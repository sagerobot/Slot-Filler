-- Slot Filler: static data (equipment slots, inventory types, upgrade classes).
local _, ns = ...

-------------------------------------------------------------------------------
-- Equipment slots (no shirt or tabard), in display order.
-------------------------------------------------------------------------------
ns.SLOTS = {
    { id = 1,  key = "HEAD",     name = HEADSLOT,          short = "Head",  inv = "INVTYPE_HEAD",     empty = "Head" },
    { id = 2,  key = "NECK",     name = NECKSLOT,          short = "Neck",  inv = "INVTYPE_NECK",     empty = "Neck" },
    { id = 3,  key = "SHOULDER", name = SHOULDERSLOT,      short = "Shldr", inv = "INVTYPE_SHOULDER", empty = "Shoulder" },
    { id = 15, key = "BACK",     name = BACKSLOT,          short = "Back",  inv = "INVTYPE_CLOAK",    empty = "Chest" },
    { id = 5,  key = "CHEST",    name = CHESTSLOT,         short = "Chest", inv = "INVTYPE_CHEST",    empty = "Chest" },
    { id = 9,  key = "WRIST",    name = WRISTSLOT,         short = "Wrist", inv = "INVTYPE_WRIST",    empty = "Wrists" },
    { id = 10, key = "HANDS",    name = HANDSSLOT,         short = "Hands", inv = "INVTYPE_HAND",     empty = "Hands" },
    { id = 6,  key = "WAIST",    name = WAISTSLOT,         short = "Waist", inv = "INVTYPE_WAIST",    empty = "Waist" },
    { id = 7,  key = "LEGS",     name = LEGSSLOT,          short = "Legs",  inv = "INVTYPE_LEGS",     empty = "Legs" },
    { id = 8,  key = "FEET",     name = FEETSLOT,          short = "Feet",  inv = "INVTYPE_FEET",     empty = "Feet" },
    { id = 11, key = "FINGER1",  name = FINGER0SLOT,       short = "Ring",  inv = "INVTYPE_FINGER",   empty = "Finger" },
    { id = 12, key = "FINGER2",  name = FINGER1SLOT,       short = "Ring",  inv = "INVTYPE_FINGER",   empty = "Finger" },
    { id = 13, key = "TRINKET1", name = TRINKET0SLOT,      short = "Trink", inv = "INVTYPE_TRINKET",  empty = "Trinket" },
    { id = 14, key = "TRINKET2", name = TRINKET1SLOT,      short = "Trink", inv = "INVTYPE_TRINKET",  empty = "Trinket" },
    { id = 16, key = "MAINHAND", name = MAINHANDSLOT,      short = "MH",                              empty = "MainHand" },
    { id = 17, key = "OFFHAND",  name = SECONDARYHANDSLOT, short = "OH",                              empty = "SecondaryHand" },
}

ns.SLOT_BY_ID = {}
for _, s in ipairs(ns.SLOTS) do
    ns.SLOT_BY_ID[s.id] = s
    s.emptyTexture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. s.empty
end

-- Rings and trinkets are judged as a pair (a drop replaces the weaker one)
-- and shown as one Gear row: the second slot folds into the first.
ns.PAIR_OF = { [11] = 12, [13] = 14 }
ns.PAIR_ROW = { [12] = 11, [14] = 13 }
ns.PAIR_LABEL = { [11] = "Rings", [13] = "Trinkets" }

-- Slots a tier set covers.
ns.TIER_SLOTS = { [1] = true, [3] = true, [5] = true, [10] = true, [7] = true }

-------------------------------------------------------------------------------
-- Inventory type (itemEquipLoc) -> candidate equipment slots. Weapons are
-- resolved from what is equipped (Gear.lua).
-------------------------------------------------------------------------------
ns.INVTYPE_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_WEAPON = "WEAPON_1H", INVTYPE_2HWEAPON = "WEAPON_2H",
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_RANGED = { 16 }, INVTYPE_RANGEDRIGHT = { 16 }, INVTYPE_THROWN = { 16 },
    -- a tier token traded for the set piece of any slot; the weakest is the target
    TIER_ANY = { 1, 3, 5, 10, 7 },
}

ns.ITEM_CLASS_WEAPON = Enum.ItemClass.Weapon

-------------------------------------------------------------------------------
-- Upgrade classes
-------------------------------------------------------------------------------
ns.UPGRADE_NONE = 0
ns.UPGRADE_STAT = 1   -- same level once upgraded free, better stats (Match level only)
ns.UPGRADE_ILVL = 2   -- immediate item level gain, same or lower ceiling
ns.UPGRADE_TRACK = 3  -- higher fully upgraded ceiling
ns.UPGRADE_WANT = 4   -- on the wanted list, or a Want slot

ns.UPGRADE_COLOR = {
    [ns.UPGRADE_NONE] = { 0.55, 0.55, 0.55 },
    [ns.UPGRADE_STAT] = { 1.00, 0.60, 0.25 },
    [ns.UPGRADE_ILVL] = { 1.00, 0.82, 0.00 },
    [ns.UPGRADE_TRACK] = { 0.10, 1.00, 0.10 },
    [ns.UPGRADE_WANT] = { 0.40, 0.75, 1.00 },
}
ns.UPGRADE_HEX = {}
for class, c in pairs(ns.UPGRADE_COLOR) do ns.UPGRADE_HEX[class] = ns.HexColor(c[1], c[2], c[3]) end

ns.UPGRADE_LABEL = {
    [ns.UPGRADE_NONE] = "no upgrade",
    [ns.UPGRADE_STAT] = "stat upgrade",
    [ns.UPGRADE_ILVL] = "ilvl upgrade",
    [ns.UPGRADE_TRACK] = "track upgrade",
    [ns.UPGRADE_WANT] = "wanted",
}

-- The colour of a source's Drops count: green with a track upgrade, yellow
-- with only item level gains, grey with none.
function ns.DropsHex(r)
    if not r or r.upgrades == 0 then return ns.UPGRADE_HEX[ns.UPGRADE_NONE] end
    return ns.UPGRADE_HEX[r.trackUpgrades > 0 and ns.UPGRADE_TRACK or ns.UPGRADE_ILVL]
end

-- Nebulous Voidcore accent
ns.VC_COLOR = { 0.78, 0.55, 1.00 }
ns.VC_HEX = "|cffc78cff"
