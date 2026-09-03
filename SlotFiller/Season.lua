-- Slot Filler: current Mythic+ season, dungeon pool, reward item levels.
local _, ns = ...

-------------------------------------------------------------------------------
-- Per-season defaults. Everything here is a fallback: the live client is asked
-- first (C_ChallengeMode / C_MythicPlus), and the track table is calibrated
-- against the player's own items. Update when a new season starts.
-- seasonID = C_MythicPlus.GetCurrentSeason()
-------------------------------------------------------------------------------
ns.SEASON_DATA = {
    -- Filled in by ns.SEASON_DATA_LATEST below; keyed by season id when known.
}

-- Used when the live season id is not in SEASON_DATA.
-- championBase: item level of Champion 1/8. Every other track follows from
-- it (13 item levels per tier, 3.25 per upgrade step). 0 = unknown; the
-- table is then bootstrapped from the player's equipped items instead.
-- Midnight Season 2 (12.1.0, started 2026-08-18). Sources: warcraft.wiki.gg
-- "Midnight Season 2" (2026-08-31), method.gg upgrade track guide (2026-08-09).
ns.SEASON_DATA_LATEST = {
    label = "Midnight Season 2",
    championBase = 292,                       -- Champion 1/6
    stepOffsets = { 0, 3, 6, 10, 13, 16 },    -- six steps: +3 +3 +4 +3 +3
    tierGap = 13,
    -- keyLevel -> end-of-dungeon item level (fallback when the API returns nothing)
    rewardByKey = { [2] = 295, [3] = 295, [4] = 298, [5] = 302, [6] = 305, [7] = 305, [8] = 308, [9] = 308, [10] = 311 },
    -- keyLevel -> Great Vault item level; Nebulous Voidcore rolls use this level
    vaultByKey = { [2] = 305, [3] = 305, [4] = 308, [5] = 308, [6] = 311, [7] = 315, [8] = 315, [9] = 315, [10] = 318 },
    maxKeyForRewards = 10,
    -- Raid boss drops: the step within the difficulty's track (Raid Finder
    -- Veteran, Normal Champion, Heroic Hero, Mythic Myth) per group of
    -- bosses, plus item levels that leave the track. A boss is matched by
    -- name, else by its position in the journal. Raids are keyed by name
    -- without a leading "The". Sources: method.gg, warcraft.wiki.gg
    -- "Venomous Abyss", expcarry (2026-09-02); the lair from wowhead.
    raidBosses = {
        ["venomous abyss"] = {
            { step = 1, positions = { 1 }, names = { "nekzali the soulcoiler" } },
            { step = 2, positions = { 2, 3 }, names = { "entombed sentinels", "the lost explorers" } },
            { step = 3, positions = { 4, 5, 6 }, names = { "vashnik the malignant", "sszorak", "the twin fangs" } },
            { step = 4, positions = { 7, 8 }, names = { "the coiled altar", "ulatek" }, ilvl = { mythic = 344 } },
        },
        ["tidebound grotto"] = {
            { step = 1, positions = { 1 }, names = { "nymrissa wavecaller" } },
        },
    },
    -- Tier tokens: not equippable, and the journal names no slot for them,
    -- so the slot each one turns into is shipped. Four armour groups
    -- (Venomwoven cloth, Venomcured leather, Venomcast mail, Venomforged
    -- plate) x five slots, and Ula'tek's Slumbering Coil Curio, traded for
    -- the set piece of any slot. Sources: expcarry tier token list, wowhead
    -- and warcraft.wiki.gg item pages (2026-09-02).
    tierTokens = {
        [270909] = "TIER_ANY",                                                                                                      -- Slumbering Coil Curio, Ula'tek
        [270910] = "INVTYPE_HAND", [270911] = "INVTYPE_HAND", [270912] = "INVTYPE_HAND", [270913] = "INVTYPE_HAND",             -- Idol, Entombed Sentinels
        [270922] = "INVTYPE_SHOULDER", [270923] = "INVTYPE_SHOULDER", [270924] = "INVTYPE_SHOULDER", [270925] = "INVTYPE_SHOULDER", -- Remnant, The Lost Explorers
        [270926] = "INVTYPE_CHEST", [270927] = "INVTYPE_CHEST", [270928] = "INVTYPE_CHEST", [270929] = "INVTYPE_CHEST",         -- Icon, Vashnik
        [270918] = "INVTYPE_LEGS", [270919] = "INVTYPE_LEGS", [270920] = "INVTYPE_LEGS", [270921] = "INVTYPE_LEGS",             -- Relic, Sszorak
        [270914] = "INVTYPE_HEAD", [270915] = "INVTYPE_HEAD", [270916] = "INVTYPE_HEAD", [270917] = "INVTYPE_HEAD",             -- Effigy, The Twin Fangs
    },
    -- Nebulous Voidcache items, one per dungeon (by challenge map id) and
    -- per raid boss (by name): their tooltips list what a bonus roll can
    -- still give the current loot spec. IDs from VoidcoreAdvisor
    -- (github.com/rolferik12/VoidcoreAdvisor, 2026-09-03).
    -- Catalyst charges: Venomblight Manaflux (wowhead currency 3465). A
    -- conversion keeps the item's stats and adds the set bonus.
    catalystCurrency = 3465,
    voidcache = {
        currency = 3418,    -- Nebulous Voidcore
        dungeons = {
            [588] = 279618, -- Altar of Fangs
            [584] = 279619, -- The Blinding Vale
            [586] = 279620, -- Den of Nalorakk
            [249] = 279621, -- Kings' Rest
            [399] = 279622, -- Ruby Life Pools
            [587] = 279623, -- Murder Row
            [250] = 279624, -- Temple of Sethraliss
            [585] = 279625, -- Voidscar Arena
        },
        bosses = {
            ["nekzali the soulcoiler"] = 278285, ["entombed sentinels"] = 278283, ["the lost explorers"] = 278286,
            ["vashnik the malignant"] = 278287, ["sszorak"] = 278288, ["the twin fangs"] = 278289,
            ["the coiled altar"] = 278290, ["ulatek"] = 278284, ["nymrissa wavecaller"] = 274708,
        },
    },
    -- Mythic+ rating for a timed run: base at +2, per level, an extra bonus at
    -- each affix breakpoint, and up to timerBonus for finishing timerWindow
    -- (40%) under the timer. Sources: Mr. Mythical / misti calculators (2026-09).
    -- +2 155, +5 215, +7 260, +10 320, +12 365. Rating.lua checks this against
    -- the game's own scores (/sf status).
    score = {
        base = 155, perLevel = 15, breakpoints = { 5, 7, 10, 12 }, breakpointBonus = 15,
        timerBonus = 15, timerWindow = 0.4, minLevel = 2, maxLevel = 30,
        milestones = { 2000, 2500, 3000 },
    },
}

-------------------------------------------------------------------------------
-- Season id
-------------------------------------------------------------------------------
function ns:GetSeasonID()
    local id = C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason()
    if type(id) ~= "number" or id <= 0 then return nil end
    return id
end

function ns:GetSeasonData()
    local id = self:GetSeasonID()
    return (id and self.SEASON_DATA[id]) or self.SEASON_DATA_LATEST
end

-------------------------------------------------------------------------------
-- Raid boss drop levels shipped with the season
-------------------------------------------------------------------------------
local function RaidKey(name)
    local s = ns:NormalizeName(name)
    return s and (s:gsub("^the ", ""))
end

-- The shipped drop level of `boss` in `raid` at diffKey on `track`, or nil
-- when the season table does not know the raid or the boss.
function ns:ShippedBossLevel(raid, boss, diffKey, track)
    local data = self:GetSeasonData()
    local bands = data and data.raidBosses and raid and raid.name and data.raidBosses[RaidKey(raid.name)]
    if not bands or not boss or not track then return nil end
    local bname = self:NormalizeName(boss.name)
    local band
    for _, b in ipairs(bands) do
        for _, n in ipairs(b.names or {}) do
            if n == bname then band = b end
        end
    end
    if not band and boss.index then
        for _, b in ipairs(bands) do
            for _, i in ipairs(b.positions or {}) do
                if i == boss.index then band = b end
            end
        end
    end
    if not band then return nil end
    local special = band.ilvl and band.ilvl[diffKey]
    if special then return special end
    return band.step and track.ilvls and track.ilvls[band.step] or nil
end

-- The inventory type a shipped tier token turns into, or nil.
function ns:ShippedTokenSlot(itemID)
    local data = self:GetSeasonData()
    return data and data.tierTokens and itemID and data.tierTokens[itemID] or nil
end

-------------------------------------------------------------------------------
-- Track defaults -> active table
-------------------------------------------------------------------------------
function ns:ApplyTrackDefaults()
    local data = self:GetSeasonData()
    if data.stepOffsets then self.TRACK_STEP_OFFSETS = data.stepOffsets end
    if data.tierGap then self.TRACK_TIER_GAP = data.tierGap end
    if data.trackSteps then self.TRACK_STEPS = data.trackSteps end
    local defs
    if self.db and self.db.trackOverride then
        defs = self.db.trackOverride
    elseif data.championBase and data.championBase > 0 then
        defs = self:TrackDefsFromAnchor("Champion", data.championBase)
    elseif self.db and self.db.calibratedChampionBase then
        -- remembered from a previous calibration
        defs = self:TrackDefsFromAnchor("Champion", self.db.calibratedChampionBase)
    else
        defs = {}
    end
    self:SetTrackTable(defs)
end

-- Remember calibration results so the next login starts from good numbers.
ns:On("TRACKS_CHANGED", function()
    if ns.db and ns.tracksCalibrated and ns.trackByKey.Champion then
        ns.db.calibratedChampionBase = ns.trackByKey.Champion.min
    end
end)

-------------------------------------------------------------------------------
-- Reward item level per key level
-------------------------------------------------------------------------------
local rewardCache = {}       -- keyLevel -> end-of-run ilvl, read while the API was usable
local apiRewardsUsable = nil -- nil = not checked yet

local function ReadApiRewards(keyLevel)
    local weekly, eor
    if C_MythicPlus and C_MythicPlus.GetRewardLevelForDifficultyLevel then
        local ok, w, e = pcall(C_MythicPlus.GetRewardLevelForDifficultyLevel, keyLevel)
        if ok then
            if type(w) == "number" and w > 0 then weekly = w end
            if type(e) == "number" and e > 0 then eor = e end
        end
    end
    if not weekly and C_MythicPlus and C_MythicPlus.GetRewardLevelFromKeystoneLevel then
        local ok, w = pcall(C_MythicPlus.GetRewardLevelFromKeystoneLevel, keyLevel)
        if ok and type(w) == "number" and w > 0 then weekly = w end
    end
    return weekly, eor
end

-- The reward APIs answer with base (Mythic 0) numbers until the client has
-- loaded the season's reward table, and with nothing useful in combat. A
-- curve that does not rise between +2 and +10 is not data. Nothing is
-- requested from here: a request answers with the update events, which
-- re-evaluate, which would ask again, a loop that ran every half second.
-- RetrySeasonData asks, a few times after login.
local function ApiRewardsUsable()
    if apiRewardsUsable ~= nil then return apiRewardsUsable end
    local _, low = ReadApiRewards(2)
    local _, high = ReadApiRewards(10)
    local usable = (low and high and high > low) and true or false
    if usable then
        -- fresh data: read every level from it again
        wipe(rewardCache)
        ns.weeklyRewardCache = nil
        apiRewardsUsable = true
    elseif not InCombatLockdown() then
        -- a combat answer is no verdict; check again afterwards
        apiRewardsUsable = false
    end
    return usable
end

function ns:RewardApiUsable()
    return ApiRewardsUsable()
end

function ns:RewardIlvl(keyLevel)
    keyLevel = tonumber(keyLevel) or 0
    if keyLevel < 2 then keyLevel = 2 end
    if ApiRewardsUsable() and not rewardCache[keyLevel] then
        local weekly, eor = ReadApiRewards(keyLevel)
        if eor then
            rewardCache[keyLevel] = eor
            self.weeklyRewardCache = self.weeklyRewardCache or {}
            self.weeklyRewardCache[keyLevel] = weekly
        end
    end
    -- the last good answer stands while the API is flat (combat, reloads)
    if rewardCache[keyLevel] then return rewardCache[keyLevel], "api" end
    local data = self:GetSeasonData()
    local fb = data.rewardByKey and data.rewardByKey[keyLevel]
    if not fb and data.rewardByKey then
        -- above the table: use the highest known level
        local top
        for k, v in pairs(data.rewardByKey) do
            if k <= keyLevel and (not top or k > top) then top = k end
        end
        fb = top and data.rewardByKey[top]
    end
    if fb then return fb, "fallback" end
    return nil, "unknown"
end

-- Great Vault item level for a key; Nebulous Voidcore bonus rolls use it.
function ns:VaultIlvl(keyLevel)
    keyLevel = tonumber(keyLevel) or 0
    if keyLevel < 2 then keyLevel = 2 end
    self:RewardIlvl(keyLevel)
    local weekly = self.weeklyRewardCache and self.weeklyRewardCache[keyLevel]
    if type(weekly) == "number" and weekly > 0 then return weekly, "api" end
    local data = self:GetSeasonData()
    local tbl = data.vaultByKey
    if tbl then
        if tbl[keyLevel] then return tbl[keyLevel], "fallback" end
        local top
        for k in pairs(tbl) do
            if k <= keyLevel and (not top or k > top) then top = k end
        end
        if top then return tbl[top], "fallback" end
    end
    return nil, "unknown"
end

-- Check the API again on the next read. What it said last stays until it
-- has something better; hard = forget that too (the pool changed).
function ns:ClearRewardCache(hard)
    apiRewardsUsable = nil
    if hard then
        wipe(rewardCache)
        self.weeklyRewardCache = nil
    end
end

-- Highest key level that still raises the end-of-run item level (the curve
-- has plateaus such as +2/+3 sharing a value, so look for the last increase).
function ns:MaxUsefulKey()
    local lastIncrease, prev
    for k = 2, 30 do
        local ilvl = self:RewardIlvl(k)
        if not ilvl then break end
        if not prev or ilvl > prev then lastIncrease = k end
        prev = ilvl
    end
    return lastIncrease or (self:GetSeasonData().maxKeyForRewards or 10)
end

-------------------------------------------------------------------------------
-- Dungeon pool
-- ns.dungeons = { { challengeMapID, name, norm, texture, background, instanceMapID }, ... }
-------------------------------------------------------------------------------
ns.dungeons = {}
ns.dungeonByMapID = {}

-- Returns built (a pool is known) and changed (it differs from the one
-- held). An unchanged pool keeps its tables (other modules annotate them)
-- and fires nothing: the update events arrive on every zone change.
function ns:BuildDungeons()
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return false, false end
    local maps = C_ChallengeMode.GetMapTable()
    if not maps or #maps == 0 then return false, false end
    local list = {}
    for _, mapID in ipairs(maps) do
        local name, id, timeLimit, texture, background, instanceMapID = C_ChallengeMode.GetMapUIInfo(mapID)
        if name then
            table.insert(list, {
                challengeMapID = mapID,
                name = name,
                norm = self:NormalizeName(name),
                texture = texture,
                background = background,
                timeLimit = timeLimit,
                instanceMapID = (type(instanceMapID) == "number" and instanceMapID > 0) and instanceMapID
                    or self.FALLBACK_INSTANCE_MAP[mapID],
            })
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    local changed = #list ~= #self.dungeons
    for i, d in ipairs(list) do
        if changed then break end
        if self.dungeons[i].challengeMapID ~= d.challengeMapID then changed = true end
    end
    if changed then
        wipe(self.dungeons); wipe(self.dungeonByMapID)
        for i, d in ipairs(list) do
            self.dungeons[i] = d
            self.dungeonByMapID[d.challengeMapID] = d
        end
        self.dungeonsBuilt = #self.dungeons > 0
        self:ClearRewardCache(true)
        self:Fire("DUNGEONS_UPDATED")
    end
    return self.dungeonsBuilt, changed
end

function ns:RequestSeasonData()
    if C_MythicPlus then
        if C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
        if C_MythicPlus.RequestCurrentAffixes then pcall(C_MythicPlus.RequestCurrentAffixes) end
        if C_MythicPlus.RequestRewards then pcall(C_MythicPlus.RequestRewards) end
    end
end

-- The reward API can stay flat for a while after login: ask again a few
-- times, out of combat, until it rises. The reply comes as the update
-- events below, which re-check it.
function ns:RetrySeasonData(tries)
    tries = tries or 4
    if tries <= 0 then return end
    C_Timer.After(10, function()
        if InCombatLockdown() then return ns:RetrySeasonData(tries) end
        apiRewardsUsable = nil
        if ApiRewardsUsable() then return end
        ns:RequestSeasonData()
        ns:RetrySeasonData(tries - 1)
    end)
end

-------------------------------------------------------------------------------
-- Premade group activity -> dungeon
-------------------------------------------------------------------------------
local activityCache = {}

function ns:DungeonForActivity(activityID)
    if type(activityID) ~= "number" or self.issecret(activityID) then return nil end
    local cached = activityCache[activityID]
    if cached ~= nil then return cached or nil end
    local found = false
    -- 1. the activity's instance map id (12.x exposes it directly)
    if C_LFGList and C_LFGList.GetActivityInfoTable then
        local ok, info = pcall(C_LFGList.GetActivityInfoTable, activityID)
        if ok and type(info) == "table" and not self.issecret(info) then
            local mapID = info.mapID
            if type(mapID) == "number" and not self.issecret(mapID) and mapID > 0 then
                for _, d in ipairs(self.dungeons) do
                    if d.instanceMapID == mapID then found = d; break end
                end
            end
        end
    end
    -- 2. known activity IDs for this season
    for mapID, ids in pairs(self.FALLBACK_ACTIVITY_IDS) do
        for _, id in ipairs(ids) do
            if id == activityID and self.dungeonByMapID[mapID] then
                found = self.dungeonByMapID[mapID]
            end
        end
    end
    -- 3. name matching via activity / activity group names
    if not found and C_LFGList and C_LFGList.GetActivityInfoTable then
        local ok, info = pcall(C_LFGList.GetActivityInfoTable, activityID)
        if ok and type(info) == "table" and not self.issecret(info) then
            local names = {}
            if type(info.fullName) == "string" and not self.issecret(info.fullName) then table.insert(names, info.fullName) end
            if type(info.shortName) == "string" and not self.issecret(info.shortName) then table.insert(names, info.shortName) end
            local groupID = info.groupFinderActivityGroupID
            if type(groupID) == "number" and groupID > 0 and C_LFGList.GetActivityGroupInfo then
                local gok, gname = pcall(C_LFGList.GetActivityGroupInfo, groupID)
                if gok and type(gname) == "string" then table.insert(names, gname) end
            end
            for _, n in ipairs(names) do
                local d = self:DungeonForName(n)
                if d then found = d; break end
            end
        end
    end
    activityCache[activityID] = found
    return found or nil
end

function ns:DungeonForName(name)
    local norm = self:NormalizeName(name)
    if not norm or norm == "" then return nil end
    norm = self.NAME_ALIASES[norm] or norm
    for _, d in ipairs(self.dungeons) do
        if d.norm == norm then return d end
    end
    -- loose: one contains the other
    for _, d in ipairs(self.dungeons) do
        if d.norm and (norm:find(d.norm, 1, true) or d.norm:find(norm, 1, true)) then return d end
    end
    return nil
end

function ns:ClearActivityCache()
    wipe(activityCache)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
ns:On("DB_READY", function()
    ns:ApplyTrackDefaults()
end)

ns:On("LOGIN", function()
    ns:RequestSeasonData()
    ns:RetrySeasonData()
    ns:BuildDungeons()
    for _, ev in ipairs({ "CHALLENGE_MODE_MAPS_UPDATE", "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "WEEKLY_REWARDS_UPDATE", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED" }) do
        ns:RegisterEvent(ev, function()
            local wasUsable = ns:RewardApiUsable()
            ns:ClearRewardCache()
            ns:ClearActivityCache()
            ns:Schedule("dungeons", 0.5, function()
                local built, changed = ns:BuildDungeons()
                if built and changed then
                    ns:ApplyTrackDefaults()
                    ns:Fire("SEASON_READY")
                elseif built and not wasUsable and ns:RewardApiUsable() then
                    -- the reward data arrived: the numbers change
                    ns:Fire("SETTINGS_CHANGED")
                end
            end)
        end)
    end
    -- Some clients never fire the update event when data is already cached.
    C_Timer.After(3, function()
        if not ns.dungeonsBuilt then
            ns:RequestSeasonData()
            C_Timer.After(2, function()
                if ns:BuildDungeons() then ns:Fire("SEASON_READY") end
            end)
        else
            ns:Fire("SEASON_READY")
        end
    end)
end)
