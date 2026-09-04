-- Slot Filler: upgrade track model.
--
-- A "track" (Veteran, Champion, Hero, Myth, ...) is a ladder of item levels.
-- The ladders share one structure per season: a fixed pattern of item level
-- gains per upgrade step (Midnight Season 2: +3 +3 +4 +3 +3 over six steps)
-- and a fixed gap between tracks (13). The whole table can therefore be
-- rebuilt from a single known point, and the player's own items provide that
-- point through their upgrade line "Upgrade Level: Hero 2/6".
--
-- Season defaults (Season.lua) seed the table; calibration against equipped
-- items overrides them whenever they disagree.
local _, ns = ...

local TRACK_ORDER = { "Explorer", "Adventurer", "Veteran", "Champion", "Hero", "Myth" }
local TRACK_RANK = {}
for i, k in ipairs(TRACK_ORDER) do TRACK_RANK[k] = i end
ns.TRACK_RANK = TRACK_RANK

-- Structure parameters; Season.lua sets them per season.
ns.TRACK_STEP_OFFSETS = { 0, 3, 6, 10, 13, 16 } -- item level above step 1, per step
ns.TRACK_TIER_GAP = 13                          -- step 1 of a track vs the track below
ns.TRACK_KEYS = { "Adventurer", "Veteran", "Champion", "Hero", "Myth" }

-------------------------------------------------------------------------------
-- Building the table
-------------------------------------------------------------------------------
local function StepOffset(step)
    local offs = ns.TRACK_STEP_OFFSETS
    if offs[step] then return offs[step] end
    if step < 1 then return 0 end
    -- beyond the table (Myth 7/6 and up): keep climbing at the average pace
    return offs[#offs] + math.floor((step - #offs) * 3.25 + 0.0001)
end

local function MakeTrack(key, min)
    local steps = #ns.TRACK_STEP_OFFSETS
    local ilvls = {}
    for i = 1, steps do ilvls[i] = min + StepOffset(i) end
    return { key = key, rank = TRACK_RANK[key] or 0, steps = steps, min = min, max = ilvls[steps], ilvls = ilvls }
end

-- Every track's step 1 from one anchor: the item level of step 1 of `anchorKey`.
function ns:TrackDefsFromAnchor(anchorKey, anchorMin)
    local defs = {}
    for _, key in ipairs(self.TRACK_KEYS) do
        defs[#defs + 1] = { key = key, min = anchorMin + (TRACK_RANK[key] - TRACK_RANK[anchorKey]) * self.TRACK_TIER_GAP }
    end
    return defs
end

ns.tracks = {}            -- ordered low -> high
ns.trackByKey = {}
ns.trackByLocalName = {}  -- localized name -> track (learned from tooltips)
ns.learnedNames = {}      -- localized name -> key

function ns:SetTrackTable(defs)
    wipe(self.tracks); wipe(self.trackByKey); wipe(self.trackByLocalName)
    for _, def in ipairs(defs or {}) do
        if def.key and def.min and def.min > 0 then
            local t = MakeTrack(def.key, def.min)
            table.insert(self.tracks, t)
            self.trackByKey[t.key] = t
        end
    end
    table.sort(self.tracks, function(a, b) return a.rank < b.rank end)
    for name, key in pairs(self.learnedNames) do
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
    for _, t in ipairs(self.tracks) do defs[#defs + 1] = { key = t.key, min = t.min } end
    return defs
end

function ns:HasTrackData()
    return #self.tracks > 0
end

-- The nearest step of track t for an item level.
function ns:StepForIlvl(t, ilvl)
    local bestStep, bestDiff = 1, math.huge
    for i, v in ipairs(t.ilvls) do
        local d = math.abs(v - ilvl)
        if d < bestDiff then bestDiff, bestStep = d, i end
    end
    return bestStep, bestDiff
end

-- The highest track that contains ilvl, and the step. An item at the Hero
-- base level is Hero 1/6, not Champion 5/6, as the game assigns it.
function ns:TrackForIlvl(ilvl)
    if not ilvl then return nil end
    local best
    for _, t in ipairs(self.tracks) do
        if t.ilvls[1] <= ilvl and ilvl <= t.max then best = t end
    end
    local top = self.tracks[#self.tracks]
    if not best and top and ilvl > top.max then best = top end
    if best then return best, (self:StepForIlvl(best, ilvl)) end
    return nil
end

-------------------------------------------------------------------------------
-- Track names
-------------------------------------------------------------------------------
-- The key an English track name is (the keys are the English names), or nil.
local function EnglishKey(name)
    local lower = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
    for _, key in ipairs(TRACK_ORDER) do
        if key:lower() == lower then return key end
    end
    return nil
end

function ns:TrackKeyForName(name)
    if not name then return nil end
    return EnglishKey(name) or self.learnedNames[name]
end

-- Remembers which track a localized name refers to (never against the English name).
function ns:LearnTrackName(name, key)
    if not name or not key then return end
    local english = EnglishKey(name)
    if english and english ~= key then return end
    if self.learnedNames[name] ~= key then
        self.learnedNames[name] = key
        if self.db then
            self.db.learnedTrackNames = self.db.learnedTrackNames or {}
            self.db.learnedTrackNames[name] = key
        end
    end
    local t = self.trackByKey[key]
    if t then
        t.localizedName = name
        self.trackByLocalName[name] = t
    end
end

function ns:TrackDisplayName(t)
    if not t then return "?" end
    return t.localizedName or t.key
end

-- "Hero 3/6", or just the name without a step.
function ns:TrackText(track, step)
    if not track then return "" end
    if step then return string.format("%s %d/%d", self:TrackDisplayName(track), step, track.steps) end
    return self:TrackDisplayName(track)
end

-- The track an upgrade line (name, cur, max, ilvl) refers to: by name, else
-- the track with that step count whose expected level for the step is closest.
function ns:ResolveTrack(name, cur, max, ilvl)
    local key = self:TrackKeyForName(name)
    if key and self.trackByKey[key] then
        self:LearnTrackName(name, key)
        return self.trackByKey[key]
    end
    local best, bestDiff
    for _, cand in ipairs(self.tracks) do
        if cand.steps == max then
            local expected = cand.min + StepOffset(cur or 1)
            local d = math.abs(expected - (ilvl or expected))
            if not bestDiff or d < bestDiff then best, bestDiff = cand, d end
        end
    end
    if best and bestDiff <= 2 then
        if name then self:LearnTrackName(name, best.key) end
        return best
    end
    return nil
end

-------------------------------------------------------------------------------
-- Calibration from the player's items. samples: { { name, cur, max, ilvl }, ... }
-- Each sample whose track can be named implies the Champion base item level;
-- when the majority disagrees with the current table, it is rebuilt.
-------------------------------------------------------------------------------
function ns:CalibrateTracks(samples)
    local votes, total = {}, 0
    for _, s in ipairs(samples or {}) do
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
    self.trackOffsetApplied = current and (bestBase - current) or nil
    self.tracksCalibrated = true
    self:SetTrackTable(self:TrackDefsFromAnchor("Champion", bestBase))
    self:Debug("Track table rebuilt from", total, "item(s): Champion base", bestBase)
    return true
end

ns:On("DB_READY", function()
    for name, key in pairs(ns.db.learnedTrackNames or {}) do ns.learnedNames[name] = key end
end)
