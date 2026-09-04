-- Slot Filler: secondary stat priority and stat weights.
-- Two modes per spec, chosen in Settings (Manual is the default):
--   manual  - the order the user arranged by clicking the stats. Until they
--             have, the auto order stands in so there is something to start
--             from; the first click saves it.
--   auto    - the weight profile in use for the spec (a Pawn scale string
--             imported and saved under a name; real weights, so drops also
--             get a weighted value that includes the primary stat), or
--             without one the stats stacked most on equipped items.
-- The priority orders drops for the same slot and colours the stats column by
-- how well a drop matches; weights add a value comparison in tooltips.
local _, ns = ...

ns.STATS = {
    { key = "CRIT",    mod = "ITEM_MOD_CRIT_RATING_SHORT",    name = STAT_CRITICAL_STRIKE, short = "Cri" },
    { key = "HASTE",   mod = "ITEM_MOD_HASTE_RATING_SHORT",   name = STAT_HASTE,           short = "Has" },
    { key = "MASTERY", mod = "ITEM_MOD_MASTERY_RATING_SHORT", name = STAT_MASTERY,         short = "Mas" },
    { key = "VERS",    mod = "ITEM_MOD_VERSATILITY",          name = STAT_VERSATILITY,     short = "Ver" },
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
local PAWN_STAT_KEYS = {
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

local function Positive(v)
    v = ns.Num(v)
    return v and v > 0 and v or nil
end

-- Stats on an item link (secondaries plus the extras above); nil until the
-- item is cached or when it has none.
function ns:ItemStats(link)
    if type(link) ~= "string" then return nil end
    local cached = statCache[link]
    if cached ~= nil then return cached or nil end
    local ok, raw = pcall(C_Item.GetItemStats, link)
    if not ok or not self.Tbl(raw) then return nil end
    local stats, any = {}, false
    for _, s in ipairs(self.STATS) do
        local v = Positive(raw[s.mod])
        if v then stats[s.key] = v; any = true end
    end
    for _, e in ipairs(self.EXTRA_STATS) do
        local best
        for _, mod in ipairs(e.mods) do
            local v = Positive(raw[mod])
            if v and (not best or v > best) then best = v end
        end
        if best then stats[e.key] = best; any = true end
    end
    statCache[link] = any and stats or false
    return any and stats or nil
end

function ns:ClearStatCache()
    wipe(statCache)
end

local function HasSecondaries(stats)
    if not stats then return false end
    for _, s in ipairs(ns.STATS) do if stats[s.key] then return true end end
    return false
end

-- Two stat sets with the same secondaries in the same proportions: a
-- Catalyst keeps an item's stats exactly, only the level may differ.
function ns:StatsAlike(a, b)
    if not HasSecondaries(a) or not HasSecondaries(b) then return false end
    local sa, sb = 0, 0
    for _, s in ipairs(self.STATS) do
        local va, vb = a[s.key] or 0, b[s.key] or 0
        if (va > 0) ~= (vb > 0) then return false end
        sa, sb = sa + va, sb + vb
    end
    if sa == 0 or sb == 0 then return false end
    for _, s in ipairs(self.STATS) do
        if math.abs((a[s.key] or 0) / sa - (b[s.key] or 0) / sb) > 0.03 then return false end
    end
    return true
end

-------------------------------------------------------------------------------
-- Pawn scale strings
-- ( Pawn: v1: "Name": Class=Shaman, Spec=Restoration, Intellect=81.97, CritRating=46.19, ... )
-------------------------------------------------------------------------------
function ns:ParsePawnString(text)
    if type(text) ~= "string" then return nil, "empty" end
    local version, name, body = text:match([[Pawn:%s*v(%d+):%s*"([^"]*)"%s*:%s*(.-)%s*%)%s*$]])
    if not body then version, name, body = text:match([[Pawn:%s*v(%d+):%s*"([^"]*)"%s*:%s*(.*)$]]) end
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
            local ours, n = PAWN_STAT_KEYS[lower], tonumber(value)
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

-------------------------------------------------------------------------------
-- Weight profiles. Every imported scale is kept per spec under a name, so a
-- healer can hold a raid set and a Mythic+ set and switch between them:
--   cdb.statProfiles[specID] = { scale, ... }
--       scale = { name, pawnName, class, spec, primary, imported, weights = { CRIT = n, ... },
--                 gear = snapshot the weights were made for, setName = equipment set followed,
--                 amrSetup = Ask Mr. Robot setup label }
--   cdb.statProfile[specID]  = index of the active one; nil = none (rank by gear)
-------------------------------------------------------------------------------
local function ProfileList(self, specID)
    specID = specID or self:GetEvalSpecID()
    if not specID or not self.cdb then return nil end
    local list = self.cdb.statProfiles[specID]
    if not list then list = {}; self.cdb.statProfiles[specID] = list end
    return list, specID
end

local function CleanName(name)
    if type(name) ~= "string" then return "" end
    return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "auto" or manual (nil) for a spec; the caller fires SETTINGS_CHANGED once.
local function SetMode(self, specID, mode)
    self.cdb.statMode[specID] = mode == "auto" and "auto" or nil
end

function ns:GetStatProfiles(specID)
    return ProfileList(self, specID) or {}
end

-- index, scale of the active profile for the evaluated spec, or nil.
function ns:GetActiveStatProfile()
    local list, specID = ProfileList(self)
    if not list then return nil end
    local i = self.cdb.statProfile[specID]
    local scale = i and list[i]
    if type(scale) == "table" and type(scale.weights) == "table" then return i, scale end
    return nil
end

function ns:GetStatWeights()
    local _, scale = self:GetActiveStatProfile()
    return scale
end

function ns:StatProfileName()
    local _, scale = self:GetActiveStatProfile()
    return scale and scale.name or nil
end

-- Switches the evaluated spec to profile `index`; nil = none.
function ns:SetActiveStatProfile(index)
    local list, specID = ProfileList(self)
    if not list or (index ~= nil and not list[index]) then return false end
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

-- The profile new weights replace: the same Pawn scale (by its own name),
-- the same Ask Mr. Robot setup, or the name given. nil for a new one.
local function Replaces(self, list, scale, name)
    local pawn = type(scale.pawnName) == "string" and scale.pawnName:lower() or nil
    local setup = self:AmrSetupFor(scale)
    local lname = name ~= "" and name:lower() or nil
    for i, old in ipairs(list) do
        if pawn and type(old.pawnName) == "string" and old.pawnName:lower() == pawn then return i, old end
        if setup and old.amrSetup == setup.label then return i, old end
        if lname and type(old.name) == "string" and old.name:lower() == lname then return i, old end
    end
    return nil
end

-- Saves a parsed scale as a profile for the evaluated spec, named `name`
-- (default: the Pawn scale's own name), and switches to it. Newer weights
-- for the same scale or setup replace the old profile in place, keeping
-- its name unless one is given. Returns index, scale.
function ns:AddStatProfile(scale, name)
    local list, specID = ProfileList(self)
    if not list or type(scale) ~= "table" or type(scale.weights) ~= "table" then return nil end
    scale.pawnName = scale.pawnName or scale.name
    name = CleanName(name)
    local index, old = Replaces(self, list, scale, name)
    if old then
        -- the old table stays (others may hold it); its contents are the new
        local keep = name ~= "" and name or old.name
        wipe(old)
        for k, v in pairs(scale) do old[k] = v end
        old.name = keep
        scale = old
    else
        if name == "" then name = CleanName(scale.pawnName) end
        if name == "" then name = "Profile " .. (#list + 1) end
        scale.name = name
        list[#list + 1] = scale
        index = #list
    end
    -- the gear the weights were made for, to say when it has changed, and
    -- the equipment set they belong to
    scale.imported = time()
    scale.gear = self:GearSnapshot()
    scale.setName = self:StatProfileSet(scale) or self:EquippedSetName()
    -- an Ask Mr. Robot setup of the same name: its gear is what the weights are for
    self:LinkProfilesToAmr()
    -- pasting weights means "use these": the order follows them from now on
    SetMode(self, specID, "auto")
    self:SetActiveStatProfile(index)
    return index, scale
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

-- Deleting the active profile leaves the spec with none; an active profile
-- after it keeps being active (its index shifts down).
function ns:DeleteStatProfile(index)
    local list, specID = ProfileList(self)
    if not list or not list[index] then return false end
    table.remove(list, index)
    local active = self.cdb.statProfile[specID]
    if active == index then
        self.cdb.statProfile[specID] = nil
    elseif active and active > index then
        self.cdb.statProfile[specID] = active - 1
    end
    self:Fire("SETTINGS_CHANGED")
    return true
end

-- Parses a Pawn string and saves it as the active profile for the evaluated
-- spec. Returns the scale and its index, or nil and a reason.
function ns:ImportPawnString(text, name)
    local scale, err = self:ParsePawnString(text)
    if not scale then return nil, err end
    local index, stored = self:AddStatProfile(scale, name)
    if not index then return nil, "no spec to save it for" end
    return stored, index
end

-- Slots worn differently from the gear a profile was made for:
-- { { slotID, from = snap entry | nil, to = gear entry | nil }, ... }, in
-- slot order. Empty when they match or the profile remembers no gear.
function ns:StatProfileGearDiff(scale)
    local diff = {}
    local snap = scale and scale.gear
    if not snap or not self.gearScanned then return diff end
    for _, s in ipairs(self.SLOTS) do
        local was, now = snap[s.id], self.gear[s.id]
        local wasID = was and was.itemID or nil
        local nowID = now and not now.empty and now.itemID or nil
        if wasID ~= nowID then diff[#diff + 1] = { slotID = s.id, from = was, to = nowID and now or nil } end
    end
    return diff
end

-------------------------------------------------------------------------------
-- Equipment sets: a profile follows the set it was made for
-------------------------------------------------------------------------------
-- Every equipment set's name, and the name of the one worn now (or nil).
local function EquipmentSets()
    local names, worn = {}, nil
    if not C_EquipmentSet then return names, worn end
    local ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
    for _, id in ipairs(ok and type(ids) == "table" and ids or {}) do
        local ok2, name, _, _, isEquipped = pcall(C_EquipmentSet.GetEquipmentSetInfo, id)
        if ok2 and type(name) == "string" then
            names[#names + 1] = name
            if isEquipped == true then worn = name end
        end
    end
    return names, worn
end

function ns:EquippedSetName()
    return (select(2, EquipmentSets()))
end

-- The set a profile follows: the one recorded at import, else the set
-- whose name ends the profile's name or its Pawn scale name (Ask Mr.
-- Robot names scales "<char> - <spec> <setup>" and sets "<setup>").
local function SetFor(scale, names)
    if scale.setName then return scale.setName end
    local best
    for _, candidate in ipairs({ scale.name, scale.pawnName }) do
        local lname = type(candidate) == "string" and candidate:lower() or ""
        for _, n in ipairs(names) do
            local ln = n:lower()
            if #ln > 0 and #lname >= #ln and lname:sub(-#ln) == ln and (not best or #n > #best) then best = n end
        end
    end
    return best
end

function ns:StatProfileSet(scale)
    if not scale then return nil end
    return SetFor(scale, (EquipmentSets()))
end

-- Switches to the profile that follows the worn equipment set, if there
-- is one for this spec. Returns its index, or nil.
function ns:FollowEquipmentSet()
    local names, worn = EquipmentSets()
    if not worn then return nil end
    local active = self:GetActiveStatProfile()
    for i, scale in ipairs(self:GetStatProfiles()) do
        if SetFor(scale, names) == worn then
            if active ~= i then self:SetActiveStatProfile(i) end
            return i
        end
    end
    return nil
end

ns:On("GEAR_UPDATED", function() ns:FollowEquipmentSet() end)

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
-- The four stats by score, ties in the default order.
local function StableOrder(score)
    local index = {}
    for i, key in ipairs(ns.STAT_DEFAULT_ORDER) do index[key] = i end
    local order = { unpack(ns.STAT_DEFAULT_ORDER) }
    table.sort(order, function(a, b)
        local sa, sb = score[a] or 0, score[b] or 0
        if sa ~= sb then return sa > sb end
        return index[a] < index[b]
    end)
    return order
end

-- Ranks the four secondaries by their total on equipped items, or nil when
-- nothing equipped carries secondaries.
function ns:StatPriorityFromGear()
    local totals, any = {}, false
    for _, slot in ipairs(self.SLOTS) do
        local g = self.gear[slot.id]
        local stats = g and not g.empty and self:ItemStats(g.link)
        for _, s in ipairs(stats and self.STATS or {}) do
            if stats[s.key] then totals[s.key] = (totals[s.key] or 0) + stats[s.key]; any = true end
        end
    end
    if not any then return nil end
    return StableOrder(totals)
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
    local mode = self.cdb and specID and self.cdb.statMode[specID]
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
    local manual = self.cdb and specID and self.cdb.statPrio[specID]
    return ValidOrder(manual) and manual or nil
end

-- Effective priority for the evaluated spec: order, source ("manual" |
-- "weights" | "gear"), or nil when there is nothing to go on. In manual mode
-- before any click, the auto order stands in (reported as what it is).
function ns:GetStatPriority()
    if self:GetStatMode() == "manual" then
        local manual = self:GetManualStatPriority()
        if manual then return manual, "manual" end
    end
    local scale = self:GetStatWeights()
    if scale then return StableOrder(scale.weights), "weights" end
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
    self.cdb.statPrio[specID] = order
    if order then SetMode(self, specID, "manual") end
    self:Fire("SETTINGS_CHANGED")
end

-------------------------------------------------------------------------------
-- Fit and value
-------------------------------------------------------------------------------
-- 0..1: where the item's secondary rating sits between the worst stat (0)
-- and the best stat (1), by the scale's weights when given, else by rank in
-- the order. nil without stats or a priority.
function ns:StatFit(stats, prio, scale)
    if not HasSecondaries(stats) then return nil end
    local w = {}
    if scale and scale.weights then
        for _, s in ipairs(self.STATS) do w[s.key] = scale.weights[s.key] or 0 end
    elseif prio then
        for i, key in ipairs(prio) do w[key] = RANK_WEIGHT[i] or 0.25 end
    else
        return nil
    end
    local wmin, wmax
    for _, s in ipairs(self.STATS) do
        local v = w[s.key] or 0
        if not wmin or v < wmin then wmin = v end
        if not wmax or v > wmax then wmax = v end
    end
    local sum, weighted = 0, 0
    for _, s in ipairs(self.STATS) do
        local v = stats[s.key]
        if v then sum, weighted = sum + v, weighted + v * (w[s.key] or 0) end
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
