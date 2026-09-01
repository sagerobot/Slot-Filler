-- Slot Filler: upgrade track model.
--
-- A "track" (Veteran, Champion, Hero, Myth, ...) is a ladder of item levels.
-- The ladders share one structure per season: a fixed pattern of item level
-- gains per upgrade step (Midnight Season 2: +3 +3 +4 +3 +3 over six steps)
-- and a fixed gap between tracks (13). The whole table can therefore be
-- rebuilt from a single known point, and the player's own items provide that
-- point through their tooltip line "Upgrade Level: Hero 2/6".
--
-- Season defaults (Season.lua) seed the table; calibration against equipped
-- items overrides them whenever they disagree.
local _, ns = ...

local TRACK_ORDER = { "Explorer", "Adventurer", "Veteran", "Champion", "Hero", "Myth" }
ns.TRACK_ORDER = TRACK_ORDER

local TRACK_RANK = {}
for i, k in ipairs(TRACK_ORDER) do TRACK_RANK[k] = i end
ns.TRACK_RANK = TRACK_RANK

-- Structure parameters; Season.lua may override them per season.
ns.TRACK_STEP_OFFSETS = { 0, 3, 6, 10, 13, 16 } -- item level above step 1, per step
ns.TRACK_TIER_GAP = 13                          -- step 1 of a track vs the track below
ns.TRACK_STEPS = nil                            -- optional per-track step counts { Champion = 8, ... }
ns.TRACK_KEYS = { "Adventurer", "Veteran", "Champion", "Hero", "Myth" }

-------------------------------------------------------------------------------
-- Build helpers
-------------------------------------------------------------------------------
local function StepOffset(step)
    local offs = ns.TRACK_STEP_OFFSETS
    if offs[step] then return offs[step] end
    -- beyond the table (Myth 7/6 and up): keep climbing at the average pace
    local last = #offs
    if step < 1 then return 0 end
    return offs[last] + math.floor((step - last) * 3.25 + 0.0001)
end
ns.StepOffset = StepOffset

local function BuildLadder(minIlvl, steps)
    local t = {}
    for i = 1, steps do
        t[i] = minIlvl + StepOffset(i)
    end
    return t
end
ns.BuildLadder = BuildLadder

local function StepsFor(key, def)
    if def and def.steps then return def.steps end
    if ns.TRACK_STEPS and ns.TRACK_STEPS[key] then return ns.TRACK_STEPS[key] end
    return #ns.TRACK_STEP_OFFSETS
end

-- def: { key=, min=, steps=? } -> track object
local function MakeTrack(def)
    local steps = StepsFor(def.key, def)
    local ilvls = BuildLadder(def.min, steps)
    return {
        key = def.key,
        rank = TRACK_RANK[def.key] or 0,
        steps = steps,
        min = def.min,
        max = ilvls[steps],
        ilvls = ilvls,
    }
end

-- Full table from one anchor: the item level of step 1 of `anchorKey`.
function ns:TrackDefsFromAnchor(anchorKey, anchorMin)
    local anchorRank = TRACK_RANK[anchorKey]
    local defs = {}
    for _, key in ipairs(self.TRACK_KEYS) do
        local rank = TRACK_RANK[key]
        table.insert(defs, {
            key = key,
            min = anchorMin + (rank - anchorRank) * self.TRACK_TIER_GAP,
        })
    end
    return defs
end

-------------------------------------------------------------------------------
-- Active track table
-------------------------------------------------------------------------------
ns.tracks = {}            -- ordered low -> high
ns.trackByKey = {}
ns.trackByLocalName = {}  -- localized name -> track (learned from tooltips)

function ns:SetTrackTable(defs)
    wipe(self.tracks); wipe(self.trackByKey); wipe(self.trackByLocalName)
    for _, def in ipairs(defs or {}) do
        if def.key and def.min and def.min > 0 then
            local t = MakeTrack(def)
            table.insert(self.tracks, t)
            self.trackByKey[t.key] = t
        end
    end
    table.sort(self.tracks, function(a, b) return a.rank < b.rank end)
    for name, key in pairs(self.learnedNames or {}) do
        local t = self.trackByKey[key]
        if t then
            t.localizedName = name
            self.trackByLocalName[name] = t
        end
    end
    self:Fire("TRACKS_CHANGED")
end

function ns:GetTrackDefs()
    local defs = {}
    for _, t in ipairs(self.tracks) do
        table.insert(defs, { key = t.key, min = t.min, steps = t.steps })
    end
    return defs
end

function ns:HasTrackData()
    return #self.tracks > 0
end

-- Highest track whose first step is <= ilvl and that still contains ilvl.
-- This mirrors how Blizzard assigns tracks: an item at the Hero base item
-- level is Hero 1/6, not Champion 5/6.
function ns:TrackForIlvl(ilvl)
    if not ilvl then return nil end
    local best
    for _, t in ipairs(self.tracks) do
        if t.ilvls[1] <= ilvl and ilvl <= t.max then
            best = t
        end
    end
    if not best then
        local top = self.tracks[#self.tracks]
        if top and ilvl > top.max then best = top end
    end
    if best then
        return best, (self:StepForIlvl(best, ilvl))
    end
    return nil
end

-- Nearest step index of track t for a given ilvl.
function ns:StepForIlvl(t, ilvl)
    local bestStep, bestDiff = 1, math.huge
    for i, v in ipairs(t.ilvls) do
        local d = math.abs(v - ilvl)
        if d < bestDiff then bestDiff, bestStep = d, i end
    end
    return bestStep, bestDiff
end

-------------------------------------------------------------------------------
-- Track names
-------------------------------------------------------------------------------
-- Which track key does a tooltip track name refer to? Learned names first,
-- then the English names (which are the keys themselves).
local function EnglishKey(localizedName)
    local lower = localizedName:lower():gsub("^%s+", ""):gsub("%s+$", "")
    for _, key in ipairs(TRACK_ORDER) do
        if key:lower() == lower then return key end
    end
    return nil
end

function ns:TrackKeyForName(localizedName)
    if not localizedName then return nil end
    -- English names are the keys themselves and always win
    local english = EnglishKey(localizedName)
    if english then return english end
    local t = self.trackByLocalName[localizedName]
    if t then return t.key end
    local learned = self.learnedNames and self.learnedNames[localizedName]
    if learned then return learned end
    return nil
end

function ns:LearnTrackName(localizedName, key)
    if not localizedName or not key then return end
    -- never learn a mapping that contradicts the English name
    local english = EnglishKey(localizedName)
    if english and english ~= key then return end
    self.learnedNames = self.learnedNames or {}
    if self.learnedNames[localizedName] ~= key then
        self.learnedNames[localizedName] = key
        if self.db then
            self.db.learnedTrackNames = self.db.learnedTrackNames or {}
            self.db.learnedTrackNames[localizedName] = key
        end
    end
    local t = self.trackByKey[key]
    if t then
        t.localizedName = localizedName
        self.trackByLocalName[localizedName] = t
    end
end

function ns:TrackDisplayName(t)
    if not t then return "?" end
    return t.localizedName or t.key
end

-- Resolve a tooltip sample (localizedName, cur, max, ilvl) to a track object.
function ns:ResolveTrack(localizedName, cur, max, ilvl)
    local key = self:TrackKeyForName(localizedName)
    if key and self.trackByKey[key] then
        self:LearnTrackName(localizedName, key)
        return self.trackByKey[key]
    end
    -- structural match: same step count, closest expected ilvl for that step
    local best, bestDiff
    for _, cand in ipairs(self.tracks) do
        if cand.steps == max then
            local expected = cand.min + StepOffset(cur or 1)
            local d = math.abs(expected - (ilvl or expected))
            if not bestDiff or d < bestDiff then best, bestDiff = cand, d end
        end
    end
    if best and bestDiff <= 2 then
        if localizedName then self:LearnTrackName(localizedName, best.key) end
        return best
    end
    return nil
end

-------------------------------------------------------------------------------
-- Calibration from the player's items
-- samples: list of { name=localizedName, cur=, max=, ilvl= }
-- Each sample whose track we can name implies the Champion base item level.
-- If the majority disagrees with the current table, rebuild the table.
-------------------------------------------------------------------------------
function ns:CalibrateTracks(samples)
    if not samples or #samples == 0 then return false end
    local votes, total = {}, 0
    for _, s in ipairs(samples) do
        local key = self:TrackKeyForName(s.name)
        if not key and self:HasTrackData() then
            local t = self:ResolveTrack(nil, s.cur, s.max, s.ilvl)
            key = t and t.key
        end
        if key and TRACK_RANK[key] and s.cur and s.ilvl and s.ilvl > 0 then
            local base = s.ilvl - StepOffset(s.cur) -- step 1 of that track
            local champion = base - (TRACK_RANK[key] - TRACK_RANK.Champion) * self.TRACK_TIER_GAP
            votes[champion] = (votes[champion] or 0) + 1
            total = total + 1
            if s.name then self:LearnTrackName(s.name, key) end
        end
    end
    if total == 0 then return false end
    local bestBase, bestCount = nil, 0
    for base, count in pairs(votes) do
        if count > bestCount then bestBase, bestCount = base, count end
    end
    if not bestBase or bestCount * 2 <= total then return false end
    local current = self.trackByKey.Champion and self.trackByKey.Champion.min
    if current == bestBase then return false end
    local defs = self:TrackDefsFromAnchor("Champion", bestBase)
    self.trackOffsetApplied = current and (bestBase - current) or nil
    self.tracksCalibrated = true
    self:SetTrackTable(defs)
    self:Debug("Track table rebuilt from", total, "item(s): Champion base", bestBase)
    return true
end

-------------------------------------------------------------------------------
-- Initialise learned names from saved variables
-------------------------------------------------------------------------------
ns:On("DB_READY", function()
    ns.learnedNames = ns.learnedNames or {}
    -- Early builds learned names before they had real numbers; drop that data.
    if (ns.db.learnedVersion or 0) < 2 then
        ns.db.learnedTrackNames = {}
        ns.db.learnedVersion = 2
    end
    for name, key in pairs(ns.db.learnedTrackNames or {}) do
        local english = EnglishKey(name)
        if not english or english == key then
            ns.learnedNames[name] = key
        else
            ns.db.learnedTrackNames[name] = nil
        end
    end
end)
