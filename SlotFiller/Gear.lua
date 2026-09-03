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

local FillFromLink

local function ScanSlot(slotID)
    local link = GetInventoryItemLink("player", slotID)
    local entry = { slotID = slotID }
    if not link then
        entry.empty = true
        entry.ilvl = 0
        entry.potential = 0
        return entry
    end
    FillFromLink(entry, link, function()
        local data = C_TooltipInfo and C_TooltipInfo.GetInventoryItem and C_TooltipInfo.GetInventoryItem("player", slotID)
        return ParseUpgradeFromTooltip(data)
    end)
    return entry
end

-- An entry's item, level and track from its link. `tooltipFallback`
-- (optional) reads the upgrade line when the direct API has none.
function FillFromLink(entry, link, tooltipFallback)
    entry.link = link
    entry.itemID = C_Item.GetItemInfoInstant(link)
    entry.ilvl = ItemLevelOf(link) or 0
    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
    entry.equipLoc = equipLoc
    entry.classID = classID
    entry.subClassID = subClassID
    -- Upgrade track: direct API first, tooltip line as fallback.
    local name, cur, max, maxIlvl = UpgradeInfoOf(link)
    if not cur and tooltipFallback then name, cur, max = tooltipFallback() end
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
    self:ScanWatermarks()
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
-- Free upgrade levels (Midnight): an item can be upgraded for free up to the
-- highest item level the character has already reached in that slot; rings,
-- trinkets and one-handers go by the lower of the pair. The client keeps
-- that number per "redundancy slot" (Enum.ItemRedundancySlot) and reports
-- it through C_ItemUpgrade. It is read when the gear is scanned, so an
-- evaluation never calls the API: ns.watermarks[redundancySlot] = ilvl.
-------------------------------------------------------------------------------
local RS = (Enum and Enum.ItemRedundancySlot) or {}
local RS_FINGER, RS_TRINKET = RS.Finger or 9, RS.Trinket or 10
local RS_TWOHAND, RS_MAINHAND, RS_ONEHAND, RS_ONEHAND2, RS_OFFHAND =
    RS.Twohand or 12, RS.MainhandWeapon or 13, RS.OnehandWeapon or 14, RS.OnehandWeaponSecond or 15, RS.Offhand or 16
local REDUNDANCY_BY_SLOT = {
    [1] = RS.Head or 0, [2] = RS.Neck or 1, [3] = RS.Shoulder or 2, [5] = RS.Chest or 3, [6] = RS.Waist or 4,
    [7] = RS.Legs or 5, [8] = RS.Feet or 6, [9] = RS.Wrist or 7, [10] = RS.Hand or 8, [11] = RS_FINGER, [12] = RS_FINGER,
    [13] = RS_TRINKET, [14] = RS_TRINKET, [15] = RS.Cloak or 11,
}
local REDUNDANCY_BY_EQUIPLOC = {
    INVTYPE_2HWEAPON = RS_TWOHAND, INVTYPE_RANGED = RS_TWOHAND, INVTYPE_THROWN = RS_TWOHAND,
    INVTYPE_WEAPONMAINHAND = RS_MAINHAND, INVTYPE_RANGEDRIGHT = RS_MAINHAND, INVTYPE_WEAPON = RS_ONEHAND,
    INVTYPE_WEAPONOFFHAND = RS_OFFHAND, INVTYPE_HOLDABLE = RS_OFFHAND, INVTYPE_SHIELD = RS_OFFHAND,
}
ns.REDUNDANCY_NAMES = {
    [0] = "Head", [1] = "Neck", [2] = "Shoulder", [3] = "Chest", [4] = "Waist", [5] = "Legs", [6] = "Feet", [7] = "Wrist",
    [8] = "Hands", [9] = "Rings", [10] = "Trinkets", [11] = "Back", [12] = "Two-hand", [13] = "Main hand", [14] = "One-hand",
    [15] = "Second one-hand", [16] = "Off hand",
}
ns.watermarks = {}

local function Number(v)
    if type(v) == "number" and not ns.issecret(v) and v > 0 then return v end
    return nil
end

-- Reads every slot's level from the client. Returns true when any changed.
function ns:ScanWatermarks()
    local api = C_ItemUpgrade and C_ItemUpgrade.GetHighWatermarkForSlot
    local marks, changed, any = {}, false, false
    if api then
        for r = 0, 16 do
            local ok, mark = pcall(api, r)
            mark = ok and Number(mark) or nil
            if mark then marks[r] = mark; any = true end
        end
    end
    for r = 0, 16 do
        if marks[r] ~= self.watermarks[r] then changed = true end
    end
    self.watermarks = marks
    self.watermarkSource = any and "api" or "gear"
    return changed
end

-- Which redundancy slot a drop belongs to: the client's answer, else by
-- inventory type. Static per item, so remembered.
local redundancyByItem = {}
function ns:RedundancySlotFor(item)
    local id = item.itemID
    local r = id and redundancyByItem[id]
    if r ~= nil then return r or nil end
    r = nil
    if item.link and C_ItemUpgrade and C_ItemUpgrade.GetHighWatermarkSlotForItem then
        local ok, v = pcall(C_ItemUpgrade.GetHighWatermarkSlotForItem, item.link)
        if ok and type(v) == "number" and not self.issecret(v) then r = v end
    end
    if not r and item.equipLoc ~= "TIER_ANY" then
        r = REDUNDANCY_BY_EQUIPLOC[item.equipLoc]
        if not r then
            local slots = self.INVTYPE_SLOTS[item.equipLoc]
            r = type(slots) == "table" and REDUNDANCY_BY_SLOT[slots[1]] or nil
        end
    end
    if id then redundancyByItem[id] = r or false end
    return r
end

-- The level a drop that could go in `candidates` can be upgraded to for
-- free: the client's mark for the item's redundancy slot, never below what
-- the weaker candidate slot already wears (which is all there is to go on
-- when the client reports nothing). Dual wielders go by the lower of the
-- two one-hander marks. 0 when nothing is known.
function ns:FreeUpgradeLevel(item, candidates)
    local floor
    for _, slotID in ipairs(candidates or {}) do
        local g = self.gear[slotID]
        local l = (g and not g.empty and g.ilvl) or 0
        if not floor or l < floor then floor = l end
    end
    local r = self:RedundancySlotFor(item)
    local mark = r and self.watermarks[r] or 0
    if r == RS_ONEHAND then
        local oh = self.gear[17]
        if oh and not oh.empty and oh.classID == self.ITEM_CLASS_WEAPON and oh.equipLoc ~= "INVTYPE_2HWEAPON" then
            local second = self.watermarks[RS_ONEHAND2]
            if second and second < mark then mark = second end
        end
    end
    return math.max(mark, floor or 0)
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

-- `withID`: a paired slot (the other ring or trinket) set to the same state.
function ns:CycleSlotState(slotID, withID)
    local cur = self:GetSlotState(slotID)
    local nextState = (cur == "auto" and "want") or (cur == "want" and "skip") or "auto"
    local value = nextState ~= "auto" and nextState or nil
    self.cdb.slotState[slotID] = value
    if withID then self.cdb.slotState[withID] = value end
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
-- Owned: equipped, in the bags, the bank (once visited this session), the
-- reagent bank or the warband bank, from the client; and, when Syndicator
-- (Baganator's tracking) is loaded, what it remembers of this character's
-- bank and the warband bank between sessions. A drop you already have is
-- no upgrade and a wanted one leaves the list on its own.
-------------------------------------------------------------------------------
-- The copies you hold, by item: links from the equipped gear, the bag and
-- bank containers the client can read, and Syndicator's record of this
-- character and the warband bank. Built once per evaluation pass; a
-- copy's level and track are worked out only when an item is asked about.
local ownedLinks = nil      -- itemID -> { { link, where }, ... }
local ownedBest = {}        -- itemID -> entry | false

function ns:ClearOwnedCache()
    ownedLinks = nil
    wipe(ownedBest)
end

local function AddLink(index, link, where)
    if type(link) ~= "string" or ns.issecret(link) then return end
    local itemID = tonumber(link:match("|Hitem:(%d+)"))
    if not itemID then return end
    index[itemID] = index[itemID] or {}
    table.insert(index[itemID], { link = link, where = where })
end

-- Syndicator keeps slots as { itemID, itemLink, ... } in nested tables.
local function Walk(t, index, where, depth)
    if type(t) ~= "table" or depth > 5 then return end
    if type(t.itemLink) == "string" then
        AddLink(index, t.itemLink, where)
        return
    end
    for _, v in pairs(t) do
        if type(v) == "table" then Walk(v, index, where, depth + 1) end
    end
end

local function BuildOwnedLinks(self)
    local index = {}
    for _, g in pairs(self.gear or {}) do
        if g.link then AddLink(index, g.link, "equipped") end
    end
    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemLink then
        local containers = {}
        for bag = 0, 5 do containers[#containers + 1] = { bag, "bags" } end
        local bankIDs = { -1, -3, 6, 7, 8, 9, 10, 11, 12 }
        if Enum and Enum.BagIndex then
            for _, key in ipairs({ "AccountBankTab_1", "AccountBankTab_2", "AccountBankTab_3", "AccountBankTab_4", "AccountBankTab_5" }) do
                if Enum.BagIndex[key] then bankIDs[#bankIDs + 1] = Enum.BagIndex[key] end
            end
        end
        for _, bag in ipairs(bankIDs) do containers[#containers + 1] = { bag, "bank" } end
        for _, c in ipairs(containers) do
            local ok, n = pcall(C_Container.GetContainerNumSlots, c[1])
            for slot = 1, (ok and tonumber(n)) or 0 do
                local ok2, link = pcall(C_Container.GetContainerItemLink, c[1], slot)
                if ok2 then AddLink(index, link, c[2]) end
            end
        end
    end
    local api = Syndicator and Syndicator.API
    if api and api.GetCharacter and api.GetCurrentCharacter and (not api.IsReady or api.IsReady()) then
        local ok, data = pcall(api.GetCharacter, api.GetCurrentCharacter())
        if ok and type(data) == "table" then
            Walk(data.bags, index, "bags", 0)
            Walk(data.bank, index, "bank", 0)
            Walk(data.equipped, index, "equipped", 0)
            Walk(data.void, index, "void storage", 0)
        end
        if api.GetWarband then
            local ok2, wb = pcall(api.GetWarband, 1)
            if ok2 and type(wb) == "table" then Walk(wb.bank, index, "warband bank", 0) end
        end
    end
    return index
end

-- The best copy of an item you hold (highest fully upgraded level), as an
-- entry like the equipped gear's, or nil. A copy the client counts but
-- shows no link for (a bank not visited) is owned at an unknown level.
function ns:OwnedCopy(itemID)
    if not itemID then return nil end
    local cached = ownedBest[itemID]
    if cached ~= nil then return cached or nil end
    ownedLinks = ownedLinks or BuildOwnedLinks(self)
    local best
    for _, copy in ipairs(ownedLinks[itemID] or {}) do
        local entry = { where = copy.where }
        FillFromLink(entry, copy.link)
        if not best or (entry.potential or 0) > (best.potential or 0) then best = entry end
    end
    if not best then
        local counted = false
        if C_Item and C_Item.IsEquippedItem then
            local ok, on = pcall(C_Item.IsEquippedItem, itemID)
            if ok and on == true then counted = true end
        end
        if not counted and C_Item and C_Item.GetItemCount then
            local ok, n = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
            if not ok then ok, n = pcall(C_Item.GetItemCount, itemID, true) end
            if ok and type(n) == "number" and not self.issecret(n) and n > 0 then counted = true end
        end
        if counted then best = { itemID = itemID, where = "bags or bank", unknownLevel = true, ilvl = 0, potential = math.huge } end
    end
    ownedBest[itemID] = best or false
    return best
end

function ns:OwnsItem(itemID)
    return self:OwnedCopy(itemID) ~= nil
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
    self:ClearOwnedCache()
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
        ns:ClearOwnedCache()
        ns:Schedule("gear", 0.5, function() ns:ScanGear() end)
        ns:Schedule("obtained", 1, function() ns:CheckObtained() end)
    end)
    ns:RegisterEvent("BAG_UPDATE_DELAYED", function()
        ns:ClearOwnedCache()
        ns:Schedule("obtained", 1, function() ns:CheckObtained() end)
        -- a drop that just arrived is owned now
        ns:Schedule("bags", 1.5, function() ns:Fire("BAGS_UPDATED") end)
    end)
    -- upgrading at the NPC raises a slot's free upgrade level
    ns:RegisterEvent("ITEM_UPGRADE_MASTER_UPDATE", function()
        ns:Schedule("watermarks", 1, function()
            if ns:ScanWatermarks() and ns.db and ns.db.matchLevel then ns:Fire("GEAR_UPDATED") end
        end)
    end)
    -- item data can arrive late right after login
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        ns:Schedule("gear-login", 2, function() ns:ScanGear() end)
    end)
end)
