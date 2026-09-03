-- Slot Filler: scan dungeon and raid loot tables from the Encounter Journal.
--
-- The journal already knows which items each dungeon and boss drops and can
-- filter by class/spec, so the drop table never needs to be maintained by
-- hand. Dungeon loot is read at Mythic Keystone difficulty (same item pool as
-- Mythic); raid loot per boss at each raid difficulty. Cached per season +
-- spec in the character's saved variables.
local _, ns = ...

local CACHE_VERSION = 7
local CACHE_MAX_AGE = 7 * 24 * 3600

local DIFF_KEYSTONE = (DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.DungeonChallenge) or 8
local DIFF_MYTHIC = (DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.DungeonMythic) or 23
local DIFF_STORY = 220
local DUNGEON_DIFFS = { [1] = true, [2] = true, [DIFF_KEYSTONE] = true, [DIFF_MYTHIC] = true, [24] = true }

-- Raid difficulties in the order the Raid tab shows them. `track` is the
-- direct drop's upgrade track this season; the Voidcore roll and the vault
-- give one track up. The Tidebound Grotto lair has a "World" difficulty in
-- place of LFR: whatever other difficulty the journal calls valid takes the
-- LFR slot.
local DID = DifficultyUtil and DifficultyUtil.ID or {}
ns.RAID_DIFFS = {
    { key = "lfr",    name = "LFR",    id = DID.PrimaryRaidLFR or 17,    track = "Veteran" },
    { key = "normal", name = "Normal", id = DID.PrimaryRaidNormal or 14, track = "Champion" },
    { key = "heroic", name = "Heroic", id = DID.PrimaryRaidHeroic or 15, track = "Hero" },
    { key = "mythic", name = "Mythic", id = DID.PrimaryRaidMythic or 16, track = "Myth" },
}
ns.RAID_DIFF_BY_KEY = {}
for _, d in ipairs(ns.RAID_DIFFS) do ns.RAID_DIFF_BY_KEY[d.key] = d end

-------------------------------------------------------------------------------
-- Spec helpers
-------------------------------------------------------------------------------
local GetSpecIndex = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
local GetSpecInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
local GetLootSpec = (C_SpecializationInfo and C_SpecializationInfo.GetLootSpecialization) or GetLootSpecialization
local GetSpecInfoByID = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoByID) or GetSpecializationInfoByID

function ns:GetActiveSpecID()
    local idx = GetSpecIndex and GetSpecIndex()
    if idx then
        local id = GetSpecInfo and GetSpecInfo(idx)
        if type(id) == "number" then return id end
    end
    return nil
end

function ns:GetLootSpecID()
    local id = GetLootSpec and GetLootSpec()
    if type(id) == "number" and id > 0 then return id end
    return self:GetActiveSpecID()
end

-- Spec the window evaluates for: manual choice, else loot spec, else active spec.
function ns:GetEvalSpecID()
    if self.cdb and self.cdb.evalSpecID then return self.cdb.evalSpecID end
    return self:GetLootSpecID()
end

function ns:SpecName(specID)
    if not specID or not GetSpecInfoByID then return "?" end
    local _, name, _, icon = GetSpecInfoByID(specID)
    return name or tostring(specID), icon
end

function ns:GetPlayerSpecs()
    local specs = {}
    local n = (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID and C_SpecializationInfo.GetNumSpecializationsForClassID(self.playerClassID))
        or (GetNumSpecializationsForClassID and GetNumSpecializationsForClassID(self.playerClassID)) or 0
    local getForClass = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForClassID) or GetSpecializationInfoForClassID
    for i = 1, n do
        local id, name, _, icon = getForClass(self.playerClassID, i)
        if id then table.insert(specs, { id = id, name = name, icon = icon }) end
    end
    return specs
end

-------------------------------------------------------------------------------
-- Journal index: instance map id / name -> journal instance id (+ tier)
-------------------------------------------------------------------------------
ns.journalByMap = {}
ns.journalByName = {}
ns.journalTier = {}

local function EnsureJournalLoaded()
    if not EncounterJournal and C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    end
end

function ns:BuildJournalIndex(force)
    if self.journalIndexBuilt and not force then return true end
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return false end
    EnsureJournalLoaded()
    wipe(self.journalByMap); wipe(self.journalByName); wipe(self.journalTier)
    local numTiers = EJ_GetNumTiers() or 0
    local savedTier = EJ_GetCurrentTier and EJ_GetCurrentTier()
    for tier = 1, numTiers do
        EJ_SelectTier(tier)
        local index = 1
        while true do
            local instanceID, name, _, _, _, _, _, _, _, _, mapID = EJ_GetInstanceByIndex(index, false)
            if not instanceID then break end
            if type(mapID) == "number" and mapID > 0 and not self.journalByMap[mapID] then
                self.journalByMap[mapID] = instanceID
            end
            local norm = self:NormalizeName(name)
            if norm and not self.journalByName[norm] then
                self.journalByName[norm] = instanceID
            end
            -- keep the LAST tier the instance appears in: the "Current Season"
            -- tier is last, and Mythic Keystone difficulty is only valid there
            self.journalTier[instanceID] = tier
            index = index + 1
        end
    end
    if savedTier and savedTier > 0 then EJ_SelectTier(savedTier) end
    self.journalIndexBuilt = true
    return true
end

function ns:JournalInstanceFor(dungeon)
    if dungeon.journalID then return dungeon.journalID end
    self:BuildJournalIndex()
    local id
    -- direct API (12.x): instance map id -> journal instance id
    if dungeon.instanceMapID and C_EncounterJournal.GetInstanceForGameMap then
        local ok, jid = pcall(C_EncounterJournal.GetInstanceForGameMap, dungeon.instanceMapID)
        if ok and type(jid) == "number" and jid > 0 then id = jid end
    end
    if not id and dungeon.instanceMapID then id = self.journalByMap[dungeon.instanceMapID] end
    if not id and dungeon.norm then
        id = self.journalByName[self.NAME_ALIASES[dungeon.norm] or dungeon.norm]
    end
    if not id and dungeon.norm then
        for norm, jid in pairs(self.journalByName) do
            if norm:find(dungeon.norm, 1, true) or dungeon.norm:find(norm, 1, true) then id = jid; break end
        end
    end
    if not id then id = self.FALLBACK_JOURNAL[dungeon.challengeMapID] end
    dungeon.journalID = id
    return id
end

-------------------------------------------------------------------------------
-- Reading one instance's loot (synchronous part)
-------------------------------------------------------------------------------
local function EquipInfo(itemID)
    local _, _, _, equipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    return equipLoc, icon, classID, subClassID
end

-- The journal's current loot list (instance or selected encounter).
local function ReadLootItems()
    local n = EJ_GetNumLoot() or 0
    local items, incomplete = {}, false
    for i = 1, n do
        local info = C_EncounterJournal.GetLootInfoByIndex(i)
        if info and info.itemID then
            if not info.link or not info.name then incomplete = true end
            local equipLoc, icon, itemClassID, subClassID = EquipInfo(info.itemID)
            table.insert(items, {
                itemID = info.itemID,
                encounterID = info.encounterID,
                name = info.name,
                link = info.link,
                icon = info.icon or icon,
                slotText = info.slot,
                armorType = info.armorType,
                equipLoc = equipLoc,
                classID = itemClassID,
                subClassID = subClassID,
                veryRare = info.displayAsVeryRare or nil,
                extremelyRare = info.displayAsExtremelyRare or nil,
                perPlayer = info.displayAsPerPlayerLoot or nil,
            })
        end
    end
    return items, incomplete, n
end

-- Key levels whose end-of-dungeon item level differs from the level below.
local function DistinctRewardLevels()
    local levels, last = {}, nil
    local maxKey = ns:MaxUsefulKey() or 10
    for k = 2, maxKey do
        local ilvl = ns:RewardIlvl(k)
        if ilvl and ilvl ~= last then
            table.insert(levels, k)
            last = ilvl
        end
    end
    if #levels == 0 then
        for k = 2, maxKey do table.insert(levels, k) end
    end
    return levels
end

-- The journal can preview loot at a keystone level; capture the links so
-- tooltips can show the item as it drops at the selected key. Missing links
-- are not fatal: Links.lua can rebuild them from bonus IDs.
local function CapturePreviewLinks(items, n)
    if not (C_EncounterJournal and C_EncounterJournal.SetPreviewMythicPlusLevel) then return end
    if #items == 0 then return end
    local byIndex = {}
    for i = 1, n do
        local info = C_EncounterJournal.GetLootInfoByIndex(i)
        if info and info.itemID then byIndex[info.itemID] = i end
    end
    local changed = false
    for _, level in ipairs(DistinctRewardLevels()) do
        local ok = pcall(C_EncounterJournal.SetPreviewMythicPlusLevel, level)
        if not ok then break end
        for _, item in ipairs(items) do
            local i = byIndex[item.itemID]
            local info = i and C_EncounterJournal.GetLootInfoByIndex(i)
            local link = info and info.link
            if link then
                -- The preview level persists in the journal, so the "base" link
                -- may already be at any level; compare against the previous
                -- stored level instead and always keep the lowest one.
                item.links = item.links or {}
                local prevLevel
                for l in pairs(item.links) do
                    if l < level and (not prevLevel or l > prevLevel) then prevLevel = l end
                end
                if not prevLevel or item.links[prevLevel] ~= link then
                    item.links[level] = link
                    changed = true
                end
            end
        end
    end
    -- previews that never changed anything are not worth keeping
    for _, item in ipairs(items) do
        if item.links then
            local count, only
            count = 0
            for _, l in pairs(item.links) do count = count + 1; only = l end
            if count == 1 and only == item.link then
                item.links = nil
            end
        end
    end
    if changed then
        -- teach Links.lua which bonus id is the track bonus
        for _, item in ipairs(items) do
            if item.links then
                local prev = item.link
                local levels = {}
                for l in pairs(item.links) do table.insert(levels, l) end
                table.sort(levels)
                for _, l in ipairs(levels) do
                    ns:LearnTrackBonusFromPair(prev, item.links[l])
                    prev = item.links[l]
                end
                break
            end
        end
    end
end

local function KeystoneDifficultyValid()
    if EJ_IsValidInstanceDifficulty and EJ_IsValidInstanceDifficulty(DIFF_KEYSTONE) then return true end
    if C_EncounterJournal.InstanceHasDifficultyID then
        local ok, has = pcall(C_EncounterJournal.InstanceHasDifficultyID, DIFF_KEYSTONE)
        if ok and has then return true end
    end
    return false
end

local function ReadInstanceLoot(journalID, classID, specID)
    local tier = ns.journalTier[journalID]
    if tier then EJ_SelectTier(tier) end
    EJ_SelectInstance(journalID)
    local diff = DIFF_MYTHIC
    if KeystoneDifficultyValid() then
        diff = DIFF_KEYSTONE
    elseif EJ_GetNumTiers then
        -- try again under the last tier ("Current Season"), where Keystone is valid
        local last = EJ_GetNumTiers()
        if last and last ~= tier then
            EJ_SelectTier(last)
            EJ_SelectInstance(journalID)
            if KeystoneDifficultyValid() then
                diff = DIFF_KEYSTONE
                ns.journalTier[journalID] = last
            else
                if tier then EJ_SelectTier(tier) end
                EJ_SelectInstance(journalID)
            end
        end
    end
    EJ_SetDifficulty(diff)
    EJ_SetLootFilter(classID, specID or 0)
    if C_EncounterJournal.SetSlotFilter and Enum and Enum.ItemSlotFilterType then
        C_EncounterJournal.SetSlotFilter(Enum.ItemSlotFilterType.NoFilter)
    end
    local items, incomplete, n = ReadLootItems()
    if not incomplete then
        CapturePreviewLinks(items, n)
    end
    return items, incomplete, n, diff
end

-------------------------------------------------------------------------------
-- Raids: the season's raids and their bosses, and one boss's loot at one
-- difficulty
-------------------------------------------------------------------------------
local function ValidDifficulty(id)
    if EJ_IsValidInstanceDifficulty and EJ_IsValidInstanceDifficulty(id) then return true end
    if C_EncounterJournal.InstanceHasDifficultyID then
        local ok, has = pcall(C_EncounterJournal.InstanceHasDifficultyID, id)
        if ok and has then return true end
    end
    return false
end

-- Difficulty ids the selected raid offers, by our key. A raid without LFR
-- (the lair) puts its other difficulty, "World", in that slot.
local function RaidDifficultyIDs()
    local ids, names, taken = {}, {}, {}
    for _, def in ipairs(ns.RAID_DIFFS) do
        if ValidDifficulty(def.id) then ids[def.key] = def.id; taken[def.id] = true end
    end
    if not ids.lfr then
        for id = 1, 300 do
            if not taken[id] and not DUNGEON_DIFFS[id] and id ~= DIFF_STORY and ValidDifficulty(id) then
                ids.lfr = id
                break
            end
        end
    end
    if DifficultyUtil and DifficultyUtil.GetDifficultyName then
        for key, id in pairs(ids) do
            local ok, name = pcall(DifficultyUtil.GetDifficultyName, id)
            if ok and type(name) == "string" and name ~= "" then names[key] = name end
        end
    end
    return ids, names
end

-- The season's raids and their bosses from the journal's last tier ("Current
-- Season"), or the tier before it when that lists none.
local function ReadRaidList()
    local raids = {}
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_GetEncounterInfoByIndex) then return raids end
    local numTiers = EJ_GetNumTiers() or 0
    for tier = numTiers, math.max(1, numTiers - 1), -1 do
        EJ_SelectTier(tier)
        local index = 1
        while true do
            local rets = { EJ_GetInstanceByIndex(index, true) }
            local instanceID, name = rets[1], rets[2]
            if not instanceID then break end
            -- shouldDisplayDifficulty is the first boolean returned (isRaid
            -- follows it); its position moved in 12.1, so it is found, not indexed.
            local shouldDisplayDifficulty
            for i = 3, #rets do
                if type(rets[i]) == "boolean" then shouldDisplayDifficulty = rets[i]; break end
            end
            local raid = { instanceID = instanceID, name = name, index = index, tier = tier, bosses = {},
                displaysDifficulty = shouldDisplayDifficulty }
            EJ_SelectInstance(instanceID)
            local b = 1
            while true do
                local bossName, _, encounterID = EJ_GetEncounterInfoByIndex(b, instanceID)
                if not encounterID then break end
                local portrait
                if EJ_GetCreatureInfo then
                    local ok, _, _, _, _, icon = pcall(EJ_GetCreatureInfo, 1, encounterID)
                    if ok then portrait = icon end
                end
                raid.bosses[b] = { encounterID = encounterID, name = bossName, index = b, portrait = portrait, loot = {} }
                b = b + 1
            end
            raid.difficulties, raid.difficultyNames = RaidDifficultyIDs()
            -- The season's world bosses sit in the journal as a raid that
            -- offers Normal only (verified 12.1: "Midnight" has normal 14,
            -- no heroic or mythic) and no difficulty selector; their gear is
            -- below every raid track, so they are left out. The lair has
            -- Heroic and Mythic too.
            local instanced = (raid.difficulties.heroic or raid.difficulties.mythic)
                and raid.displaysDifficulty ~= false
            ns:Debug(string.format("Journal raid %s: difficulty selector %s, normal %s heroic %s mythic %s -> %s", tostring(name),
                tostring(shouldDisplayDifficulty), tostring(raid.difficulties.normal), tostring(raid.difficulties.heroic),
                tostring(raid.difficulties.mythic), instanced and "kept" or "left out"))
            if #raid.bosses > 0 and instanced then table.insert(raids, raid) end
            index = index + 1
        end
        if #raids > 0 then break end
    end
    return raids
end

local function ReadEncounterLoot(raid, boss, diffID, classID, specID)
    EJ_SelectTier(raid.tier)
    EJ_SelectInstance(raid.instanceID)
    EJ_SetDifficulty(diffID)
    EJ_SelectEncounter(boss.encounterID)
    EJ_SetLootFilter(classID, specID or 0)
    if C_EncounterJournal.SetSlotFilter and Enum and Enum.ItemSlotFilterType then
        C_EncounterJournal.SetSlotFilter(Enum.ItemSlotFilterType.NoFilter)
    end
    return ReadLootItems()
end

-------------------------------------------------------------------------------
-- Cache
-------------------------------------------------------------------------------
local function CacheKey()
    return ns:GetSeasonID() or 0, ns:GetEvalSpecID() or 0
end

function ns:GetCachedLoot()
    local season, spec = CacheKey()
    local bySeason = self.cdb.lootCache[season]
    local entry = bySeason and bySeason[spec]
    if not entry or entry.version ~= CACHE_VERSION then return nil end
    return entry
end

function ns:CacheIsFresh(entry)
    if not entry then return false end
    if (time() - (entry.time or 0)) > CACHE_MAX_AGE then return false end
    if type(entry.raids) ~= "table" then return false end
    -- the pool changed?
    for _, d in ipairs(self.dungeons) do
        if not entry.dungeons[d.challengeMapID] then return false end
    end
    return true
end

function ns:StoreLoot(results, raids)
    local season, spec = CacheKey()
    self.cdb.lootCache[season] = self.cdb.lootCache[season] or {}
    self.cdb.lootCache[season][spec] = {
        version = CACHE_VERSION,
        time = time(),
        classID = self.playerClassID,
        dungeons = results,
        raids = raids or {},
    }
    return self.cdb.lootCache[season][spec]
end

-- Current loot in use:
--   dungeons[challengeMapID] = { items = {...}, difficulty = , journalID = }
--   raids = { { instanceID, name, bosses = { { encounterID, name, index, portrait,
--              loot = { [diffKey] = { items = {...}, difficulty = id } } } } } }
ns.loot = nil

function ns:GetDungeonLoot(challengeMapID)
    local entry = self.loot
    local d = entry and entry.dungeons and entry.dungeons[challengeMapID]
    return d and d.items or nil
end

-- The season's raids, in journal order; empty until loot has been scanned.
function ns:GetRaids()
    return self.loot and self.loot.raids or {}
end

function ns:GetBossLoot(boss, diffKey)
    local l = boss and boss.loot and boss.loot[diffKey]
    return l and l.items or nil
end

-- "Heroic", or the raid's own name for the slot ("World" for the lair).
function ns:RaidDifficultyName(raid, diffKey)
    local name = raid and raid.difficultyNames and raid.difficultyNames[diffKey]
    local def = self.RAID_DIFF_BY_KEY[diffKey]
    return name or (def and def.name) or tostring(diffKey)
end

-------------------------------------------------------------------------------
-- Scanner (async state machine driven by EJ_LOOT_DATA_RECIEVED + timers)
-------------------------------------------------------------------------------
local scan = nil
local MAX_RETRIES = 6

local function SaveJournalState()
    local state = {}
    if EJ_GetLootFilter then state.classID, state.specID = EJ_GetLootFilter() end
    if EJ_GetDifficulty then state.difficulty = EJ_GetDifficulty() end
    if EJ_GetCurrentTier then state.tier = EJ_GetCurrentTier() end
    if EncounterJournal then state.instanceID = EncounterJournal.instanceID end
    return state
end

local function RestoreJournalState(state)
    if not state then return end
    if state.tier and state.tier > 0 and EJ_SelectTier then EJ_SelectTier(state.tier) end
    if state.instanceID and EJ_SelectInstance then EJ_SelectInstance(state.instanceID) end
    if state.difficulty and EJ_SetDifficulty then EJ_SetDifficulty(state.difficulty) end
    if state.classID and EJ_SetLootFilter then EJ_SetLootFilter(state.classID, state.specID or 0) end
end

local function FinishScan(aborted)
    if not scan then return end
    local s = scan
    scan = nil
    RestoreJournalState(s.journalState)
    if aborted then
        ns:Debug("Loot scan aborted")
        ns.scanning = false
        ns:Fire("SCAN_PROGRESS", nil)
        return
    end
    ns.loot = ns:StoreLoot(s.results, s.raids)
    ns.scanning = false
    ns:Debug("Loot scan complete:", s.scannedCount, "dungeons")
    ns:Fire("SCAN_PROGRESS", nil)
    ns:Fire("LOOT_UPDATED")
end

local ScanStep

local function ScheduleStep(delay)
    C_Timer.After(delay or 0, function()
        if scan then ScanStep() end
    end)
end

-- keep only equippable gear (drop quest items, recipes, etc.)
local function Equippable(items)
    local out = {}
    for _, it in ipairs(items) do
        if it.equipLoc and ns.INVTYPE_SLOTS[it.equipLoc] then table.insert(out, it) end
    end
    return out
end

local function NextStep()
    scan.scannedCount = scan.scannedCount + 1
    scan.index = scan.index + 1
    scan.retries = 0
    return ScheduleStep(0)
end

-- A read that came back empty or without links: the journal is still
-- loading it. EJ_LOOT_DATA_RECIEVED retries sooner; the timer is the net.
local function Retry()
    scan.retries = scan.retries + 1
    scan.waitingForData = true
    return ScheduleStep(0.6)
end

function ScanStep()
    if not scan then return end
    if EncounterJournal and EncounterJournal:IsShown() then
        -- don't fight the player for the journal's state; resume when it closes
        scan.waitingForJournalClose = true
        return
    end
    local entry = scan.queue[scan.index]
    if not entry then
        return FinishScan(false)
    end
    if entry.boss then
        ns:Fire("SCAN_PROGRESS", scan.index, #scan.queue, entry.boss.name .. " (" .. entry.diff.name .. ")")
        local items, incomplete, n = ReadEncounterLoot(entry.raid, entry.boss, entry.diffID, scan.classID, scan.specID)
        if (incomplete or n == 0) and scan.retries < MAX_RETRIES then return Retry() end
        scan.waitingForData = false
        entry.boss.loot[entry.diff.key] = { items = Equippable(items), difficulty = entry.diffID, raw = n, incomplete = incomplete or nil }
        return NextStep()
    end
    local d = entry.dungeon
    ns:Fire("SCAN_PROGRESS", scan.index, #scan.queue, d.name)
    local journalID = ns:JournalInstanceFor(d)
    if not journalID then
        ns:Debug("No journal instance for", d.name)
        scan.results[d.challengeMapID] = { items = {}, missing = true }
        scan.index = scan.index + 1
        scan.retries = 0
        return ScheduleStep(0)
    end
    local items, incomplete, n, diffUsed = ReadInstanceLoot(journalID, scan.classID, scan.specID)
    if (incomplete or n == 0) and scan.retries < MAX_RETRIES then return Retry() end
    scan.waitingForData = false
    local equippable = Equippable(items)
    local previewCount = 0
    for _, it in ipairs(equippable) do if it.links then previewCount = previewCount + 1 end end
    scan.results[d.challengeMapID] = { items = equippable, journalID = journalID, raw = n, incomplete = incomplete or nil, previews = previewCount, difficulty = diffUsed }
    return NextStep()
end

function ns:StartLootScan(reason)
    if scan then return end
    if not self.dungeonsBuilt then
        self:Debug("Cannot scan loot yet: dungeon pool unknown")
        return
    end
    if not (EJ_GetNumLoot and C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex) then
        self:Print("Encounter Journal API unavailable; cannot scan loot.")
        return
    end
    EnsureJournalLoaded()
    local specID = self:GetEvalSpecID()
    scan = {
        queue = {},
        index = 1,
        retries = 0,
        results = {},
        scannedCount = 0,
        classID = self.playerClassID,
        specID = specID,
        journalState = SaveJournalState(),
    }
    for _, d in ipairs(self.dungeons) do table.insert(scan.queue, { dungeon = d }) end
    -- raid bosses after the dungeons: selecting an encounter narrows the
    -- journal's loot list, and dungeons are read with none selected
    scan.raids = ReadRaidList()
    for _, raid in ipairs(scan.raids) do
        for _, boss in ipairs(raid.bosses) do
            for _, def in ipairs(ns.RAID_DIFFS) do
                local id = raid.difficulties[def.key]
                if id then table.insert(scan.queue, { raid = raid, boss = boss, diff = def, diffID = id }) end
            end
        end
    end
    self.scanning = true
    self:Debug("Loot scan started", reason or "", "spec", specID)
    ScanStep()
end

function ns:RescanLoot(verbose)
    if scan then
        if verbose then self:Print("Scan already in progress.") end
        return
    end
    if verbose then self:Print("Scanning dungeon and raid loot tables for", (self:SpecName(self:GetEvalSpecID()))) end
    self:StartLootScan("manual")
end

-- Load from cache if fresh, else scan.
function ns:EnsureLoot(force)
    if not self.dungeonsBuilt then return end
    local entry = self:GetCachedLoot()
    if entry and self:CacheIsFresh(entry) and not force then
        if self.loot ~= entry then
            self.loot = entry
            self:Fire("LOOT_UPDATED")
        end
        return
    end
    -- show stale cache while rescanning
    if entry and entry.dungeons then self.loot = entry end
    self:StartLootScan(force and "forced" or "cache-miss")
end

function ns:IsScanning()
    return scan ~= nil
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
ns:On("LOGIN", function()
    ns:RegisterEvent("EJ_LOOT_DATA_RECIEVED", function()
        if scan and scan.waitingForData then
            scan.waitingForData = false
            ScheduleStep(0.05)
        end
    end)
    local function SpecChanged()
        ns:Schedule("spec", 0.5, function()
            ns.loot = nil
            ns:EnsureLoot(false)
            ns:Fire("SPEC_CHANGED")
        end)
    end
    ns:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED", SpecChanged)
    ns:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(unit)
        if unit == "player" or unit == nil then SpecChanged() end
    end)
    -- resume a scan that paused while the journal was open
    if EncounterJournal then
        EncounterJournal:HookScript("OnHide", function()
            if scan and scan.waitingForJournalClose then
                scan.waitingForJournalClose = false
                ScheduleStep(0.2)
            end
        end)
    else
        -- hook once the Blizzard addon loads
        ns:RegisterEvent("ADDON_LOADED", function(name)
            if name == "Blizzard_EncounterJournal" and EncounterJournal and not ns.ejHooked then
                ns.ejHooked = true
                EncounterJournal:HookScript("OnHide", function()
                    if scan and scan.waitingForJournalClose then
                        scan.waitingForJournalClose = false
                        ScheduleStep(0.2)
                    end
                end)
            end
        end)
    end
end)

ns:On("SEASON_READY", function()
    ns:EnsureLoot(false)
end)
