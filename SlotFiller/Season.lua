-- Slot Filler: the season's numbers, the dungeon pool, reward item levels.
local _, ns = ...

-------------------------------------------------------------------------------
-- Season data. Everything here is a fallback or a fact the game does not
-- expose: the live client is asked first (C_ChallengeMode / C_MythicPlus),
-- and the track table is calibrated against the player's own items. Update
-- when a new season starts.
--
-- Midnight Season 2 (12.1.0, started 2026-08-18). Sources: warcraft.wiki.gg
-- "Midnight Season 2" (2026-08-31), method.gg upgrade track guide (2026-08-09).
-------------------------------------------------------------------------------
ns.SEASON = {
    label = "Midnight Season 2",
    -- Item level of Champion 1/6; every other track follows from it. 0 =
    -- unknown: the table is then bootstrapped from the player's items.
    championBase = 292,
    stepOffsets = { 0, 3, 6, 10, 13, 16 },    -- six steps: +3 +3 +4 +3 +3
    tierGap = 13,
    -- keyLevel -> end-of-dungeon item level (when the API has nothing)
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

    -- Tier tokens are not equippable and the journal names no slot for them,
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

    -- Catalyst charges: Venomblight Manaflux (wowhead currency 3465). A
    -- conversion keeps the item's stats and adds the set bonus.
    catalystCurrency = 3465,

    -- Nebulous Voidcache items, one per dungeon (by challenge map id) and
    -- per raid boss (by name): their tooltips list what a bonus roll can
    -- still give the current loot spec. IDs from VoidcoreAdvisor
    -- (github.com/rolferik12/VoidcoreAdvisor, 2026-09-03).
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

    -- Fallbacks for when the live mapping fails, by challenge map id.
    -- Source: Raider.IO db_dungeons.lua for season "mn-2" (12.1.0), 2026-09-01.
    instanceMaps = {
        [249] = 1762, -- Kings' Rest
        [250] = 1877, -- Temple of Sethraliss
        [399] = 2521, -- Ruby Life Pools
        [587] = 2813, -- Murder Row
        [584] = 2859, -- The Blinding Vale
        [586] = 2825, -- Den of Nalorakk
        [585] = 2923, -- Voidscar Arena
        [588] = 2993, -- Altar of Fangs
    },
    -- Encounter Journal instance IDs (JournalInstance.ID, build 12.1.0.69497)
    journalInstances = {
        [249] = 1041, -- Kings' Rest
        [250] = 1030, -- Temple of Sethraliss
        [399] = 1202, -- Ruby Life Pools
        [587] = 1304, -- Murder Row
        [584] = 1309, -- The Blinding Vale
        [586] = 1311, -- Den of Nalorakk
        [585] = 1313, -- Voidscar Arena
        [588] = 1322, -- Altar of Fangs (its journal row points at the raid map, so the fallbacks matter)
    },
    -- premade group finder activity IDs (all difficulties)
    activityIDs = {
        [249] = { 512, 513, 514, 515, 660, 661 },
        [250] = { 503, 504, 505, 542, 645 },
        [399] = { 1173, 1174, 1175, 1176 },
        [587] = { 1749, 1750, 1751, 1950 },
        [584] = { 1699, 1700, 1701, 1949 },
        [586] = { 1721, 1722, 1723, 1952 },
        [585] = { 1754, 1755, 1756, 1951 },
        [588] = { 1930, 1931, 1932, 1933 },
    },
}

function ns:GetSeasonID()
    local id = C_MythicPlus.GetCurrentSeason()
    if type(id) ~= "number" or id <= 0 then return nil end
    return id
end

-------------------------------------------------------------------------------
-- Raid boss drop levels and tier tokens shipped with the season
-------------------------------------------------------------------------------
-- The shipped drop level of `boss` in `raid` at diffKey on `track`, or nil
-- when the season table does not know the raid or the boss.
function ns:ShippedBossLevel(raid, boss, diffKey, track)
    local key = raid and self:NormalizeName(raid.name)
    local bands = key and self.SEASON.raidBosses[(key:gsub("^the ", ""))]
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
    return (band.ilvl and band.ilvl[diffKey]) or (band.step and track.ilvls[band.step]) or nil
end

-- The inventory type a shipped tier token turns into, or nil.
function ns:ShippedTokenSlot(itemID)
    return itemID and self.SEASON.tierTokens[itemID] or nil
end

-------------------------------------------------------------------------------
-- Track defaults -> active table
-------------------------------------------------------------------------------
function ns:ApplyTrackDefaults()
    local data = self.SEASON
    self.TRACK_STEP_OFFSETS = data.stepOffsets
    self.TRACK_TIER_GAP = data.tierGap
    local defs
    if self.db.trackOverride then
        defs = self.db.trackOverride
    elseif data.championBase > 0 then
        defs = self:TrackDefsFromAnchor("Champion", data.championBase)
    elseif self.db.calibratedChampionBase then
        defs = self:TrackDefsFromAnchor("Champion", self.db.calibratedChampionBase) -- a previous calibration
    else
        defs = {}
    end
    self:SetTrackTable(defs)
end

-- Calibration results are remembered so the next login starts from good numbers.
ns:On("TRACKS_CHANGED", function()
    if ns.db and ns.tracksCalibrated and ns.trackByKey.Champion then
        ns.db.calibratedChampionBase = ns.trackByKey.Champion.min
    end
end)

-------------------------------------------------------------------------------
-- Reward item level per key level
-------------------------------------------------------------------------------
local rewardCache = {}       -- keyLevel -> { eor, weekly }, read while the API was usable
local apiRewardsUsable = nil -- nil = not checked yet

local function ReadApiRewards(keyLevel)
    local ok, weekly, eor = pcall(C_MythicPlus.GetRewardLevelForDifficultyLevel, keyLevel)
    if not ok then return nil, nil end
    if type(weekly) ~= "number" or weekly <= 0 then weekly = nil end
    if type(eor) ~= "number" or eor <= 0 then eor = nil end
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
        wipe(rewardCache) -- fresh data: read every level from it again
        apiRewardsUsable = true
    elseif not InCombatLockdown() then
        apiRewardsUsable = false -- a combat answer is no verdict; check again afterwards
    end
    return usable
end

function ns:RewardApiUsable()
    return ApiRewardsUsable()
end

-- The table's value for a key, or the highest key below it.
local function TableIlvl(tbl, keyLevel)
    if tbl[keyLevel] then return tbl[keyLevel] end
    local top
    for k in pairs(tbl) do
        if k <= keyLevel and (not top or k > top) then top = k end
    end
    return top and tbl[top]
end

local function Rewards(self, keyLevel)
    keyLevel = math.max(2, tonumber(keyLevel) or 0)
    if ApiRewardsUsable() and not rewardCache[keyLevel] then
        local weekly, eor = ReadApiRewards(keyLevel)
        if eor then rewardCache[keyLevel] = { eor = eor, weekly = weekly } end
    end
    -- the last good answer stands while the API is flat (combat, reloads)
    return rewardCache[keyLevel], keyLevel
end

-- End-of-dungeon item level for a key: ilvl, "api" | "fallback" | "unknown".
function ns:RewardIlvl(keyLevel)
    local cached, key = Rewards(self, keyLevel)
    if cached then return cached.eor, "api" end
    local fb = TableIlvl(self.SEASON.rewardByKey, key)
    if fb then return fb, "fallback" end
    return nil, "unknown"
end

-- Great Vault item level for a key; Nebulous Voidcore bonus rolls use it.
function ns:VaultIlvl(keyLevel)
    local cached, key = Rewards(self, keyLevel)
    if cached and cached.weekly then return cached.weekly, "api" end
    local fb = TableIlvl(self.SEASON.vaultByKey, key)
    if fb then return fb, "fallback" end
    return nil, "unknown"
end

-- Checks the API again on the next read. What it said last stays until it
-- has something better; hard = forget that too (the pool changed).
function ns:ClearRewardCache(hard)
    apiRewardsUsable = nil
    if hard then wipe(rewardCache) end
end

-- The highest key level that still raises the end-of-run item level (the
-- curve has plateaus such as +2/+3 sharing a value, so look for the last increase).
function ns:MaxUsefulKey()
    local lastIncrease, prev
    for k = 2, 30 do
        local ilvl = self:RewardIlvl(k)
        if not ilvl then break end
        if not prev or ilvl > prev then lastIncrease = k end
        prev = ilvl
    end
    return lastIncrease or self.SEASON.maxKeyForRewards
end

-------------------------------------------------------------------------------
-- Dungeon pool
-- ns.dungeons = { { challengeMapID, name, norm, texture, background, timeLimit, instanceMapID }, ... }
-------------------------------------------------------------------------------
ns.dungeons = {}
ns.dungeonByMapID = {}

-- Returns built (a pool is known) and changed (it differs from the one
-- held). An unchanged pool keeps its tables (other modules annotate them)
-- and fires nothing: the update events arrive on every zone change.
function ns:BuildDungeons()
    local maps = C_ChallengeMode.GetMapTable()
    if not maps or #maps == 0 then return false, false end
    local list = {}
    for _, mapID in ipairs(maps) do
        local name, _, timeLimit, texture, background, instanceMapID = C_ChallengeMode.GetMapUIInfo(mapID)
        if name then
            list[#list + 1] = {
                challengeMapID = mapID, name = name, norm = self:NormalizeName(name),
                texture = texture, background = background, timeLimit = timeLimit,
                instanceMapID = (type(instanceMapID) == "number" and instanceMapID > 0) and instanceMapID or self.SEASON.instanceMaps[mapID],
            }
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
    pcall(C_MythicPlus.RequestMapInfo)
    pcall(C_MythicPlus.RequestCurrentAffixes)
    pcall(C_MythicPlus.RequestRewards)
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

function ns:DungeonForName(name)
    local norm = self:NormalizeName(name)
    if not norm or norm == "" then return nil end
    for _, d in ipairs(self.dungeons) do
        if d.norm == norm then return d end
    end
    -- loose: one contains the other
    for _, d in ipairs(self.dungeons) do
        if d.norm and (norm:find(d.norm, 1, true) or d.norm:find(norm, 1, true)) then return d end
    end
    return nil
end

function ns:DungeonForActivity(activityID)
    if not self.Num(activityID) then return nil end
    local cached = activityCache[activityID]
    if cached ~= nil then return cached or nil end
    local found
    local ok, info = pcall(C_LFGList.GetActivityInfoTable, activityID)
    info = ok and self.Tbl(info)
    -- the activity's instance map id
    local mapID = info and self.Num(info.mapID)
    if mapID and mapID > 0 then
        for _, d in ipairs(self.dungeons) do
            if d.instanceMapID == mapID then found = d; break end
        end
    end
    -- known activity ids for this season
    if not found then
        for cmID, ids in pairs(self.SEASON.activityIDs) do
            for _, id in ipairs(ids) do
                if id == activityID and self.dungeonByMapID[cmID] then found = self.dungeonByMapID[cmID] end
            end
        end
    end
    -- name matching via the activity's and its group's names
    if not found and info then
        local names = {}
        for _, field in ipairs({ "fullName", "shortName" }) do
            if type(info[field]) == "string" and not self.issecret(info[field]) then names[#names + 1] = info[field] end
        end
        local groupID = self.Num(info.groupFinderActivityGroupID)
        if groupID and groupID > 0 then
            local gok, gname = pcall(C_LFGList.GetActivityGroupInfo, groupID)
            if gok and type(gname) == "string" then names[#names + 1] = gname end
        end
        for _, n in ipairs(names) do
            found = self:DungeonForName(n)
            if found then break end
        end
    end
    activityCache[activityID] = found or false
    return found
end

function ns:ClearActivityCache()
    wipe(activityCache)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
ns:On("DB_READY", function() ns:ApplyTrackDefaults() end)

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
                    ns:Fire("SETTINGS_CHANGED") -- the reward data arrived: the numbers change
                end
            end)
        end)
    end
    -- some clients never fire the update event when data is already cached
    C_Timer.After(3, function()
        if ns.dungeonsBuilt then
            ns:Fire("SEASON_READY")
        else
            ns:RequestSeasonData()
            C_Timer.After(2, function()
                if ns:BuildDungeons() then ns:Fire("SEASON_READY") end
            end)
        end
    end)
end)
