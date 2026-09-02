-- Slot Filler: scan the player's equipped gear and read upgrade tracks from tooltips.
local _, ns = ...

-- "Upgrade Level: %s %d/%d" (track name + step) on TWW/Midnight clients.
local UPGRADE_PATTERN
do
    local fmt = ITEM_UPGRADE_TOOLTIP_FORMAT_STRING or "Upgrade Level: %s %d/%d"
    -- escape magic characters, then substitute the format tokens
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
    fmt = fmt:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
    UPGRADE_PATTERN = "^%s*" .. fmt .. "%s*$"
end
ns.UPGRADE_PATTERN = UPGRADE_PATTERN

-- Fallback pattern without a track name ("Upgrade Level: 3/8", older clients).
local UPGRADE_PATTERN_NONAME
do
    local fmt = ITEM_UPGRADE_TOOLTIP_FORMAT or "Upgrade Level: %d/%d"
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
    fmt = fmt:gsub("%%%%d", "(%%d+)")
    UPGRADE_PATTERN_NONAME = "^%s*" .. fmt .. "%s*$"
end

local function StripColor(s)
    if not s then return s end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return s
end

-- Extract (trackName, cur, max) from tooltip data.
local function ParseUpgradeFromTooltip(data)
    if not data or not data.lines or #data.lines == 0 then return nil end
    if TooltipUtil and TooltipUtil.SurfaceArgs and data.lines[1].leftText == nil and data.lines[1].args then
        TooltipUtil.SurfaceArgs(data)
        for _, line in ipairs(data.lines) do TooltipUtil.SurfaceArgs(line) end
    end
    for i = 1, math.min(#data.lines, 12) do
        local line = data.lines[i]
        local text = line.leftText
        if text and not ns.issecret(text) then
            text = StripColor(text)
            local name, cur, max = text:match(UPGRADE_PATTERN)
            if cur then
                name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
                return name, tonumber(cur), tonumber(max)
            end
            cur, max = text:match(UPGRADE_PATTERN_NONAME)
            if cur then
                return nil, tonumber(cur), tonumber(max)
            end
        end
    end
    return nil
end
ns.ParseUpgradeFromTooltip = ParseUpgradeFromTooltip

local function ItemLevelOf(link)
    if not link then return nil end
    local ilvl = C_Item.GetDetailedItemLevelInfo(link)
    if not ilvl or ilvl == 0 then
        ilvl = select(4, C_Item.GetItemInfo(link))
    end
    return ilvl
end
ns.ItemLevelOf = ItemLevelOf

-- 11.1.5+: the client can tell us the upgrade track directly, including the
-- fully upgraded item level. Returns trackName, cur, max, maxItemLevel or nil.
local function UpgradeInfoOf(link)
    if not link or not (C_Item and C_Item.GetItemUpgradeInfo) then return nil end
    local ok, info = pcall(C_Item.GetItemUpgradeInfo, link)
    if not ok or type(info) ~= "table" then return nil end
    local cur, max = tonumber(info.currentLevel), tonumber(info.maxLevel)
    if not cur or not max or max <= 0 then return nil end
    local track = info.trackString
    if type(track) ~= "string" or track == "" then track = nil end
    local maxIlvl = tonumber(info.maxItemLevel)
    if maxIlvl and maxIlvl <= 0 then maxIlvl = nil end
    return track, cur, max, maxIlvl
end
ns.UpgradeInfoOf = UpgradeInfoOf

-------------------------------------------------------------------------------
-- Equipped gear
-- ns.gear[slotID] = { slotID, link, itemID, ilvl, trackName, cur, max, track, potential, equipLoc }
-------------------------------------------------------------------------------
ns.gear = {}

local function ScanSlot(slotID)
    local link = GetInventoryItemLink("player", slotID)
    local entry = { slotID = slotID }
    if not link then
        entry.empty = true
        entry.ilvl = 0
        entry.potential = 0
        return entry
    end
    entry.link = link
    entry.itemID = C_Item.GetItemInfoInstant(link)
    entry.ilvl = ItemLevelOf(link) or 0
    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
    entry.equipLoc = equipLoc
    entry.classID = classID
    entry.subClassID = subClassID

    -- Upgrade track: direct API first, tooltip line as fallback.
    local name, cur, max, maxIlvl = UpgradeInfoOf(link)
    if not cur then
        local data = C_TooltipInfo and C_TooltipInfo.GetInventoryItem and C_TooltipInfo.GetInventoryItem("player", slotID)
        name, cur, max = ParseUpgradeFromTooltip(data)
    end
    entry.trackName, entry.cur, entry.max = name, cur, max
    if cur and max then
        local track = ns:ResolveTrack(name, cur, max, entry.ilvl)
        entry.track = track
        if maxIlvl and maxIlvl >= entry.ilvl then
            -- the client told us the fully upgraded item level: trust it
            entry.potential = maxIlvl
        elseif track then
            local stepIlvl = track.ilvls[cur] or entry.ilvl
            local delta = entry.ilvl - stepIlvl -- usually 0; keeps odd items sane
            entry.potential = math.max(track.max + delta, entry.ilvl)
        else
            entry.potential = entry.ilvl
        end
    else
        entry.potential = entry.ilvl
    end
    return entry
end

function ns:ScanGear()
    local samples = {}
    for _, slot in ipairs(self.SLOTS) do
        local e = ScanSlot(slot.id)
        self.gear[slot.id] = e
        if e.cur and e.max and e.ilvl > 0 then
            table.insert(samples, { name = e.trackName, cur = e.cur, max = e.max, ilvl = e.ilvl })
        end
    end
    -- Calibrate the track table against what the player is wearing, then
    -- re-resolve so potentials use the calibrated ladder.
    if self:CalibrateTracks(samples) then
        for _, slot in ipairs(self.SLOTS) do
            self.gear[slot.id] = ScanSlot(slot.id)
        end
    end
    self.gearScanned = true
    self:Fire("GEAR_UPDATED")
end

-- Samples from bags too (only used to improve calibration / learn names).
function ns:ScanBagSamples()
    local samples = {}
    if not C_Container or not C_TooltipInfo or not C_TooltipInfo.GetBagItem then return samples end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local name, cur, max = UpgradeInfoOf(link)
                if not cur then
                    local data = C_TooltipInfo.GetBagItem(bag, slot)
                    name, cur, max = ParseUpgradeFromTooltip(data)
                end
                if cur and max then
                    local ilvl = ItemLevelOf(link)
                    if ilvl and ilvl > 0 then
                        table.insert(samples, { name = name, cur = cur, max = max, ilvl = ilvl })
                    end
                end
            end
        end
    end
    return samples
end

-------------------------------------------------------------------------------
-- Weapon configuration helpers
-------------------------------------------------------------------------------
local function IsWeaponEntry(e)
    return e and not e.empty and e.classID == ns.ITEM_CLASS_WEAPON
end

local function IsTwoHand(e)
    return e and e.equipLoc == "INVTYPE_2HWEAPON"
end

-- Return the list of equipped slot IDs a dropped item of the given equipLoc could replace.
function ns:CandidateSlotsFor(equipLoc)
    local map = self.INVTYPE_SLOTS[equipLoc]
    if type(map) == "table" then return map end
    local mh, oh = self.gear[16], self.gear[17]
    if map == "WEAPON_2H" then
        -- Titan's Grip style: two 2H equipped -> either hand; otherwise main hand.
        if IsTwoHand(mh) and IsTwoHand(oh) then return { 16, 17 } end
        return { 16 }
    elseif map == "WEAPON_1H" then
        -- Dual wielding one-handers -> either hand. Otherwise main hand only.
        if IsWeaponEntry(oh) and not IsTwoHand(oh) then return { 16, 17 } end
        return { 16 }
    end
    return nil
end

-------------------------------------------------------------------------------
-- Slot manual state
-------------------------------------------------------------------------------
function ns:GetSlotState(slotID)
    return (self.cdb and self.cdb.slotState[slotID]) or "auto"
end

function ns:CycleSlotState(slotID)
    local cur = self:GetSlotState(slotID)
    local nextState = (cur == "auto" and "want") or (cur == "want" and "skip") or "auto"
    if nextState == "auto" then
        self.cdb.slotState[slotID] = nil
    else
        self.cdb.slotState[slotID] = nextState
    end
    self:Fire("SETTINGS_CHANGED")
end

-------------------------------------------------------------------------------
-- Item state per spec: "want" (the wanted list) or "exclude".
-- Kept per spec because a wanted list is a BiS list, and BiS differs per spec.
-------------------------------------------------------------------------------
local function StatesFor(self)
    if not self.cdb then return nil end
    local spec = self:GetEvalSpecID()
    if not spec then return nil end
    local by = self.cdb.itemStateBySpec
    if not by then by = {}; self.cdb.itemStateBySpec = by end
    -- one-time move of the old flat table into the current spec
    local flat = self.cdb.itemState
    if flat and next(flat) then
        by[spec] = by[spec] or {}
        for id, state in pairs(flat) do
            if by[spec][id] == nil then by[spec][id] = state end
        end
        wipe(flat)
    end
    by[spec] = by[spec] or {}
    return by[spec]
end

-- Voidcore targets: the drops you would spend a Nebulous Voidcore on, a
-- second flag next to the wanted list. [specID] = { [itemID] = true }
local function VoidcoreFor(self)
    if not self.cdb then return nil end
    local spec = self:GetEvalSpecID()
    if not spec then return nil end
    self.cdb.voidcoreBySpec = self.cdb.voidcoreBySpec or {}
    local t = self.cdb.voidcoreBySpec[spec]
    if not t then t = {}; self.cdb.voidcoreBySpec[spec] = t end
    return t
end

function ns:GetItemState(itemID)
    local t = StatesFor(self)
    return t and t[itemID] or nil
end

-- Excluding an item (already rolled it) also drops it as a Voidcore target.
function ns:SetItemState(itemID, state)
    local t = StatesFor(self)
    if not t then return end
    t[itemID] = state
    if state == "exclude" then
        local vc = VoidcoreFor(self)
        if vc then vc[itemID] = nil end
    end
    self:Fire("SETTINGS_CHANGED")
end

function ns:IsVoidcoreTarget(itemID)
    local t = VoidcoreFor(self)
    return (t and t[itemID]) and true or false
end

-- Marking a Voidcore target lifts an exclusion.
function ns:SetVoidcoreTarget(itemID, on)
    local t = VoidcoreFor(self)
    if not t then return end
    t[itemID] = on and true or nil
    local states = StatesFor(self)
    if on and states and states[itemID] == "exclude" then states[itemID] = nil end
    self:Fire("SETTINGS_CHANGED")
end

-- Sorted Voidcore target item IDs for the evaluated spec.
function ns:VoidcoreItemIDs()
    local out = {}
    local t = VoidcoreFor(self)
    if t then for id in pairs(t) do out[#out + 1] = id end end
    table.sort(out)
    return out
end

-- Sorted list of wanted item IDs for the evaluated spec.
function ns:WantedItemIDs()
    local out = {}
    local t = StatesFor(self)
    if t then
        for id, state in pairs(t) do if state == "want" then out[#out + 1] = id end end
    end
    table.sort(out)
    return out
end

function ns:ClearItemStates()
    local t = StatesFor(self)
    if t then wipe(t) end
    local vc = VoidcoreFor(self)
    if vc then wipe(vc) end
    self:Fire("SETTINGS_CHANGED")
end

-------------------------------------------------------------------------------
-- Obtained: a wanted item that turns up equipped or in the bags leaves the
-- wanted list on its own, so the window never keeps pointing at it.
-------------------------------------------------------------------------------
function ns:OwnsItem(itemID)
    for _, g in pairs(self.gear or {}) do
        if g.itemID == itemID then return true end
    end
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, itemID, true)
        if ok and type(n) == "number" and not self.issecret(n) and n > 0 then return true end
    end
    return false
end

-- Loot table entry for an item ID (any dungeon or boss), or nil.
function ns:LootItem(itemID)
    local entry = self.loot
    if not entry then return nil end
    for _, d in pairs(entry.dungeons or {}) do
        for _, item in ipairs(d.items or {}) do
            if item.itemID == itemID then return item end
        end
    end
    for _, raid in ipairs(entry.raids or {}) do
        for _, boss in ipairs(raid.bosses) do
            for _, l in pairs(boss.loot or {}) do
                for _, item in ipairs(l.items or {}) do
                    if item.itemID == itemID then return item end
                end
            end
        end
    end
    return nil
end

-- A wanted item or Voidcore target that turned up leaves its list.
function ns:CheckObtained()
    local states = StatesFor(self)
    if not states then return end
    local targets = VoidcoreFor(self) or {}
    local spec = self:GetEvalSpecID()
    local got = {}
    for itemID, state in pairs(states) do
        if state == "want" and self:OwnsItem(itemID) then
            states[itemID] = nil
            got[itemID] = true
        end
    end
    for itemID in pairs(targets) do
        if self:OwnsItem(itemID) then
            targets[itemID] = nil
            got[itemID] = true
        end
    end
    local changed = false
    for itemID in pairs(got) do
        self.cdb.obtained = self.cdb.obtained or {}
        self.cdb.obtained[spec] = self.cdb.obtained[spec] or {}
        self.cdb.obtained[spec][itemID] = time()
        local item = self:LootItem(itemID)
        self:Print("Got it:", item and (item.link or item.name) or ("item " .. itemID), "- removed from your list.")
        changed = true
    end
    if changed then self:Fire("SETTINGS_CHANGED") end
end

-------------------------------------------------------------------------------
-- List sharing: "SF2:<specID>:<wanted ids>:<Voidcore target ids>"
-- (SF1 carried only the wanted ids and still imports.)
-------------------------------------------------------------------------------
function ns:ExportWanted()
    return string.format("SF2:%d:%s:%s", self:GetEvalSpecID() or 0,
        table.concat(self:WantedItemIDs(), ","), table.concat(self:VoidcoreItemIDs(), ","))
end

-- Adds the items in the string to the current spec's lists. Returns the
-- number added, or nil and a reason.
function ns:ImportWanted(text)
    if type(text) ~= "string" then return nil, "empty" end
    local spec, list, targets = text:match("SF%d:(%d+):([%d,]*):?([%d,]*)")
    if not spec then return nil, "not a Slot Filler list" end
    local t = StatesFor(self)
    local vc = VoidcoreFor(self)
    if not t or not vc then return nil, "no spec" end
    local n = 0
    for id in list:gmatch("%d+") do
        id = tonumber(id)
        if id and t[id] ~= "want" then t[id] = "want"; n = n + 1 end
    end
    for id in (targets or ""):gmatch("%d+") do
        id = tonumber(id)
        if id and not vc[id] then vc[id] = true; n = n + 1 end
    end
    self:Fire("SETTINGS_CHANGED")
    return n, tonumber(spec)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
ns:On("LOGIN", function()
    ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
        ns:Schedule("gear", 0.5, function() ns:ScanGear() end)
        ns:Schedule("obtained", 1, function() ns:CheckObtained() end)
    end)
    ns:RegisterEvent("BAG_UPDATE_DELAYED", function()
        ns:Schedule("obtained", 1, function() ns:CheckObtained() end)
    end)
    -- item data can arrive late right after login
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        ns:Schedule("gear-login", 2, function() ns:ScanGear() end)
    end)
end)
