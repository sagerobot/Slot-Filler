-- Slot Filler: dungeon and raid loot tables from the Encounter Journal.
--
-- The journal knows which items each dungeon and boss drops and filters by
-- class and spec, so no drop table is maintained by hand. Dungeon loot is
-- read at Mythic Keystone difficulty (the Mythic item pool); raid loot per
-- boss at each raid difficulty. Cached per season and spec in the
-- character's saved variables.
local _, ns = ...

local CACHE_VERSION = 11
local CACHE_MAX_AGE = 7 * 24 * 3600

local DID = DifficultyUtil.ID
local DIFF_KEYSTONE = DID.DungeonChallenge
local DIFF_MYTHIC = DID.DungeonMythic
local DIFF_STORY = 220
local DUNGEON_DIFFS = { [1] = true, [2] = true, [DIFF_KEYSTONE] = true, [DIFF_MYTHIC] = true, [24] = true }

-- Raid difficulties in the order the Raid tab shows them. `track` is the
-- direct drop's upgrade track this season; the Voidcore roll and the vault
-- give one track up. The Tidebound Grotto lair has a "World" difficulty in
-- place of LFR: whatever other difficulty the journal calls valid takes the
-- LFR slot.
ns.RAID_DIFFS = {
    { key = "lfr",    name = "LFR",    id = DID.PrimaryRaidLFR,    track = "Veteran" },
    { key = "normal", name = "Normal", id = DID.PrimaryRaidNormal, track = "Champion" },
    { key = "heroic", name = "Heroic", id = DID.PrimaryRaidHeroic, track = "Hero" },
    { key = "mythic", name = "Mythic", id = DID.PrimaryRaidMythic, track = "Myth" },
}
ns.RAID_DIFF_BY_KEY = {}
for _, d in ipairs(ns.RAID_DIFFS) do ns.RAID_DIFF_BY_KEY[d.key] = d end

-------------------------------------------------------------------------------
-- Specs. On 12.1 the active spec is under C_SpecializationInfo; the loot
-- spec and the per-ID lookups are still globals.
-------------------------------------------------------------------------------
function ns:GetActiveSpecID()
    local idx = C_SpecializationInfo.GetSpecialization()
    local id = idx and C_SpecializationInfo.GetSpecializationInfo(idx)
    return type(id) == "number" and id or nil
end

function ns:GetLootSpecID()
    local id = GetLootSpecialization()
    if type(id) == "number" and id > 0 then return id end
    return self:GetActiveSpecID()
end

-- The spec the window evaluates for: the pinned one, else the loot spec.
function ns:GetEvalSpecID()
    return (self.cdb and self.cdb.evalSpecID) or self:GetLootSpecID()
end

function ns:SpecName(specID)
    if not specID then return "?" end
    local _, name, _, icon = GetSpecializationInfoByID(specID)
    return name or tostring(specID), icon
end

function ns:GetPlayerSpecs()
    local specs = {}
    for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(self.playerClassID) or 0 do
        local id, name, _, icon = GetSpecializationInfoForClassID(self.playerClassID, i)
        if id then specs[#specs + 1] = { id = id, name = name, icon = icon } end
    end
    return specs
end

-- The spec button: follow the loot spec, then each spec in turn.
function ns:CycleEvalSpec()
    local specs = self:GetPlayerSpecs()
    local cur, nextID = self.cdb.evalSpecID, nil
    if cur == nil then
        nextID = specs[1] and specs[1].id
    else
        for i, s in ipairs(specs) do
            if s.id == cur then nextID = specs[i + 1] and specs[i + 1].id; break end
        end
    end
    self.cdb.evalSpecID = nextID
    self.loot = nil
    self:EnsureLoot(false)
    self:Fire("SETTINGS_CHANGED")
end

-------------------------------------------------------------------------------
-- Journal index: instance map id / name -> journal instance id (+ tier)
-------------------------------------------------------------------------------
ns.journalByMap = {}
ns.journalByName = {}
ns.journalTier = {}

local function EnsureJournalLoaded()
    if not EncounterJournal then pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal") end
end

-- Runs fn once the Blizzard journal frame exists (now, or when its addon loads).
function ns:WhenJournalLoaded(fn)
    if EncounterJournal then fn(); return end
    self:RegisterEvent("ADDON_LOADED", function(name)
        if name == "Blizzard_EncounterJournal" and EncounterJournal then fn() end
    end)
end

function ns:BuildJournalIndex()
    if self.journalIndexBuilt then return end
    EnsureJournalLoaded()
    local savedTier = EJ_GetCurrentTier()
    for tier = 1, EJ_GetNumTiers() or 0 do
        EJ_SelectTier(tier)
        local index = 1
        while true do
            local instanceID, name, _, _, _, _, _, _, _, _, mapID = EJ_GetInstanceByIndex(index, false)
            if not instanceID then break end
            if type(mapID) == "number" and mapID > 0 and not self.journalByMap[mapID] then self.journalByMap[mapID] = instanceID end
            local norm = self:NormalizeName(name)
            if norm and not self.journalByName[norm] then self.journalByName[norm] = instanceID end
            -- the LAST tier the instance appears in: the "Current Season"
            -- tier is last, and Mythic Keystone difficulty is only valid there
            self.journalTier[instanceID] = tier
            index = index + 1
        end
    end
    if savedTier and savedTier > 0 then EJ_SelectTier(savedTier) end
    self.journalIndexBuilt = true
end

function ns:JournalInstanceFor(dungeon)
    if dungeon.journalID then return dungeon.journalID end
    self:BuildJournalIndex()
    local id
    if dungeon.instanceMapID then
        local ok, jid = pcall(C_EncounterJournal.GetInstanceForGameMap, dungeon.instanceMapID)
        if ok and type(jid) == "number" and jid > 0 then id = jid end
        id = id or self.journalByMap[dungeon.instanceMapID]
    end
    if not id and dungeon.norm then id = self.journalByName[dungeon.norm] end
    if not id and dungeon.norm then
        for norm, jid in pairs(self.journalByName) do
            if norm:find(dungeon.norm, 1, true) or dungeon.norm:find(norm, 1, true) then id = jid; break end
        end
    end
    dungeon.journalID = id or self.SEASON.journalInstances[dungeon.challengeMapID]
    return dungeon.journalID
end

-------------------------------------------------------------------------------
-- Reading the journal's loot
-------------------------------------------------------------------------------
local function EquipInfo(itemID)
    local _, _, _, equipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    return equipLoc, icon, classID, subClassID
end

local function ValidDifficulty(id)
    if EJ_IsValidInstanceDifficulty(id) then return true end
    local ok, has = pcall(C_EncounterJournal.InstanceHasDifficultyID, id)
    return ok and has == true
end

-- The class's current tier set from the journal's Class Sets tab: the set
-- whose pieces are exactly the five tier slots (the PvP set has eight),
-- the highest base item level among those; its pieces by inventory type.
-- Tier tokens are judged as the piece they turn into.
local TIER_INV = { INVTYPE_HEAD = "head", INVTYPE_SHOULDER = "shoulder", INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest",
    INVTYPE_HAND = "hands", INVTYPE_LEGS = "legs" }

local function ReadClassSet(classID, specID)
    local savedClass, savedSpec
    local ok, c, s = pcall(C_LootJournal.GetClassAndSpecFilters)
    if ok then savedClass, savedSpec = c, s end
    pcall(C_LootJournal.SetClassAndSpecFilters, classID, specID or 0)
    local ok2, sets = pcall(C_LootJournal.GetFilteredItemSets)
    if savedClass then pcall(C_LootJournal.SetClassAndSpecFilters, savedClass, savedSpec or 0) end
    if not ok2 or type(sets) ~= "table" then return nil end

    local function Pieces(setID)
        local ok3, items = pcall(C_LootJournal.GetItemSetItems, setID)
        if not ok3 or type(items) ~= "table" then return nil end
        local pieces, slots, n = {}, {}, 0
        for _, info in ipairs(items) do
            local equipLoc, icon, itemClassID, subClassID = EquipInfo(info.itemID or 0)
            if equipLoc and ns.INVTYPE_SLOTS[equipLoc] then
                pieces[equipLoc] = { itemID = info.itemID, link = "item:" .. info.itemID, icon = icon, equipLoc = equipLoc,
                    classID = itemClassID, subClassID = subClassID, piece = true }
                n = n + 1
                if TIER_INV[equipLoc] then slots[TIER_INV[equipLoc]] = true end
            end
        end
        local tierSlots = 0
        for _ in pairs(slots) do tierSlots = tierSlots + 1 end
        return pieces, n, tierSlots == 5 and n == 5
    end

    local best, bestPieces
    for _, set in ipairs(sets) do
        local lvl = tonumber(set.itemLevel) or 0
        local pieces, n, tier
        if set.setID then pieces, n, tier = Pieces(set.setID) end
        if pieces and n > 0 then
            -- a tier-shaped set beats any other; then the highest base level
            if not best or (tier and not best.tier) or (tier == best.tier and (lvl > best.itemLevel or (lvl == best.itemLevel and set.setID > best.setID))) then
                best, bestPieces = { setID = set.setID, name = set.name, itemLevel = lvl, tier = tier }, pieces
            end
        end
    end
    if not best then return nil end
    for _, piece in pairs(bestPieces) do ns:FillItemInfo(piece) end
    best.pieces = bestPieces
    ns:Debug(string.format("Class set: %s (%d)%s", tostring(best.name), best.setID, best.tier and "" or " (no five-slot set found)"))
    return best
end

local function CopyPiece(p, noRoll)
    return { itemID = p.itemID, name = p.name, link = p.link, icon = p.icon, equipLoc = p.equipLoc,
        classID = p.classID, subClassID = p.subClassID, piece = true, noRoll = noRoll }
end

local function SetPiece(set, inv)
    return set.pieces[inv] or (inv == "INVTYPE_CHEST" and set.pieces.INVTYPE_ROBE) or nil
end

local TIER_ORDER = { "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_HAND", "INVTYPE_LEGS" }

-- A tier token gets the set piece it becomes; one traded for any slot
-- gets all five. That one (the omni token) is unique and outside the
-- bonus roll pool, so it and its pieces carry noRoll; slot tokens roll.
local function AttachPieces(it, set)
    if not it.token then return end
    local omni = it.equipLoc == "TIER_ANY"
    if omni then it.noRoll = true end
    if not set or not set.pieces then return end
    if omni then
        local pieces = {}
        for _, inv in ipairs(TIER_ORDER) do
            local p = SetPiece(set, inv)
            if p then pieces[#pieces + 1] = CopyPiece(p, true) end
        end
        if #pieces > 0 then it.pieces = pieces end
    else
        local p = SetPiece(set, it.equipLoc)
        if p then it.piece = CopyPiece(p) end
    end
end

-- The inventory type a tier token stands for, from the slot the journal
-- names for it ("Head"); nil when the text is not a slot name.
local function TokenEquipLoc(slotText)
    local want = ns:NormalizeName(slotText)
    if not want or want == "" then return nil end
    for _, s in ipairs(ns.SLOTS) do
        if s.inv and ns:NormalizeName(s.name) == want then return s.inv end
    end
    return nil
end

-- The journal's current loot list (instance or selected encounter): the
-- equippable items, whether any is still missing its link or level, and
-- the raw count.
local function ReadLootItems()
    local n = EJ_GetNumLoot() or 0
    local items, incomplete = {}, false
    for i = 1, n do
        local info = C_EncounterJournal.GetLootInfoByIndex(i)
        if info and info.itemID then
            if not info.link or not info.name then incomplete = true end
            local equipLoc, icon, itemClassID, subClassID = EquipInfo(info.itemID)
            -- a tier token is not equippable itself and is listed under the
            -- slot it becomes: the season table knows this season's, else
            -- the slot the journal names (it names none for the current ones)
            local token
            if not (equipLoc and ns.INVTYPE_SLOTS[equipLoc]) then
                local inv = ns:ShippedTokenSlot(info.itemID) or (info.slot and TokenEquipLoc(info.slot))
                if inv then equipLoc, token = inv, true end
            end
            if equipLoc and ns.INVTYPE_SLOTS[equipLoc] then
                -- the link's level is only right while the journal holds this
                -- loot; remembered here so a later login need not resolve it
                local ilvl = info.link and ns.ItemLevelOf(info.link)
                items[#items + 1] = {
                    itemID = info.itemID, encounterID = info.encounterID, name = info.name, link = info.link,
                    ilvl = ilvl and ilvl > 0 and ilvl or nil, icon = info.icon or icon, slotText = info.slot,
                    armorType = info.armorType, token = token, equipLoc = equipLoc, classID = itemClassID, subClassID = subClassID,
                    veryRare = info.displayAsVeryRare or nil, extremelyRare = info.displayAsExtremelyRare or nil,
                    perPlayer = info.displayAsPerPlayerLoot or nil,
                }
            end
        end
    end
    return items, incomplete, n
end

-- Key levels whose end-of-dungeon item level differs from the level below.
local function DistinctRewardLevels()
    local levels, last = {}, nil
    local maxKey = ns:MaxUsefulKey()
    for k = 2, maxKey do
        local ilvl = ns:RewardIlvl(k)
        if ilvl and ilvl ~= last then levels[#levels + 1] = k; last = ilvl end
    end
    if #levels == 0 then
        for k = 2, maxKey do levels[#levels + 1] = k end
    end
    return levels
end

-- The journal can preview loot at a keystone level; the links are captured
-- so tooltips can show the item as it drops at the selected key. Missing
-- links are not fatal: Links.lua can rebuild them from bonus IDs.
local function CapturePreviewLinks(items, n)
    if #items == 0 then return end
    local byIndex = {}
    for i = 1, n do
        local info = C_EncounterJournal.GetLootInfoByIndex(i)
        if info and info.itemID then byIndex[info.itemID] = i end
    end
    local changed = false
    for _, level in ipairs(DistinctRewardLevels()) do
        if not pcall(C_EncounterJournal.SetPreviewMythicPlusLevel, level) then break end
        for _, item in ipairs(items) do
            local i = byIndex[item.itemID]
            local info = i and C_EncounterJournal.GetLootInfoByIndex(i)
            if info and info.link then
                -- The preview level persists in the journal, so the "base" link
                -- may already be at any level; compare against the previous
                -- stored level instead and always keep the lowest one.
                item.links = item.links or {}
                local prevLevel
                for l in pairs(item.links) do
                    if l < level and (not prevLevel or l > prevLevel) then prevLevel = l end
                end
                if not prevLevel or item.links[prevLevel] ~= info.link then
                    item.links[level] = info.link
                    changed = true
                end
            end
        end
    end
    -- previews that never changed anything are not worth keeping
    for _, item in ipairs(items) do
        if item.links then
            local count, only = 0, nil
            for _, l in pairs(item.links) do count = count + 1; only = l end
            if count == 1 and only == item.link then item.links = nil end
        end
    end
    -- teach Links.lua which bonus id is the track bonus
    for _, item in ipairs(changed and items or {}) do
        if item.links then
            local prev, levels = item.link, {}
            for l in pairs(item.links) do levels[#levels + 1] = l end
            table.sort(levels)
            for _, l in ipairs(levels) do
                ns:LearnTrackBonusFromPair(prev, item.links[l])
                prev = item.links[l]
            end
            break
        end
    end
end

local function SelectLootFilter(classID, specID)
    EJ_SetLootFilter(classID, specID or 0)
    C_EncounterJournal.SetSlotFilter(Enum.ItemSlotFilterType.NoFilter)
end

local function ReadInstanceLoot(journalID, classID, specID)
    local tier = ns.journalTier[journalID]
    if tier then EJ_SelectTier(tier) end
    EJ_SelectInstance(journalID)
    local diff = DIFF_MYTHIC
    if ValidDifficulty(DIFF_KEYSTONE) then
        diff = DIFF_KEYSTONE
    else
        -- try again under the last tier ("Current Season"), where Keystone is valid
        local last = EJ_GetNumTiers()
        if last and last ~= tier then
            EJ_SelectTier(last)
            EJ_SelectInstance(journalID)
            if ValidDifficulty(DIFF_KEYSTONE) then
                diff = DIFF_KEYSTONE
                ns.journalTier[journalID] = last
            else
                if tier then EJ_SelectTier(tier) end
                EJ_SelectInstance(journalID)
            end
        end
    end
    EJ_SetDifficulty(diff)
    SelectLootFilter(classID, specID)
    local items, incomplete, n = ReadLootItems()
    if not incomplete then CapturePreviewLinks(items, n) end
    return items, incomplete, n, diff
end

local function ReadEncounterLoot(raid, boss, diffID, classID, specID)
    EJ_SelectTier(raid.tier)
    EJ_SelectInstance(raid.instanceID)
    EJ_SetDifficulty(diffID)
    EJ_SelectEncounter(boss.encounterID)
    SelectLootFilter(classID, specID)
    return ReadLootItems()
end

-------------------------------------------------------------------------------
-- Raids: the season's raids and their bosses
-------------------------------------------------------------------------------
-- Difficulty ids the selected raid offers, by our key. A raid without LFR
-- (the lair) puts its other difficulty, "World", in that slot.
local function RaidDifficultyIDs()
    local ids, names, taken = {}, {}, {}
    for _, def in ipairs(ns.RAID_DIFFS) do
        if ValidDifficulty(def.id) then ids[def.key] = def.id; taken[def.id] = true end
    end
    if not ids.lfr then
        for id = 1, 300 do
            if not taken[id] and not DUNGEON_DIFFS[id] and id ~= DIFF_STORY and ValidDifficulty(id) then ids.lfr = id; break end
        end
    end
    for key, id in pairs(ids) do
        local ok, name = pcall(DifficultyUtil.GetDifficultyName, id)
        if ok and type(name) == "string" and name ~= "" then names[key] = name end
    end
    return ids, names
end

-- The season's raids and their bosses from the journal's last tier ("Current
-- Season"), or the tier before it when that lists none.
local function ReadRaidList()
    local raids = {}
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
            local displaysDifficulty
            for i = 3, #rets do
                if type(rets[i]) == "boolean" then displaysDifficulty = rets[i]; break end
            end
            local raid = { instanceID = instanceID, name = name, index = index, tier = tier, bosses = {}, displaysDifficulty = displaysDifficulty }
            EJ_SelectInstance(instanceID)
            local b = 1
            while true do
                local bossName, _, encounterID = EJ_GetEncounterInfoByIndex(b, instanceID)
                if not encounterID then break end
                local ok, _, _, _, _, portrait = pcall(EJ_GetCreatureInfo, 1, encounterID)
                raid.bosses[b] = { encounterID = encounterID, name = bossName, index = b, portrait = ok and portrait or nil, loot = {} }
                b = b + 1
            end
            raid.difficulties, raid.difficultyNames = RaidDifficultyIDs()
            -- The season's world bosses sit in the journal as a raid that
            -- offers Normal only (verified 12.1: "Midnight" has normal 14,
            -- no heroic or mythic) and no difficulty selector; their gear is
            -- below every raid track, so they are left out. The lair has
            -- Heroic and Mythic too.
            local instanced = (raid.difficulties.heroic or raid.difficulties.mythic) and displaysDifficulty ~= false
            ns:Debug(string.format("Journal raid %s: difficulty selector %s, normal %s heroic %s mythic %s -> %s", tostring(name),
                tostring(displaysDifficulty), tostring(raid.difficulties.normal), tostring(raid.difficulties.heroic),
                tostring(raid.difficulties.mythic), instanced and "kept" or "left out"))
            if #raid.bosses > 0 and instanced then raids[#raids + 1] = raid end
            index = index + 1
        end
        if #raids > 0 then break end
    end
    return raids
end

-------------------------------------------------------------------------------
-- Cache
-------------------------------------------------------------------------------
local function CacheKey()
    return ns:GetSeasonID() or 0, ns:GetEvalSpecID() or 0
end

function ns:GetCachedLoot()
    local season, spec = CacheKey()
    local entry = self.cdb.lootCache[season] and self.cdb.lootCache[season][spec]
    if not entry or entry.version ~= CACHE_VERSION then return nil end
    return entry
end

function ns:CacheIsFresh(entry)
    if not entry or (time() - (entry.time or 0)) > CACHE_MAX_AGE or type(entry.raids) ~= "table" then return false end
    for _, d in ipairs(self.dungeons) do
        if not entry.dungeons[d.challengeMapID] then return false end -- the pool changed
    end
    return true
end

function ns:StoreLoot(results, raids, classSet)
    local season, spec = CacheKey()
    self.cdb.lootCache[season] = self.cdb.lootCache[season] or {}
    self.cdb.lootCache[season][spec] = {
        version = CACHE_VERSION, time = time(), classID = self.playerClassID,
        dungeons = results, raids = raids or {}, classSet = classSet,
    }
    return self.cdb.lootCache[season][spec]
end

-- The loot in use:
--   dungeons[challengeMapID] = { items = {...}, difficulty = , journalID = }
--   raids = { { instanceID, name, bosses = { { encounterID, name, index, portrait,
--              loot = { [diffKey] = { items = {...}, difficulty = id } } } } } }
--   classSet = { setID, name, pieces = { [equipLoc] = piece } }
ns.loot = nil

function ns:GetDungeonLoot(challengeMapID)
    local d = self.loot and self.loot.dungeons[challengeMapID]
    return d and d.items or nil
end

-- The season's raids, in journal order; empty until loot has been scanned.
function ns:GetRaids()
    return self.loot and self.loot.raids or {}
end

function ns:GetBossLoot(boss, diffKey)
    local l = boss and boss.loot[diffKey]
    return l and l.items or nil
end

function ns:RaidOfBoss(boss)
    for _, raid in ipairs(self:GetRaids()) do
        for _, b in ipairs(raid.bosses) do
            if b == boss then return raid end
        end
    end
    return nil
end

-- "Heroic", or the raid's own name for the slot ("World" for the lair).
function ns:RaidDifficultyName(raid, diffKey)
    local name = raid and raid.difficultyNames and raid.difficultyNames[diffKey]
    local def = self.RAID_DIFF_BY_KEY[diffKey]
    return name or (def and def.name) or tostring(diffKey)
end

-- A loot table entry for an item ID (any dungeon or boss), or nil.
function ns:LootItem(itemID)
    if not self.loot then return nil end
    for _, d in pairs(self.loot.dungeons) do
        for _, item in ipairs(d.items or {}) do
            if item.itemID == itemID then return item end
        end
    end
    for _, raid in ipairs(self.loot.raids) do
        for _, boss in ipairs(raid.bosses) do
            for _, l in pairs(boss.loot) do
                for _, item in ipairs(l.items or {}) do
                    if item.itemID == itemID then return item end
                end
            end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Scanner (async state machine driven by EJ_LOOT_DATA_RECIEVED + timers)
-------------------------------------------------------------------------------
local scan = nil
local MAX_RETRIES = 6

local function SaveJournalState()
    local state = { difficulty = EJ_GetDifficulty(), tier = EJ_GetCurrentTier(), instanceID = EncounterJournal and EncounterJournal.instanceID }
    state.classID, state.specID = EJ_GetLootFilter()
    return state
end

local function RestoreJournalState(state)
    if not state then return end
    if state.tier and state.tier > 0 then EJ_SelectTier(state.tier) end
    if state.instanceID then EJ_SelectInstance(state.instanceID) end
    if state.difficulty then EJ_SetDifficulty(state.difficulty) end
    if state.classID then EJ_SetLootFilter(state.classID, state.specID or 0) end
end

-- Asks the journal for one source's loot without keeping the answer: the
-- client builds a Voidcache tooltip's item list from it, and after a login
-- the cached loot means nothing has asked. Nothing while the journal is
-- open or in combat; the journal's state is saved and restored around it.
-- Returns asked, the number of loot entries the journal lists right now
-- (0 until its answer arrives), and whether they were still incomplete.
-- With `keep`, the journal is left on the source (a boss's loot arrives
-- only while it stays selected); RestoreJournalAfterTouch puts it back.
local touchState
function ns:RestoreJournalAfterTouch()
    if touchState and not (EncounterJournal and EncounterJournal:IsShown()) then
        RestoreJournalState(touchState)
        touchState = nil
    end
end

function ns:TouchJournalLoot(source, keep)
    if not source then return false, 0, "no source" end
    if EncounterJournal and EncounterJournal:IsShown() then return false, 0, "journal open" end
    if InCombatLockdown() then return false, 0, "combat" end
    EnsureJournalLoaded()
    local state = touchState or SaveJournalState()
    if keep then touchState = state end
    local classID, specID = self.playerClassID, self:GetEvalSpecID()
    local asked, n, incomplete, why = false, 0, nil, "no source"
    if source.kind == "dungeon" and source.dungeon then
        local journalID = self:JournalInstanceFor(source.dungeon)
        if journalID then
            local _, inc, count = ReadInstanceLoot(journalID, classID, specID)
            asked, n, incomplete, why = true, count or 0, inc, nil
        else
            why = "no journal instance"
        end
    elseif source.kind == "boss" and source.raid and source.boss then
        local diffID = source.raid.difficulties[source.diffKey]
        if diffID then
            local _, inc, count = ReadEncounterLoot(source.raid, source.boss, diffID, classID, specID)
            asked, n, incomplete, why = true, count or 0, inc, nil
        else
            why = "no difficulty id"
        end
    end
    if not keep then RestoreJournalState(state) end
    return asked, n, incomplete and "incomplete" or why
end

local function FinishScan()
    local s = scan
    scan = nil
    RestoreJournalState(s.journalState)
    ns.loot = ns:StoreLoot(s.results, s.raids, s.classSet)
    ns.scanning = false
    ns:Debug("Loot scan complete")
    ns:Fire("SCAN_PROGRESS", nil)
    ns:Fire("LOOT_UPDATED")
end

local ScanStep

local function ScheduleStep(delay)
    C_Timer.After(delay or 0, function()
        if scan then ScanStep() end
    end)
end

local function NextStep()
    scan.index = scan.index + 1
    scan.retries = 0
    ScheduleStep(0)
end

-- A read that came back empty or without links: the journal is still
-- loading it. EJ_LOOT_DATA_RECIEVED retries sooner; the timer is the net.
local function Retry()
    scan.retries = scan.retries + 1
    scan.waitingForData = true
    ScheduleStep(0.6)
end

function ScanStep()
    if EncounterJournal and EncounterJournal:IsShown() then
        -- don't fight the player for the journal's state; resume when it closes
        scan.waitingForJournalClose = true
        return
    end
    local entry = scan.queue[scan.index]
    if not entry then return FinishScan() end
    if entry.boss then
        ns:Fire("SCAN_PROGRESS", scan.index, #scan.queue, entry.boss.name .. " (" .. entry.diff.name .. ")")
        local items, incomplete, n = ReadEncounterLoot(entry.raid, entry.boss, entry.diffID, scan.classID, scan.specID)
        for _, it in ipairs(items) do
            if not it.ilvl then incomplete = true; break end
            AttachPieces(it, scan.classSet)
        end
        if (incomplete or n == 0) and scan.retries < MAX_RETRIES then return Retry() end
        scan.waitingForData = false
        entry.boss.loot[entry.diff.key] = { items = items, difficulty = entry.diffID, raw = n, incomplete = incomplete or nil }
        return NextStep()
    end
    local d = entry.dungeon
    ns:Fire("SCAN_PROGRESS", scan.index, #scan.queue, d.name)
    local journalID = ns:JournalInstanceFor(d)
    if not journalID then
        ns:Debug("No journal instance for", d.name)
        scan.results[d.challengeMapID] = { items = {}, missing = true }
        return NextStep()
    end
    local items, incomplete, n, diffUsed = ReadInstanceLoot(journalID, scan.classID, scan.specID)
    if (incomplete or n == 0) and scan.retries < MAX_RETRIES then return Retry() end
    scan.waitingForData = false
    local previews = 0
    for _, it in ipairs(items) do if it.links then previews = previews + 1 end end
    scan.results[d.challengeMapID] = { items = items, journalID = journalID, raw = n, incomplete = incomplete or nil, previews = previews, difficulty = diffUsed }
    return NextStep()
end

function ns:StartLootScan(reason)
    if scan then return end
    if not self.dungeonsBuilt then
        self:Debug("Cannot scan loot yet: dungeon pool unknown")
        return
    end
    EnsureJournalLoaded()
    local specID = self:GetEvalSpecID()
    scan = { queue = {}, index = 1, retries = 0, results = {}, classID = self.playerClassID, specID = specID, journalState = SaveJournalState() }
    scan.classSet = ReadClassSet(scan.classID, specID)
    for _, d in ipairs(self.dungeons) do scan.queue[#scan.queue + 1] = { dungeon = d } end
    -- raid bosses after the dungeons: selecting an encounter narrows the
    -- journal's loot list, and dungeons are read with none selected
    scan.raids = ReadRaidList()
    for _, raid in ipairs(scan.raids) do
        for _, boss in ipairs(raid.bosses) do
            for _, def in ipairs(ns.RAID_DIFFS) do
                local id = raid.difficulties[def.key]
                if id then scan.queue[#scan.queue + 1] = { raid = raid, boss = boss, diff = def, diffID = id } end
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

-- Loads from the cache when it is fresh, else scans (showing the stale
-- cache meanwhile).
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
    if entry and entry.dungeons then self.loot = entry end
    self:StartLootScan(force and "forced" or "cache-miss")
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
    ns:WhenJournalLoaded(function()
        EncounterJournal:HookScript("OnHide", function()
            if scan and scan.waitingForJournalClose then
                scan.waitingForJournalClose = false
                ScheduleStep(0.2)
            end
        end)
    end)
end)

ns:On("SEASON_READY", function() ns:EnsureLoot(false) end)
