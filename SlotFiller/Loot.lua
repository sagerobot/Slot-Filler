-- Slot Filler: scan dungeon loot tables from the Encounter Journal.
--
-- The journal already knows which items each dungeon drops and can filter by
-- class/spec, so the drop table never needs to be maintained by hand. Loot is
-- read at Mythic Keystone difficulty (same item pool as Mythic), cached per
-- season + spec in the character's saved variables.
local _, ns = ...

local CACHE_VERSION = 3
local CACHE_MAX_AGE = 7 * 24 * 3600

local DIFF_KEYSTONE = (DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.DungeonChallenge) or 8
local DIFF_MYTHIC = (DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.DungeonMythic) or 23

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
    if not incomplete then
        CapturePreviewLinks(items, n)
    end
    return items, incomplete, n, diff
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
    -- the pool changed?
    for _, d in ipairs(self.dungeons) do
        if not entry.dungeons[d.challengeMapID] then return false end
    end
    return true
end

function ns:StoreLoot(results)
    local season, spec = CacheKey()
    self.cdb.lootCache[season] = self.cdb.lootCache[season] or {}
    self.cdb.lootCache[season][spec] = {
        version = CACHE_VERSION,
        time = time(),
        classID = self.playerClassID,
        dungeons = results,
    }
    return self.cdb.lootCache[season][spec]
end

-- Current loot in use: [challengeMapID] = { items = {...}, difficulty = , journalID = }
ns.loot = nil

function ns:GetDungeonLoot(challengeMapID)
    local entry = self.loot
    local d = entry and entry.dungeons and entry.dungeons[challengeMapID]
    return d and d.items or nil
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
    ns.loot = ns:StoreLoot(s.results)
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

function ScanStep()
    if not scan then return end
    if EncounterJournal and EncounterJournal:IsShown() then
        -- don't fight the player for the journal's state; resume when it closes
        scan.waitingForJournalClose = true
        return
    end
    local d = scan.queue[scan.index]
    if not d then
        return FinishScan(false)
    end
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
    if (incomplete or n == 0) and scan.retries < MAX_RETRIES then
        scan.retries = scan.retries + 1
        scan.waitingForData = true
        -- EJ_LOOT_DATA_RECIEVED will retry sooner; this is the safety net
        return ScheduleStep(0.6)
    end
    scan.waitingForData = false
    -- keep only equippable gear (drop quest items, recipes, etc.)
    local equippable = {}
    for _, it in ipairs(items) do
        if it.equipLoc and ns.INVTYPE_SLOTS[it.equipLoc] then
            table.insert(equippable, it)
        end
    end
    local previewCount = 0
    for _, it in ipairs(equippable) do if it.links then previewCount = previewCount + 1 end end
    scan.results[d.challengeMapID] = { items = equippable, journalID = journalID, raw = n, incomplete = incomplete or nil, previews = previewCount, difficulty = diffUsed }
    scan.scannedCount = scan.scannedCount + 1
    scan.index = scan.index + 1
    scan.retries = 0
    return ScheduleStep(0)
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
    for _, d in ipairs(self.dungeons) do table.insert(scan.queue, d) end
    self.scanning = true
    self:Debug("Loot scan started", reason or "", "spec", specID)
    ScanStep()
end

function ns:RescanLoot(verbose)
    if scan then
        if verbose then self:Print("Scan already in progress.") end
        return
    end
    if verbose then self:Print("Scanning dungeon loot tables for", (self:SpecName(self:GetEvalSpecID()))) end
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
