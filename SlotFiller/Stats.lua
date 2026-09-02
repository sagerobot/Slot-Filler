-- Slot Filler: secondary stat priority and stat weights.
-- Two modes per spec, chosen in Settings (Manual is the default):
--   manual  - the order the user arranged by clicking the stats. Until they
--             have, the chips show the auto order so there is something to
--             start from; the first click saves it.
--   auto    - weights: the active weight profile for the spec, a Pawn scale
--             string imported and saved under a name (real weights, so drops
--             also get a weighted value that includes the primary stat). A
--             spec can hold several profiles, e.g. Raid and Mythic+.
--             gear: without a profile, the stat you stacked most on equipped
--             items ranks first.
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
    { key = "PRIMARY", name = "Primary",   mods = { "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STRENGTH_SHORT" } },
    { key = "STAMINA", name = "Stamina",   mods = { "ITEM_MOD_STAMINA_SHORT" } },
    { key = "LEECH",   name = "Leech",     mods = { "ITEM_MOD_CR_LIFESTEAL_SHORT" } },
    { key = "AVOID",   name = "Avoidance", mods = { "ITEM_MOD_CR_AVOIDANCE_SHORT" } },
    { key = "SPEED",   name = "Speed",     mods = { "ITEM_MOD_CR_SPEED_SHORT" } },
}
ns.EXTRA_STAT_BY_KEY = {}
for _, e in ipairs(ns.EXTRA_STATS) do ns.EXTRA_STAT_BY_KEY[e.key] = e end

-- Pawn stat names (lower-cased) -> our keys.
ns.PAWN_STAT_KEYS = {
    critrating = "CRIT", hasterating = "HASTE", masteryrating = "MASTERY", versatility = "VERS",
    intellect = "PRIMARY", agility = "PRIMARY", strength = "PRIMARY", stamina = "STAMINA",
    leech = "LEECH", avoidance = "AVOID", movementspeed = "SPEED",
}

-- Weight of a secondary by its rank when only an order is known.
local RANK_WEIGHT = { 1, 0.75, 0.5, 0.25 }

local statCache = {}  -- link -> { key = amount } | false (nothing usable)
-- scale -> { link -> value | false }. Keyed by the scale table itself, so
-- switching profiles or specs never serves a value from another scale.
local valueCache = setmetatable({}, { __mode = "k" })

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
local PAWN_CLOSED = [[Pawn:%s*v(%d+):%s*"([^"]*)"%s*:%s*(.-)%s*%)%s*$]]
local PAWN_OPEN   = [[Pawn:%s*v(%d+):%s*"([^"]*)"%s*:%s*(.*)$]]

function ns:ParsePawnString(text)
    if type(text) ~= "string" then return nil, "empty" end
    local version, name, body = text:match(PAWN_CLOSED)
    if not body then
        version, name, body = text:match(PAWN_OPEN)
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
                if not scale.weights[ours] or n > scale.weights[ours] then
                    scale.weights[ours] = n
                    if ours == "PRIMARY" then scale.primary = key end -- "Intellect"
                end
                any = true
            end
        end
    end
    if not any then return nil, "no stat weights found" end
    return scale
end

-- "auto" or manual (nil) for a spec; the caller fires SETTINGS_CHANGED once.
local function SetMode(self, specID, mode)
    self.cdb.statMode = self.cdb.statMode or {}
    self.cdb.statMode[specID] = mode == "auto" and "auto" or nil
end

-------------------------------------------------------------------------------
-- Weight profiles. Every imported scale is kept per spec under a name, so a
-- healer can hold a raid set and a Mythic+ set and switch between them:
--   db.statProfiles[specID] = { scale, ... }
--       scale = { name, pawnName, class, spec, primary, imported, weights = { CRIT = n, ... } }
--   db.statProfile[specID]  = index of the active one; nil = none (rank by gear)
-------------------------------------------------------------------------------
local function ProfileList(self, specID)
    specID = specID or self:GetEvalSpecID()
    if not specID or not self.cdb then return nil end
    self.cdb.statProfiles = self.cdb.statProfiles or {}
    local list = self.cdb.statProfiles[specID]
    if not list then list = {}; self.cdb.statProfiles[specID] = list end
    return list, specID
end

local function CleanName(name)
    if type(name) ~= "string" then return "" end
    return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Saved profiles for the evaluated spec (or specID); may be empty.
function ns:GetStatProfiles(specID)
    return ProfileList(self, specID) or {}
end

-- index, scale of the active profile for the evaluated spec, or nil.
function ns:GetActiveStatProfile()
    local list, specID = ProfileList(self)
    if not list then return nil end
    local i = self.cdb.statProfile and self.cdb.statProfile[specID]
    local scale = i and list[i]
    if type(scale) == "table" and type(scale.weights) == "table" then return i, scale end
    return nil
end

-- Active scale for the evaluated spec, or nil.
function ns:GetStatWeights()
    local _, scale = self:GetActiveStatProfile()
    return scale
end

-- "Raid", or nil when no profile is active.
function ns:StatProfileName()
    local _, scale = self:GetActiveStatProfile()
    return scale and scale.name or nil
end

-- Switches the evaluated spec to profile `index`; nil = none.
function ns:SetActiveStatProfile(index)
    local list, specID = ProfileList(self)
    if not list then return false end
    if index ~= nil and not list[index] then return false end
    self.cdb.statProfile = self.cdb.statProfile or {}
    self.cdb.statProfile[specID] = index
    self:Fire("SETTINGS_CHANGED")
    return true
end

-- Profile by 1-based index or by name (case-insensitive): index, scale or nil.
function ns:FindStatProfile(what)
    local list = self:GetStatProfiles()
    local n = tonumber(what)
    if n and list[n] then return n, list[n] end
    local lower = CleanName(what):lower()
    if lower ~= "" then
        for i, scale in ipairs(list) do
            if tostring(scale.name):lower() == lower then return i, scale end
        end
    end
    return nil
end

-- Saves a parsed scale as a new profile for the evaluated spec, named `name`
-- (default: the Pawn scale's own name), and switches to it. Returns index, scale.
function ns:AddStatProfile(scale, name)
    local list, specID = ProfileList(self)
    if not list or type(scale) ~= "table" or type(scale.weights) ~= "table" then return nil end
    scale.pawnName = scale.pawnName or scale.name
    name = CleanName(name)
    if name == "" then name = CleanName(scale.pawnName) end
    if name == "" then name = "Profile " .. (#list + 1) end
    scale.name = name
    scale.imported = scale.imported or time()
    list[#list + 1] = scale
    -- Pasting weights means "use these": the order follows them from now on.
    SetMode(self, specID, "auto")
    self:SetActiveStatProfile(#list)
    return #list, scale
end

function ns:RenameStatProfile(index, name)
    local list = ProfileList(self)
    local scale = list and list[index]
    name = CleanName(name)
    if not scale or name == "" then return false end
    scale.name = name
    self:Fire("SETTINGS_CHANGED")
    return true
end

-- Removes a profile. Deleting the active one leaves the spec with none; an
-- active profile after it keeps being active (its index shifts down).
function ns:DeleteStatProfile(index)
    local list, specID = ProfileList(self)
    if not list or not list[index] then return false end
    table.remove(list, index)
    local active = self.cdb.statProfile and self.cdb.statProfile[specID]
    if active then
        if active == index then
            active = nil
        elseif active > index then
            active = active - 1
        end
        self.cdb.statProfile[specID] = active
    end
    self:Fire("SETTINGS_CHANGED")
    return true
end

-- nil = use no profile for the evaluated spec (the saved profiles stay);
-- a scale table is saved as a new profile and switched to.
function ns:SetStatWeights(scale)
    if scale == nil then
        self:SetActiveStatProfile(nil)
    else
        self:AddStatProfile(scale)
    end
end

-- Parses a Pawn string and saves it as a new, active profile for the
-- evaluated spec. Returns the scale and its index, or nil and a reason.
function ns:ImportPawnString(text, name)
    local scale, err = self:ParsePawnString(text)
    if not scale then return nil, err end
    local index = self:AddStatProfile(scale, name)
    if not index then return nil, "no spec to save it for" end
    return scale, index
end

-- Chat listing for /sf pawn.
function ns:PrintStatProfiles()
    local specName = (self:SpecName(self:GetEvalSpecID())) or "this spec"
    local list = self:GetStatProfiles()
    local active = self:GetActiveStatProfile()
    if #list == 0 then
        self:Print("No weight profiles saved for " .. specName .. ". Paste a Pawn string after /sf pawn to add one.")
        return
    end
    self:Print(string.format("Weight profiles for %s (%s, %s stat order):", specName,
        active and ("using " .. tostring(list[active].name)) or "none in use", self:GetStatMode()))
    for i, scale in ipairs(list) do
        print(string.format("  %s%d. %s|r  %s", i == active and "|cffffffff" or "|cffaaaaaa", i, tostring(scale.name), self:StatWeightsText(scale, true)))
    end
    print("  /sf pawn use <name|n>, rename <n> <new name>, delete <name|n>, clear")
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

-- "manual" (default) or "auto" for the evaluated spec.
function ns:GetStatMode()
    local specID = self:GetEvalSpecID()
    local mode = self.cdb and self.cdb.statMode and specID and self.cdb.statMode[specID]
    return mode == "auto" and "auto" or "manual"
end

-- Switching modes keeps the saved manual order, so Auto -> Manual restores it.
function ns:SetStatMode(mode)
    local specID = self:GetEvalSpecID()
    if not specID or not self.cdb then return end
    SetMode(self, specID, mode)
    self:Fire("SETTINGS_CHANGED")
end

-- The saved manual order for the evaluated spec, or nil.
function ns:GetManualStatPriority()
    local specID = self:GetEvalSpecID()
    local manual = self.cdb and self.cdb.statPrio and specID and self.cdb.statPrio[specID]
    return ValidOrder(manual) and manual or nil
end

-- Effective priority for the evaluated spec. Returns order, source
-- ("manual" | "weights" | "gear") or nil when there is nothing to go on. In
-- manual mode before any click, the auto order stands in (and is reported as
-- what it is) so the first click has something to start from.
function ns:GetStatPriority()
    if self:GetStatMode() == "manual" then
        local manual = self:GetManualStatPriority()
        if manual then return manual, "manual" end
    end
    local scale = self:GetStatWeights()
    if scale then return StableOrder(self, scale.weights), "weights" end
    local order = self:StatPriorityFromGear()
    if order then return order, "gear" end
    return nil, nil
end

-- order = list of the four stat keys; saving one puts the spec in manual
-- mode. nil forgets the manual order (the mode stays).
function ns:SetStatPriority(order)
    local specID = self:GetEvalSpecID()
    if not specID or not self.cdb then return end
    if order ~= nil and not ValidOrder(order) then return end
    self.cdb.statPrio = self.cdb.statPrio or {}
    self.cdb.statPrio[specID] = order
    if order then SetMode(self, specID, "manual") end
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
    local perScale = valueCache[scale]
    if not perScale then perScale = {}; valueCache[scale] = perScale end
    local cached = perScale[link]
    if cached ~= nil then return cached or nil end
    local stats = self:ItemStats(link)
    if not stats then return nil end
    local total = 0
    for key, v in pairs(stats) do total = total + v * (scale.weights[key] or 0) end
    perScale[link] = total
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

-- A scale's weights, largest first: "Intellect 82, Critical Strike 46, ..."
-- (short = "Int 82, Cri 46, ..."). The primary stat is named as the Pawn
-- string named it.
function ns:StatWeightsText(scale, short)
    if not scale or type(scale.weights) ~= "table" then return "" end
    local keys = {}
    for k, v in pairs(scale.weights) do
        if type(v) == "number" and v >= 0.05 then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b)
        if scale.weights[a] ~= scale.weights[b] then return scale.weights[a] > scale.weights[b] end
        return a < b
    end)
    local parts = {}
    for _, k in ipairs(keys) do
        local label
        local s = self.STAT_BY_KEY[k]
        if s then
            label = short and s.short or s.name
        elseif k == "PRIMARY" and scale.primary then
            label = short and scale.primary:sub(1, 3) or scale.primary
        else
            local e = self.EXTRA_STAT_BY_KEY[k]
            label = e and (short and e.name:sub(1, 3) or e.name) or k
        end
        local v = scale.weights[k]
        parts[#parts + 1] = string.format(v >= 10 and "%s %.0f" or "%s %.1f", label, v)
    end
    return table.concat(parts, ", ")
end

-- Short description of where the priority comes from.
function ns:StatSourceText(source, scale)
    if source == "manual" then return "manual" end
    if source == "weights" then return "profile: " .. tostring(scale and scale.name or "?") end
    if source == "gear" then return "from gear" end
    return "not set"
end
