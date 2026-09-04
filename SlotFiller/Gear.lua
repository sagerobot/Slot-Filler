-- Slot Filler: the player's equipped gear, free upgrade levels, slot and item
-- overrides, owned copies of drops, and the wanted list.
local _, ns = ...

-------------------------------------------------------------------------------
-- Reading an item's level and upgrade track
-------------------------------------------------------------------------------
-- "Upgrade Level: %s %d/%d" (track name and step) as a Lua pattern.
local UPGRADE_PATTERN = "^%s*" .. ITEM_UPGRADE_TOOLTIP_FORMAT_STRING
    :gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1"):gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)") .. "%s*$"

-- (trackName, cur, max) from tooltip data, or nil.
function ns.ParseUpgradeFromTooltip(data)
    for i = 1, math.min(data and data.lines and #data.lines or 0, 12) do
        local text = data.lines[i].leftText
        if text and not ns.issecret(text) then
            local name, cur, max = ns.StripColor(text):match(UPGRADE_PATTERN)
            if cur then return name:gsub("^%s+", ""):gsub("%s+$", ""), tonumber(cur), tonumber(max) end
        end
    end
    return nil
end

function ns.ItemLevelOf(link)
    if not link then return nil end
    local ilvl = C_Item.GetDetailedItemLevelInfo(link)
    if not ilvl or ilvl == 0 then ilvl = select(4, C_Item.GetItemInfo(link)) end
    return ilvl
end

-- The client's own answer for a link: trackName, cur, max, maxItemLevel (the
-- fully upgraded level), or nil.
function ns.UpgradeInfoOf(link)
    if not link then return nil end
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

-- Fills an entry from its link: item, level, equip location, and the track
-- with the fully upgraded level (`potential`). `tooltipFallback` reads the
-- upgrade line when the direct API has none.
local function FillFromLink(entry, link, tooltipFallback)
    local itemID, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
    entry.link, entry.itemID, entry.equipLoc, entry.classID, entry.subClassID = link, itemID, equipLoc, classID, subClassID
    entry.ilvl = ns.ItemLevelOf(link) or 0
    local name, cur, max, maxIlvl = ns.UpgradeInfoOf(link)
    if not cur and tooltipFallback then name, cur, max = tooltipFallback() end
    entry.trackName, entry.cur, entry.max = name, cur, max
    entry.potential = entry.ilvl
    if cur and max then
        local track = ns:ResolveTrack(name, cur, max, entry.ilvl)
        entry.track = track
        if maxIlvl and maxIlvl >= entry.ilvl then
            entry.potential = maxIlvl
        elseif track then
            local delta = entry.ilvl - (track.ilvls[cur] or entry.ilvl) -- usually 0; keeps odd items sane
            entry.potential = math.max(track.max + delta, entry.ilvl)
        end
    end
    return entry
end

-------------------------------------------------------------------------------
-- Equipped gear
-- ns.gear[slotID] = { slotID, link, itemID, ilvl, trackName, cur, max, track, potential, equipLoc }
-------------------------------------------------------------------------------
ns.gear = {}

local function ScanSlot(slotID)
    local link = GetInventoryItemLink("player", slotID)
    if not link then return { slotID = slotID, empty = true, ilvl = 0, potential = 0 } end
    return FillFromLink({ slotID = slotID }, link, function()
        return ns.ParseUpgradeFromTooltip(C_TooltipInfo.GetInventoryItem("player", slotID))
    end)
end

function ns:ScanGear()
    local samples = {}
    for _, slot in ipairs(self.SLOTS) do
        local e = ScanSlot(slot.id)
        self.gear[slot.id] = e
        if e.cur and e.max and e.ilvl > 0 then
            samples[#samples + 1] = { name = e.trackName, cur = e.cur, max = e.max, ilvl = e.ilvl }
        end
    end
    -- calibrate the track table against what is worn, then resolve again so
    -- the potentials use the calibrated ladder
    if self:CalibrateTracks(samples) then
        for _, slot in ipairs(self.SLOTS) do self.gear[slot.id] = ScanSlot(slot.id) end
    end
    self:ScanWatermarks()
    self.gearScanned = true
    self:Fire("GEAR_UPDATED")
end

-- What is worn now, per slot: { [slotID] = { itemID, ilvl, name } }; nil
-- before the gear has been scanned.
function ns:GearSnapshot()
    if not self.gearScanned then return nil end
    local snap = {}
    for _, s in ipairs(self.SLOTS) do
        local g = self.gear[s.id]
        if g and not g.empty and g.itemID then
            snap[s.id] = { itemID = g.itemID, ilvl = g.ilvl or 0, name = g.link:match("%[(.-)%]") }
        end
    end
    return snap
end

-------------------------------------------------------------------------------
-- Free upgrade levels (Midnight): an item can be upgraded for free up to the
-- highest item level the character has already reached in that slot; rings,
-- trinkets and one-handers go by the lower of the pair. The client keeps
-- that number per "redundancy slot" (Enum.ItemRedundancySlot). It is read
-- when the gear is scanned, so an evaluation never calls the API:
-- ns.watermarks[redundancySlot] = ilvl.
-------------------------------------------------------------------------------
local RS = Enum.ItemRedundancySlot
local REDUNDANCY_BY_SLOT = {
    [1] = RS.Head, [2] = RS.Neck, [3] = RS.Shoulder, [5] = RS.Chest, [6] = RS.Waist, [7] = RS.Legs, [8] = RS.Feet,
    [9] = RS.Wrist, [10] = RS.Hand, [11] = RS.Finger, [12] = RS.Finger, [13] = RS.Trinket, [14] = RS.Trinket, [15] = RS.Cloak,
}
local REDUNDANCY_BY_EQUIPLOC = {
    INVTYPE_2HWEAPON = RS.Twohand, INVTYPE_RANGED = RS.Twohand, INVTYPE_THROWN = RS.Twohand,
    INVTYPE_WEAPONMAINHAND = RS.MainhandWeapon, INVTYPE_RANGEDRIGHT = RS.MainhandWeapon, INVTYPE_WEAPON = RS.OnehandWeapon,
    INVTYPE_WEAPONOFFHAND = RS.Offhand, INVTYPE_HOLDABLE = RS.Offhand, INVTYPE_SHIELD = RS.Offhand,
}
ns.REDUNDANCY_NAMES = {
    [0] = "Head", [1] = "Neck", [2] = "Shoulder", [3] = "Chest", [4] = "Waist", [5] = "Legs", [6] = "Feet", [7] = "Wrist",
    [8] = "Hands", [9] = "Rings", [10] = "Trinkets", [11] = "Back", [12] = "Two-hand", [13] = "Main hand", [14] = "One-hand",
    [15] = "Second one-hand", [16] = "Off hand",
}
ns.watermarks = {}

-- Reads every slot's level from the client. Returns true when any changed.
function ns:ScanWatermarks()
    local marks, changed, any = {}, false, false
    for r = 0, 16 do
        local ok, mark = pcall(C_ItemUpgrade.GetHighWatermarkForSlot, r)
        mark = ok and self.Num(mark) or nil
        if mark and mark > 0 then marks[r] = mark; any = true end
        if marks[r] ~= self.watermarks[r] then changed = true end
    end
    self.watermarks = marks
    self.watermarkSource = any and "api" or "gear"
    return changed
end

-- The redundancy slot a drop belongs to: the client's answer, else by
-- inventory type. Static per item, so remembered.
local redundancyByItem = {}
function ns:RedundancySlotFor(item)
    local id = item.itemID
    if id and redundancyByItem[id] ~= nil then return redundancyByItem[id] or nil end
    local r
    if item.link then
        local ok, v = pcall(C_ItemUpgrade.GetHighWatermarkSlotForItem, item.link)
        if ok then r = self.Num(v) end
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
-- the weaker candidate slot already wears (all there is to go on when the
-- client reports nothing). Dual wielders go by the lower of the two
-- one-hander marks. 0 when nothing is known.
function ns:FreeUpgradeLevel(item, candidates)
    local floor = 0
    for i, slotID in ipairs(candidates or {}) do
        local g = self.gear[slotID]
        local l = (g and not g.empty and g.ilvl) or 0
        if i == 1 or l < floor then floor = l end
    end
    local r = self:RedundancySlotFor(item)
    local mark = r and self.watermarks[r] or 0
    if r == RS.OnehandWeapon then
        local oh = self.gear[17]
        if oh and not oh.empty and oh.classID == self.ITEM_CLASS_WEAPON and oh.equipLoc ~= "INVTYPE_2HWEAPON" then
            local second = self.watermarks[RS.OnehandWeaponSecond]
            if second and second < mark then mark = second end
        end
    end
    return math.max(mark, floor)
end

-------------------------------------------------------------------------------
-- Weapons: the equipped slots a drop of the given equip location could replace.
-------------------------------------------------------------------------------
local function IsTwoHand(e)
    return e and e.equipLoc == "INVTYPE_2HWEAPON"
end

function ns:CandidateSlotsFor(equipLoc)
    local map = self.INVTYPE_SLOTS[equipLoc]
    if type(map) == "table" then return map end
    local mh, oh = self.gear[16], self.gear[17]
    if map == "WEAPON_2H" then
        -- Titan's Grip: two two-handers equipped -> either hand; otherwise main hand
        if IsTwoHand(mh) and IsTwoHand(oh) then return { 16, 17 } end
        return { 16 }
    elseif map == "WEAPON_1H" then
        -- dual wielding one-handers -> either hand; otherwise main hand
        if oh and not oh.empty and oh.classID == self.ITEM_CLASS_WEAPON and not IsTwoHand(oh) then return { 16, 17 } end
        return { 16 }
    end
    return nil
end

-------------------------------------------------------------------------------
-- Slot overrides: "auto" (absent), "want" (every drop counts), "skip"
-------------------------------------------------------------------------------
function ns:GetSlotState(slotID)
    return (self.cdb and self.cdb.slotState[slotID]) or "auto"
end

-- `withID`: a paired slot (the other ring or trinket) set to the same state.
function ns:CycleSlotState(slotID, withID)
    local cur = self:GetSlotState(slotID)
    local nextState = (cur == "auto" and "want") or (cur == "want" and "skip") or nil
    self.cdb.slotState[slotID] = nextState
    if withID then self.cdb.slotState[withID] = nextState end
    self:Fire("SETTINGS_CHANGED")
end

-------------------------------------------------------------------------------
-- Item overrides per spec: "want" (the wanted list) or "exclude", and the
-- Voidcore targets, a second flag next to the wanted list.
-------------------------------------------------------------------------------
local function PerSpec(self, field)
    local spec = self.cdb and self:GetEvalSpecID()
    if not spec then return nil end
    local by = self.cdb[field]
    by[spec] = by[spec] or {}
    return by[spec]
end

function ns:GetItemState(itemID)
    local t = PerSpec(self, "itemStateBySpec")
    return t and t[itemID] or nil
end

-- Excluding an item (already rolled it) also drops it as a Voidcore target.
function ns:SetItemState(itemID, state)
    local t = PerSpec(self, "itemStateBySpec")
    if not t then return end
    t[itemID] = state
    if state == "exclude" then PerSpec(self, "voidcoreBySpec")[itemID] = nil end
    self:Fire("SETTINGS_CHANGED")
end

function ns:CycleItemState(itemID)
    self:SetItemState(itemID, self:GetItemState(itemID) ~= "exclude" and "exclude" or nil)
end

function ns:IsVoidcoreTarget(itemID)
    local t = PerSpec(self, "voidcoreBySpec")
    return (t and t[itemID]) and true or false
end

-- Marking a Voidcore target lifts an exclusion.
function ns:SetVoidcoreTarget(itemID, on)
    local t = PerSpec(self, "voidcoreBySpec")
    if not t then return end
    t[itemID] = on and true or nil
    local states = PerSpec(self, "itemStateBySpec")
    if on and states[itemID] == "exclude" then states[itemID] = nil end
    self:Fire("SETTINGS_CHANGED")
end

local function SortedKeys(t, wanted)
    local out = {}
    for id, v in pairs(t or {}) do
        if wanted == nil or v == wanted then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

function ns:VoidcoreItemIDs()
    return SortedKeys(PerSpec(self, "voidcoreBySpec"))
end

function ns:WantedItemIDs()
    return SortedKeys(PerSpec(self, "itemStateBySpec"), "want")
end

function ns:ClearItemStates()
    local t, vc = PerSpec(self, "itemStateBySpec"), PerSpec(self, "voidcoreBySpec")
    if t then wipe(t) end
    if vc then wipe(vc) end
    self:Fire("SETTINGS_CHANGED")
end

-------------------------------------------------------------------------------
-- List sharing: "SF2:<specID>:<wanted ids>:<Voidcore target ids>"
-------------------------------------------------------------------------------
function ns:ExportWanted()
    return string.format("SF2:%d:%s:%s", self:GetEvalSpecID() or 0,
        table.concat(self:WantedItemIDs(), ","), table.concat(self:VoidcoreItemIDs(), ","))
end

-- Adds the items in the string to the current spec's lists. Returns the
-- number added, or nil and a reason.
function ns:ImportWanted(text)
    if type(text) ~= "string" then return nil, "empty" end
    local spec, list, targets = text:match("SF2:(%d+):([%d,]*):([%d,]*)")
    if not spec then return nil, "not a Slot Filler list" end
    local t, vc = PerSpec(self, "itemStateBySpec"), PerSpec(self, "voidcoreBySpec")
    if not t then return nil, "no spec" end
    local n = 0
    for id in list:gmatch("%d+") do
        id = tonumber(id)
        if t[id] ~= "want" then t[id] = "want"; n = n + 1 end
    end
    for id in targets:gmatch("%d+") do
        id = tonumber(id)
        if not vc[id] then vc[id] = true; n = n + 1 end
    end
    self:Fire("SETTINGS_CHANGED")
    return n, tonumber(spec)
end

-------------------------------------------------------------------------------
-- Owned copies: equipped, in the bags, the bank (once visited this session),
-- the reagent bank or the warband bank, from the client; and, with Syndicator
-- (Baganator's tracking) loaded, what it remembers of this character's bank
-- and the warband bank between sessions. A drop you already have is no
-- upgrade, and a wanted one leaves the list on its own.
--
-- Links are collected once per evaluation pass; a copy's level and track are
-- worked out only when an item is asked about.
-------------------------------------------------------------------------------
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

local BANK_BAGS = { -1, -3, 6, 7, 8, 9, 10, 11, 12 }
for i = 1, 5 do
    local id = Enum.BagIndex["AccountBankTab_" .. i]
    if id then BANK_BAGS[#BANK_BAGS + 1] = id end
end

local function BuildOwnedLinks(self)
    local index = {}
    for _, g in pairs(self.gear) do
        if g.link then AddLink(index, g.link, "equipped") end
    end
    local containers = {}
    for bag = 0, 5 do containers[#containers + 1] = { bag, "bags" } end
    for _, bag in ipairs(BANK_BAGS) do containers[#containers + 1] = { bag, "bank" } end
    for _, c in ipairs(containers) do
        local ok, n = pcall(C_Container.GetContainerNumSlots, c[1])
        for slot = 1, (ok and tonumber(n)) or 0 do
            local ok2, link = pcall(C_Container.GetContainerItemLink, c[1], slot)
            if ok2 then AddLink(index, link, c[2]) end
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
        local entry = FillFromLink({ where = copy.where }, copy.link)
        if not best or entry.potential > best.potential then best = entry end
    end
    if not best then
        local ok, on = pcall(C_Item.IsEquippedItem, itemID)
        local counted = ok and on == true
        if not counted then
            local ok2, n = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
            counted = ok2 and (self.Num(n) or 0) > 0
        end
        if counted then best = { itemID = itemID, where = "bags or bank", unknownLevel = true, ilvl = 0, potential = math.huge } end
    end
    ownedBest[itemID] = best or false
    return best
end

function ns:OwnsItem(itemID)
    return self:OwnedCopy(itemID) ~= nil
end

-- A wanted item or Voidcore target that turned up leaves its list.
function ns:CheckObtained()
    self:ClearOwnedCache()
    local states, targets = PerSpec(self, "itemStateBySpec"), PerSpec(self, "voidcoreBySpec")
    if not states then return end
    local got = {}
    for itemID, state in pairs(states) do
        if state == "want" and self:OwnsItem(itemID) then states[itemID] = nil; got[itemID] = true end
    end
    for itemID in pairs(targets) do
        if self:OwnsItem(itemID) then targets[itemID] = nil; got[itemID] = true end
    end
    if not next(got) then return end
    for itemID in pairs(got) do
        local item = self:LootItem(itemID)
        self:Print("Got it:", item and (item.link or item.name) or ("item " .. itemID), "- removed from your list.")
    end
    self:Fire("SETTINGS_CHANGED")
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
            if ns:ScanWatermarks() and ns.db.matchLevel then ns:Fire("GEAR_UPDATED") end
        end)
    end)
    -- item data can arrive late right after login
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        ns:Schedule("gear-login", 2, function() ns:ScanGear() end)
    end)
end)
