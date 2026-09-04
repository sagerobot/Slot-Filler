-- Slot Filler: Mythic+ rating per dungeon, the timed-score model, and run
-- plans towards a target rating (the IO tab).
--
-- Reads only: the client's season-best data per dungeon and the overall
-- score. Nothing here requests anything from the server; RequestRatingData
-- is called when the IO tab opens and a few seconds after a completed key.
local _, ns = ...

local Num, Tbl = ns.Num, ns.Tbl

-------------------------------------------------------------------------------
-- Score model
-------------------------------------------------------------------------------
-- Rating for a timed run at `level`. With a time limit and duration the timer
-- bonus is added (linear up to timerWindow under the limit); a duration past
-- the limit returns nil (the game reports depleted scores, we do not model them).
function ns:TimedScore(level, timeLimit, durationSec)
    local s = self.SEASON.score
    level = tonumber(level) or 0
    if level < s.minLevel then return 0 end
    local score = s.base + s.perLevel * (level - s.minLevel)
    for _, b in ipairs(s.breakpoints) do
        if b <= level then score = score + s.breakpointBonus end
    end
    if timeLimit and durationSec and timeLimit > 0 then
        if durationSec > timeLimit then return nil end
        score = score + s.timerBonus * math.min(1, (timeLimit - durationSec) / (s.timerWindow * timeLimit))
    end
    return score
end

function ns:RatingMilestones()
    return self.SEASON.score.milestones
end

function ns:RatingLevelRange()
    return self.SEASON.score.minLevel, self.SEASON.score.maxLevel
end

-- The lowest level whose timed score beats `score`; nil when none does.
local function FloorLevel(score)
    local minL, maxL = ns:RatingLevelRange()
    for level = minL, maxL do
        if ns:TimedScore(level) > score then return level end
    end
    return nil
end

function ns:FormatDuration(sec)
    sec = math.floor((tonumber(sec) or 0) + 0.5)
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-------------------------------------------------------------------------------
-- Reading the client's data
-------------------------------------------------------------------------------
ns.rating = nil        -- { ready, overall, byMap, signature, timedMax }
ns.ratingDirty = true

local planCache = {}

local function ZeroEntry()
    return { score = 0, hasRun = false, floor = (ns:RatingLevelRange()) }
end

local function ReadSummary()
    local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player")
    summary = ok and Tbl(summary)
    if not summary then return nil end
    local byMap = {}
    for _, run in ipairs(Tbl(summary.runs) or {}) do
        run = Tbl(run)
        local mapID = run and Num(run.challengeModeID)
        if mapID then byMap[mapID] = run end
    end
    return { overall = Num(summary.currentSeasonScore), byMap = byMap }
end

local function RunEntry(info)
    info = Tbl(info)
    local score = info and Num(info.dungeonScore)
    if not score then return nil end
    return { score = score, level = Num(info.level) or 0, durationSec = Num(info.durationSec) }
end

-- Self-check: the formula against the game's own score for timed runs.
local function CheckFormula(byMap)
    local result = { checked = 0, off = 0 }
    for mapID, e in pairs(byMap) do
        local d = ns.dungeonByMapID[mapID]
        local run = e.intime
        if run and run.durationSec and d and d.timeLimit and d.timeLimit > 0 then
            local expected = ns:TimedScore(run.level, d.timeLimit, run.durationSec)
            if expected then
                result.checked = result.checked + 1
                local diff = math.abs(expected - run.score)
                if diff > 1 then
                    result.off = result.off + 1
                    if not result.worst or diff > result.worst.diff then
                        result.worst = { name = d.name, level = run.level, expected = expected, actual = run.score, diff = diff }
                    end
                    ns:Debug(string.format("Rating formula off for %s +%d: expected %.1f, game says %.1f", d.name, run.level, expected, run.score))
                end
            end
        end
    end
    ns.ratingCheck = result
end

function ns:ReadRatings()
    if self.rating and not self.ratingDirty then return self.rating end
    local byMap, parts, summary, timedMax = {}, {}, nil, nil
    local ok, v = pcall(C_ChallengeMode.GetOverallDungeonScore)
    local overall = ok and Num(v) or nil
    for _, d in ipairs(self.dungeons) do
        local mapID = d.challengeMapID
        local ok2, intime, overtime = pcall(C_MythicPlus.GetSeasonBestForMap, mapID)
        local ti, to = ok2 and RunEntry(intime), ok2 and RunEntry(overtime)
        if not ti and not to then
            summary = summary or ReadSummary() or false
            local run = summary and summary.byMap[mapID]
            local score = run and Num(run.mapScore)
            if score and score > 0 then
                local e = { score = score, level = Num(run.bestRunLevel) or 0,
                    durationSec = Num(run.bestRunDurationMS) and Num(run.bestRunDurationMS) / 1000 }
                if run.finishedSuccess then ti = e else to = e end
            end
        end
        local e = ZeroEntry()
        e.intime, e.overtime = ti, to
        if ti or to then
            local best = (to and (not ti or to.score > ti.score)) and to or ti
            e.hasRun, e.score, e.level, e.timed, e.durationSec = true, best.score, best.level, best == ti, best.durationSec
            e.floor = FloorLevel(best.score)
            if e.timed and (not timedMax or best.level > timedMax) then timedMax = best.level end
        end
        byMap[mapID] = e
        parts[#parts + 1] = string.format("%d:%s:%s:%s", mapID, tostring(e.score), tostring(e.level), e.timed and "t" or "o")
    end
    if not overall then
        summary = summary or ReadSummary() or false
        overall = summary and summary.overall
    end
    if not overall then
        local any, sum = false, 0
        for _, e in pairs(byMap) do
            if e.hasRun then any = true; sum = sum + e.score end
        end
        if any then overall = sum end
    end
    parts[#parts + 1] = tostring(overall)
    local signature = table.concat(parts, ";")
    local changed = not self.rating or self.rating.signature ~= signature
    self.rating = { ready = (self.dungeonsBuilt and overall ~= nil) and true or false, overall = overall, byMap = byMap, signature = signature, timedMax = timedMax }
    self.ratingDirty = nil
    if changed then
        wipe(planCache)
        CheckFormula(byMap)
    end
    return self.rating, changed
end

function ns:DungeonRating(mapID)
    return self:ReadRatings().byMap[mapID] or ZeroEntry()
end

function ns:OverallRating()
    local r = self:ReadRatings()
    return r.ready and r.overall or nil
end

function ns:RatingsReady()
    return self:ReadRatings().ready
end

-- Rating gained by timing `mapID` at `level` (0 when it would not beat the best).
function ns:RatingGain(mapID, level)
    return math.max(0, self:TimedScore(level) - self:DungeonRating(mapID).score)
end

-------------------------------------------------------------------------------
-- Target, key cap, avoided dungeons
-------------------------------------------------------------------------------
local TARGET_MIN, TARGET_MAX, TARGET_STEP = 50, 5000, 50

-- Returns target, isAuto, tabID ("2000" | "2500" | "3000" | "custom").
function ns:RatingTarget()
    local target = self.cdb and self.cdb.ioTarget
    local auto = not target
    if auto then
        local overall = self:OverallRating() or 0
        for _, m in ipairs(self:RatingMilestones()) do
            if m > overall then target = m; break end
        end
        if not target then target = math.floor(overall / 100) * 100 + 100 end
    end
    local tabID = "custom"
    for _, m in ipairs(self:RatingMilestones()) do
        if m == target then tabID = tostring(m) end
    end
    return target, auto, tabID
end

function ns:SetRatingTarget(n)
    if n ~= nil then
        n = tonumber(n)
        if not n then return end
        n = math.floor(n / TARGET_STEP + 0.5) * TARGET_STEP
        n = math.max(TARGET_MIN, math.min(TARGET_MAX, n))
    end
    self.cdb.ioTarget = n
    self:Fire("RATING_UPDATED")
end

function ns:StepRatingTarget(delta)
    self:SetRatingTarget(self:RatingTarget() + delta * TARGET_STEP)
end

-- Returns cap, isAuto. Auto = the highest timed key + 2 (10 when nothing is timed).
function ns:RatingMaxKey()
    local minL, maxL = self:RatingLevelRange()
    local cap = self.cdb and self.cdb.ioMaxKey
    if cap then return math.max(minL, math.min(maxL, cap)), false end
    local r = self:ReadRatings()
    cap = r.timedMax and (r.timedMax + 2) or 10
    return math.max(minL, math.min(maxL, cap)), true
end

function ns:SetRatingMaxKey(n)
    if n ~= nil then
        n = tonumber(n)
        if not n then return end
        local minL, maxL = self:RatingLevelRange()
        n = math.max(minL, math.min(maxL, math.floor(n)))
    end
    self.cdb.ioMaxKey = n
    self:Fire("RATING_UPDATED")
end

function ns:StepRatingMaxKey(delta)
    self:SetRatingMaxKey(self:RatingMaxKey() + delta)
end

function ns:IsDungeonAvoided(mapID)
    return self.cdb and self.cdb.ioAvoid[mapID] and true or false
end

function ns:ToggleAvoidDungeon(mapID)
    if not mapID then return end
    self.cdb.ioAvoid[mapID] = not self.cdb.ioAvoid[mapID] or nil
    self:Fire("RATING_UPDATED")
end

function ns:SetRatingRuns(count)
    self.db.ioRuns = count
    self:Fire("RATING_UPDATED")
end

-- Order of the planned runs: "rating" (highest key first) or "gear" (most
-- usable drops at the planned key first). Picking one returns the list to
-- plan order.
function ns:RatingOrder()
    return self.db.ioOrder == "gear" and "gear" or "rating"
end

function ns:SetRatingOrder(order)
    self.db.ioOrder = order == "gear" and "gear" or "rating"
    self.db.ioSort = "plan"
    self:Fire("RATING_UPDATED")
end

-------------------------------------------------------------------------------
-- Planner
-------------------------------------------------------------------------------
-- Raises the dungeons in S (each { d, cur, floor }) one level at a time, the
-- lowest projected level first, until the gains cover `need`. Returns nil
-- when the cap stops it short (unless `toCap`, which then returns the plan
-- with everything at the cap).
local function WaterFill(S, need, cap, toCap)
    local lvl, total = {}, 0
    while total < need do
        local best
        for i, c in ipairs(S) do
            local nextLevel = lvl[i] and (lvl[i] + 1) or c.floor
            if nextLevel and nextLevel <= cap then
                local from = lvl[i] and ns:TimedScore(lvl[i]) or c.cur
                local step = ns:TimedScore(nextLevel) - from
                if not best or nextLevel < best.level or (nextLevel == best.level and step > best.step) then
                    best = { i = i, level = nextLevel, step = step }
                end
            end
        end
        if not best then
            if toCap then break end
            return nil
        end
        total = total + best.step
        lvl[best.i] = best.level
    end
    local runs, byMap, maxLevel = {}, {}, 0
    for i, c in ipairs(S) do
        if lvl[i] then
            local score = ns:TimedScore(lvl[i])
            local run = { dungeon = c.d, mapID = c.d.challengeMapID, level = lvl[i], score = score, gain = score - c.cur }
            runs[#runs + 1] = run
            byMap[run.mapID] = run
            if lvl[i] > maxLevel then maxLevel = lvl[i] end
        end
    end
    table.sort(runs, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.dungeon.name < b.dungeon.name
    end)
    return { runs = runs, byMap = byMap, count = #runs, maxLevel = maxLevel, total = total }
end

local function AvoidSignature()
    local ids = {}
    for mapID, on in pairs(ns.cdb and ns.cdb.ioAvoid or {}) do
        if on then ids[#ids + 1] = mapID end
    end
    table.sort(ids)
    return table.concat(ids, ",")
end

-- Returns plans (fastest first, easiest last) and info
-- { ready, overall, target, need, reached, cap, capAuto, partial }.
function ns:RatingPlans()
    local r = self:ReadRatings()
    local target = self:RatingTarget()
    local cap, capAuto = self:RatingMaxKey()
    local info = { ready = r.ready, overall = r.overall, target = target, cap = cap, capAuto = capAuto }
    if not r.ready then return {}, info end
    info.need = target - r.overall
    if info.need <= 0 then
        info.reached = true
        return {}, info
    end
    local key = table.concat({ r.signature, tostring(target), tostring(cap), AvoidSignature() }, "|")
    local cached = planCache[key]
    if cached then return cached.plans, cached.info end

    local cands = {}
    for _, d in ipairs(self.dungeons) do
        local e = r.byMap[d.challengeMapID]
        if e and e.floor and not self:IsDungeonAvoided(d.challengeMapID) then
            cands[#cands + 1] = { d = d, cur = e.score, floor = e.floor }
        end
    end
    table.sort(cands, function(a, b)
        if a.cur ~= b.cur then return a.cur < b.cur end
        if a.floor ~= b.floor then return a.floor < b.floor end
        return a.d.name < b.d.name
    end)

    local byCount, counts = {}, {}
    for k = 1, #cands do
        local S = {}
        for i = 1, k do S[i] = cands[i] end
        local plan = WaterFill(S, info.need, cap)
        if plan then
            if not byCount[plan.count] then counts[#counts + 1] = plan.count end
            byCount[plan.count] = plan
        end
    end
    table.sort(counts)
    local plans = {}
    for i, c in ipairs(counts) do plans[i] = byCount[c] end
    if #plans == 0 and #cands > 0 then
        local all = WaterFill(cands, math.huge, cap, true)
        if all and all.count > 0 then
            all.partial = true
            all.reach = r.overall + all.total
            plans[1] = all
            info.partial = true
        end
    end
    for i, p in ipairs(plans) do
        p.index, p.of = i, #plans
        p.fastest = (i == 1 and #plans > 1)
        p.easiest = (i == #plans and #plans > 1)
    end
    planCache[key] = { plans = plans, info = info }
    return plans, info
end

-- The plan the Runs strip has selected: db.ioRuns is a run count; nil or an
-- unknown count falls back to the next larger count, then the easiest plan.
function ns:SelectedRatingPlan()
    local plans, info = self:RatingPlans()
    if #plans == 0 then return nil, info end
    local want = self.db.ioRuns
    if want then
        for _, p in ipairs(plans) do
            if p.count == want then return p, info end
        end
        for _, p in ipairs(plans) do
            if p.count > want then return p, info end
        end
    end
    return plans[#plans], info
end

function ns:PlannedRun(mapID)
    local plan = self:SelectedRatingPlan()
    return plan and plan.byMap[mapID] or nil
end

-------------------------------------------------------------------------------
-- Requests and events
-------------------------------------------------------------------------------
function ns:RequestRatingData()
    pcall(C_MythicPlus.RequestMapInfo)
end

local function RefreshRatings()
    ns.ratingDirty = true
    local _, changed = ns:ReadRatings()
    if changed then ns:Fire("RATING_UPDATED") end
end

local function RequestAfterRun()
    if InCombatLockdown() then
        ns.ratingRequestPending = true
        return
    end
    ns.ratingRequestPending = nil
    ns:RequestRatingData()
end

ns:On("LOGIN", function()
    for _, ev in ipairs({ "CHALLENGE_MODE_MAPS_UPDATE", "MYTHIC_PLUS_NEW_SEASON_RECORD" }) do
        ns:RegisterEvent(ev, function()
            ns.ratingDirty = true
            ns:Schedule("rating", 0.5, RefreshRatings)
        end)
    end
    ns:RegisterEvent("CHALLENGE_MODE_COMPLETED", function()
        ns.ratingDirty = true
        ns:Schedule("ratingRequest", 3, RequestAfterRun)
    end)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if ns.ratingRequestPending then RequestAfterRun() end
    end)
end)

ns:On("DUNGEONS_UPDATED", function()
    ns.ratingDirty = true
    wipe(planCache)
end)
