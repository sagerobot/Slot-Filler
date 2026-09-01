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
local rewardCache = {}
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
-- loaded the season's reward table. A curve that does not rise between +2
-- and +10 means the data is not there yet; use the season fallback meanwhile.
local function ApiRewardsUsable()
    if apiRewardsUsable ~= nil then return apiRewardsUsable end
    local _, low = ReadApiRewards(2)
    local _, high = ReadApiRewards(10)
    if low and high and high > low then
        apiRewardsUsable = true
    else
        apiRewardsUsable = false
        -- ask again; the answer changes once the data arrives
        ns:RequestSeasonData()
        ns.rewardRetries = (ns.rewardRetries or 0) + 1
        if ns.rewardRetries <= 10 then
            C_Timer.After(5, function()
                apiRewardsUsable = nil
                wipe(rewardCache)
                ns.weeklyRewardCache = nil
                ns:Fire("SETTINGS_CHANGED")
            end)
        end
    end
    return apiRewardsUsable
end

function ns:RewardIlvl(keyLevel)
    keyLevel = tonumber(keyLevel) or 0
    if keyLevel < 2 then keyLevel = 2 end
    if rewardCache[keyLevel] then return rewardCache[keyLevel], "api" end
    if ApiRewardsUsable() then
        local weekly, eor = ReadApiRewards(keyLevel)
        if eor then
            rewardCache[keyLevel] = eor
            self.weeklyRewardCache = self.weeklyRewardCache or {}
            self.weeklyRewardCache[keyLevel] = weekly
            return eor, "api"
        end
    end
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

function ns:ClearRewardCache()
    wipe(rewardCache)
    self.weeklyRewardCache = nil
    apiRewardsUsable = nil
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

function ns:BuildDungeons()
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return false end
    local maps = C_ChallengeMode.GetMapTable()
    if not maps or #maps == 0 then return false end
    wipe(self.dungeons); wipe(self.dungeonByMapID)
    for _, mapID in ipairs(maps) do
        local name, id, timeLimit, texture, background, instanceMapID = C_ChallengeMode.GetMapUIInfo(mapID)
        if name then
            local d = {
                challengeMapID = mapID,
                name = name,
                norm = self:NormalizeName(name),
                texture = texture,
                background = background,
                timeLimit = timeLimit,
                instanceMapID = (type(instanceMapID) == "number" and instanceMapID > 0) and instanceMapID
                    or self.FALLBACK_INSTANCE_MAP[mapID],
            }
            table.insert(self.dungeons, d)
            self.dungeonByMapID[mapID] = d
        end
    end
    table.sort(self.dungeons, function(a, b) return a.name < b.name end)
    self.dungeonsBuilt = #self.dungeons > 0
    self:Fire("DUNGEONS_UPDATED")
    return self.dungeonsBuilt
end

function ns:RequestSeasonData()
    if C_MythicPlus then
        if C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
        if C_MythicPlus.RequestCurrentAffixes then pcall(C_MythicPlus.RequestCurrentAffixes) end
        if C_MythicPlus.RequestRewards then pcall(C_MythicPlus.RequestRewards) end
    end
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
    ns:BuildDungeons()
    for _, ev in ipairs({ "CHALLENGE_MODE_MAPS_UPDATE", "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "WEEKLY_REWARDS_UPDATE", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED" }) do
        ns:RegisterEvent(ev, function()
            ns:ClearRewardCache()
            ns:ClearActivityCache()
            ns:Schedule("dungeons", 0.5, function()
                if ns:BuildDungeons() then
                    ns:ApplyTrackDefaults()
                    ns:Fire("SEASON_READY")
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
