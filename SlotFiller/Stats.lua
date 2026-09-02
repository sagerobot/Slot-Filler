-- Slot Filler: secondary stat priority and stat weights.
-- Three sources, best first:
--   manual  - an order the user set per spec in the options
--   weights - a Pawn scale string imported per spec (real weights, so drops
--             also get a weighted value that includes the primary stat)
--   gear    - the stat you stacked most on equipped items ranks first
-- The priority orders drops for the same slot and colours the stats column by
-- how well a drop matches; weights add a value comparison in tooltips.
local _, ns = ...

ns.STATS = {
    { key = "CRIT",    mod = "ITEM_MOD_CRIT_RATING_SHORT",    name = STAT_CRITICAL_STRIKE or "Critical Strike", short = "Cri" },
    { key = "HASTE",   mod = "ITEM_MOD_HASTE_RATING_SHORT",   name = STAT_HASTE or "Haste",                     short = "Has" },
    { key = "MASTERY", mod = "ITEM_MOD_MASTERY_RATING_SHORT", name = STAT_MASTERY or "Mastery",                 short = "Mas" },
    { key = "VERS",    mod = "ITEM_MOD_VERSATILITY",          name = STAT_VERSATILITY or "Versatility",         short = "Ver" },
}
ns.STAT_BY_KEY = {}
ns.STAT_DEFAULT_ORDER = {}
for i, s in ipairs(ns.STATS) do
    ns.STAT_BY_KEY[s.key] = s
    ns.STAT_DEFAULT_ORDER[i] = s.key
end

-- Other stats a Pawn scale can weight. An item carries one primary stat for
-- you; the highest of the three is taken.
ns.EXTRA_STATS = {
    { key = "PRIMARY", mods = { "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STRENGTH_SHORT" } },
    { key = "STAMINA", mods = { "ITEM_MOD_STAMINA_SHORT" } },
    { key = "LEECH",   mods = { "ITEM_MOD_CR_LIFESTEAL_SHORT" } },
    { key = "AVOID",   mods = { "ITEM_MOD_CR_AVOIDANCE_SHORT" } },
    { key = "SPEED",   mods = { "ITEM_MOD_CR_SPEED_SHORT" } },
}

-- Pawn stat names (lower-cased) -> our keys.
ns.PAWN_STAT_KEYS = {
    critrating = "CRIT", hasterating = "HASTE", masteryrating = "MASTERY", versatility = "VERS",
    intellect = "PRIMARY", agility = "PRIMARY", strength = "PRIMARY", stamina = "STAMINA",
    leech = "LEECH", avoidance = "AVOID", movementspeed = "SPEED",
}

-- Weight of a secondary by its rank when only an order is known.
local RANK_WEIGHT = { 1, 0.75, 0.5, 0.25 }

local statCache = {}  -- link -> { key = amount } | false (nothing usable)
local valueCache = {} -- link -> weighted value under the current scale

local function Num(v)
    if type(v) == "number" and not ns.issecret(v) and v > 0 then return v end
    return nil
end

-- Stats on an item link (secondaries plus the extras above); nil until the
-- item is cached or when it has none.
function ns:ItemStats(link)
    if type(link) ~= "string" then return nil end
    local cached = statCache[link]
    if cached ~= nil then return cached or nil end
    local api = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not api then return nil end
    local ok, raw = pcall(api, link)
    if not ok or type(raw) ~= "table" or self.issecret(raw) then return nil end
    local stats, any = {}, false
    for _, s in ipairs(self.STATS) do
        local v = Num(raw[s.mod])
        if v then stats[s.key] = v; any = true end
    end
    for _, e in ipairs(self.EXTRA_STATS) do
        local best
        for _, mod in ipairs(e.mods) do
            local v = Num(raw[mod])
            if v and (not best or v > best) then best = v end
        end
        if best then stats[e.key] = best; any = true end
    end
    statCache[link] = any and stats or false
    return any and stats or nil
end

local function HasSecondaries(stats)
    if not stats then return false end
    for _, s in ipairs(ns.STATS) do if stats[s.key] then return true end end
    return false
end

-------------------------------------------------------------------------------
-- Pawn scale strings
-- ( Pawn: v1: "Name": Class=Shaman, Spec=Restoration, Intellect=81.97, CritRating=46.19, ... )
-------------------------------------------------------------------------------
function ns:ParsePawnString(text)
    if type(text) ~= "string" then return nil, "empty" end
    local version, name, body = text:match('Pawn:%s*v(%d+):%s*"([^"]*)"%s*:%s*(.-)%s*%)%s*$')
    if not body then
        version, name, body = text:match('Pawn:%s*v(%d+):%s*"([^"]*)"%s*:%s*(.*)$')
    end
    if not body then return nil, "not a Pawn string" end
    local scale = { name = name, version = tonumber(version), weights = {} }
    local any = false
    for key, value in body:gmatch("([%a_]+)%s*=%s*([^,%)]+)") do
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
        local lower = key:lower()
        if lower == "class" then
            scale.class = value
        elseif lower == "spec" then
            scale.spec = value
        else
            local ours = self.PAWN_STAT_KEYS[lower]
            local n = tonumber(value)
            if ours and n then
                if not scale.weights[ours] or n > scale.weights[ours] then scale.weights[ours] = n end
                any = true
            end
        end
    end
    if not any then return nil, "no stat weights found" end
    return scale
end

-- Imported scale for the evaluated spec, or nil.
function ns:GetStatWeights()
    local specID = self:GetEvalSpecID()
    local scale = self.db and self.db.statWeights and specID and self.db.statWeights[specID]
    if type(scale) == "table" and type(scale.weights) == "table" then return scale end
    return nil
end

-- scale table from ParsePawnString, or nil to clear, for the evaluated spec.
function ns:SetStatWeights(scale)
    local specID = self:GetEvalSpecID()
    if not specID or not self.db then return end
    self.db.statWeights = self.db.statWeights or {}
    self.db.statWeights[specID] = scale
    wipe(valueCache)
    self:Fire("SETTINGS_CHANGED")
end

-- Parses and stores a Pawn string for the evaluated spec. Returns the scale,
-- or nil and a reason.
function ns:ImportPawnString(text)
    local scale, err = self:ParsePawnString(text)
    if not scale then return nil, err end
    self:SetStatWeights(scale)
    return scale
end

-------------------------------------------------------------------------------
-- Priority order
-------------------------------------------------------------------------------
local function StableOrder(self, score)
    local index = {}
    for i, key in ipairs(self.STAT_DEFAULT_ORDER) do index[key] = i end
    local order = { unpack(self.STAT_DEFAULT_ORDER) }
    table.sort(order, function(a, b)
        local sa, sb = score[a] or 0, score[b] or 0
        if sa ~= sb then return sa > sb end
        return index[a] < index[b]
    end)
    return order
end

-- Ranks the four secondaries by their total on equipped items. Returns the
-- order and the totals, or nil when nothing equipped carries secondaries.
function ns:StatPriorityFromGear()
    local totals, any = {}, false
    for _, s in ipairs(self.STATS) do totals[s.key] = 0 end
    for _, slot in ipairs(self.SLOTS) do
        local g = self.gear and self.gear[slot.id]
        local stats = g and not g.empty and self:ItemStats(g.link)
        if stats then
            for _, s in ipairs(self.STATS) do
                local v = stats[s.key]
                if v then totals[s.key] = totals[s.key] + v; any = true end
            end
        end
    end
    if not any then return nil end
    return StableOrder(self, totals), totals
end

local function ValidOrder(t)
    if type(t) ~= "table" or #t ~= #ns.STATS then return false end
    local seen = {}
    for _, key in ipairs(t) do
        if not ns.STAT_BY_KEY[key] or seen[key] then return false end
        seen[key] = true
    end
    return true
end

-- Effective priority for the evaluated spec. Returns order, source
-- ("manual" | "weights" | "gear") or nil when there is nothing to go on.
function ns:GetStatPriority()
    local specID = self:GetEvalSpecID()
    local manual = self.db and self.db.statPrio and specID and self.db.statPrio[specID]
    if ValidOrder(manual) then return manual, "manual" end
    local scale = self:GetStatWeights()
    if scale then return StableOrder(self, scale.weights), "weights" end
    local order = self:StatPriorityFromGear()
    if order then return order, "gear" end
    return nil, nil
end

-- order = list of the four stat keys, or nil to fall back to weights / gear.
function ns:SetStatPriority(order)
    local specID = self:GetEvalSpecID()
    if not specID or not self.db then return end
    if order ~= nil and not ValidOrder(order) then return end
    self.db.statPrio = self.db.statPrio or {}
    self.db.statPrio[specID] = order
    self:Fire("SETTINGS_CHANGED")
end

-------------------------------------------------------------------------------
-- Fit and value
-------------------------------------------------------------------------------
-- Per-secondary weights: from the scale when given, else by rank in the order.
function ns:SecondaryWeights(prio, scale)
    local w = {}
    if scale and scale.weights then
        for _, s in ipairs(self.STATS) do w[s.key] = scale.weights[s.key] or 0 end
    elseif prio then
        for i, key in ipairs(prio) do w[key] = RANK_WEIGHT[i] or 0.25 end
    else
        return nil
    end
    return w
end

-- 0..1: where the item's secondary rating sits between the worst stat (0)
-- and the best stat (1). nil without stats or a priority.
function ns:StatFit(stats, prio, scale)
    if not HasSecondaries(stats) then return nil end
    local w = self:SecondaryWeights(prio, scale)
    if not w then return nil end
    local wmin, wmax
    for _, s in ipairs(self.STATS) do
        local v = w[s.key] or 0
        if not wmin or v < wmin then wmin = v end
        if not wmax or v > wmax then wmax = v end
    end
    local sum, weighted = 0, 0
    for _, s in ipairs(self.STATS) do
        local v = stats[s.key]
        if v then
            sum = sum + v
            weighted = weighted + v * (w[s.key] or 0)
        end
    end
    if sum == 0 then return nil end
    if wmax <= wmin then return 0.5 end
    return (weighted / sum - wmin) / (wmax - wmin)
end

-- Weighted value of an item link under a scale (every stat it maps), or nil.
function ns:ItemValue(link, scale)
    if not scale or not scale.weights or type(link) ~= "string" then return nil end
    local cached = valueCache[link]
    if cached ~= nil then return cached or nil end
    local stats = self:ItemStats(link)
    if not stats then return nil end
    local total = 0
    for key, v in pairs(stats) do total = total + v * (scale.weights[key] or 0) end
    valueCache[link] = total
    return total
end

function ns:FitHex(fit)
    if not fit then return "|cff888888" end
    if fit >= 0.6 then return "|cff33dd33" end
    if fit >= 0.3 then return "|cffffcc33" end
    return "|cffaaaaaa"
end

-- The item's secondaries, largest first, coloured by fit. long = full names.
function ns:StatText(stats, fit, long)
    if not HasSecondaries(stats) then return "" end
    local keys = {}
    for _, s in ipairs(self.STATS) do if stats[s.key] then keys[#keys + 1] = s.key end end
    table.sort(keys, function(a, b)
        if stats[a] ~= stats[b] then return stats[a] > stats[b] end
        return a < b
    end)
    local parts = {}
    for _, k in ipairs(keys) do
        local s = self.STAT_BY_KEY[k]
        parts[#parts + 1] = long and s.name or s.short
    end
    return self:FitHex(fit) .. table.concat(parts, long and ", " or "/") .. "|r"
end

-- "Has > Mas > Cri > Ver"
function ns:StatPriorityText(order, long)
    if not order then return "" end
    local parts = {}
    for _, k in ipairs(order) do
        local s = self.STAT_BY_KEY[k]
        parts[#parts + 1] = s and (long and s.name or s.short) or k
    end
    return table.concat(parts, " > ")
end

-- Short description of where the priority comes from.
function ns:StatSourceText(source, scale)
    if source == "manual" then return "manual" end
    if source == "weights" then return "Pawn: " .. tostring(scale and scale.name or "?") end
    if source == "gear" then return "from gear" end
    return "not set"
end
