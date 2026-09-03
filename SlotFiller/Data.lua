-- Slot Filler: static data (slots, inventory types, fallback ID tables).
local _, ns = ...

-------------------------------------------------------------------------------
-- Equipment slots we care about (no shirt/tabard).
-------------------------------------------------------------------------------
ns.SLOTS = {
    { id = 1,  key = "HEAD",     name = HEADSLOT,          icon = 136516 }, -- INV_Helmet_..
    { id = 2,  key = "NECK",     name = NECKSLOT,          icon = 136519 },
    { id = 3,  key = "SHOULDER", name = SHOULDERSLOT,      icon = 136526 },
    { id = 15, key = "BACK",     name = BACKSLOT,          icon = 136512 },
    { id = 5,  key = "CHEST",    name = CHESTSLOT,         icon = 136513 },
    { id = 9,  key = "WRIST",    name = WRISTSLOT,         icon = 136530 },
    { id = 10, key = "HANDS",    name = HANDSSLOT,         icon = 136515 },
    { id = 6,  key = "WAIST",    name = WAISTSLOT,         icon = 136529 },
    { id = 7,  key = "LEGS",     name = LEGSSLOT,          icon = 136517 },
    { id = 8,  key = "FEET",     name = FEETSLOT,          icon = 136514 },
    { id = 11, key = "FINGER1",  name = FINGER0SLOT,       icon = 136514 },
    { id = 12, key = "FINGER2",  name = FINGER1SLOT,       icon = 136514 },
    { id = 13, key = "TRINKET1", name = TRINKET0SLOT,      icon = 136528 },
    { id = 14, key = "TRINKET2", name = TRINKET1SLOT,      icon = 136528 },
    { id = 16, key = "MAINHAND", name = MAINHANDSLOT,      icon = 136518 },
    { id = 17, key = "OFFHAND",  name = SECONDARYHANDSLOT, icon = 136524 },
}

ns.SLOT_BY_ID = {}
for _, s in ipairs(ns.SLOTS) do ns.SLOT_BY_ID[s.id] = s end

-- Empty slot textures from the character frame (used when nothing equipped).
ns.SLOT_EMPTY_TEXTURE = {
    [1] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head",
    [2] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Neck",
    [3] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder",
    [15] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest", -- no dedicated back texture
    [5] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
    [9] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists",
    [10] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands",
    [6] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist",
    [7] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs",
    [8] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet",
    [11] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger",
    [12] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger",
    [13] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket",
    [14] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket",
    [16] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand",
    [17] = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand",
}

-- Short labels for the slot strip.
ns.SLOT_SHORT = {
    [1] = "Head", [2] = "Neck", [3] = "Shldr", [15] = "Back", [5] = "Chest",
    [9] = "Wrist", [10] = "Hands", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [11] = "Ring", [12] = "Ring", [13] = "Trink", [14] = "Trink",
    [16] = "MH", [17] = "OH",
}

-- Tier tokens are not equippable; the journal names the slot they turn
-- into. slot key -> the inventory type the token stands for
ns.SLOT_INVTYPE = {
    HEAD = "INVTYPE_HEAD", NECK = "INVTYPE_NECK", SHOULDER = "INVTYPE_SHOULDER", BACK = "INVTYPE_CLOAK",
    CHEST = "INVTYPE_CHEST", WRIST = "INVTYPE_WRIST", HANDS = "INVTYPE_HAND", WAIST = "INVTYPE_WAIST",
    LEGS = "INVTYPE_LEGS", FEET = "INVTYPE_FEET", FINGER1 = "INVTYPE_FINGER", FINGER2 = "INVTYPE_FINGER",
    TRINKET1 = "INVTYPE_TRINKET", TRINKET2 = "INVTYPE_TRINKET",
}

-------------------------------------------------------------------------------
-- Inventory type (itemEquipLoc string) -> candidate equipment slot IDs.
-- Weapons are resolved dynamically in Gear.lua based on what is equipped.
-------------------------------------------------------------------------------
ns.INVTYPE_SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_WEAPON = "WEAPON_1H",          -- one-hand, either hand
    INVTYPE_2HWEAPON = "WEAPON_2H",
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_RANGED = { 16 },
    INVTYPE_RANGEDRIGHT = { 16 },
    INVTYPE_THROWN = { 16 },
    -- a tier token traded for the set piece of any slot (Ula'tek's Curio):
    -- head, shoulder, chest, hands, legs; the weakest of them is the target
    TIER_ANY = { 1, 3, 5, 10, 7 },
}

-- Item classes/subclasses that are weapons (LE_ITEM_CLASS_WEAPON = 2).
ns.ITEM_CLASS_WEAPON = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
ns.ITEM_CLASS_ARMOR = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4

-------------------------------------------------------------------------------
-- Fallback tables (used only when the live API mapping fails).
-- Source: Raider.IO db_dungeons.lua for season "mn-2" (12.1.0), 2026-09-01.
-- challengeMapID -> instance map ID
-------------------------------------------------------------------------------
ns.FALLBACK_INSTANCE_MAP = {
    [249] = 1762, -- Kings' Rest
    [250] = 1877, -- Temple of Sethraliss
    [399] = 2521, -- Ruby Life Pools
    [587] = 2813, -- Murder Row
    [584] = 2859, -- The Blinding Vale
    [586] = 2825, -- Den of Nalorakk
    [585] = 2923, -- Voidscar Arena
    [588] = 2993, -- Altar of Fangs
}

-- challengeMapID -> Encounter Journal instance ID (JournalInstance.ID, build 12.1.0.69497)
ns.FALLBACK_JOURNAL = {
    [249] = 1041, -- Kings' Rest
    [250] = 1030, -- Temple of Sethraliss
    [399] = 1202, -- Ruby Life Pools
    [587] = 1304, -- Murder Row
    [584] = 1309, -- The Blinding Vale
    [586] = 1311, -- Den of Nalorakk
    [585] = 1313, -- Voidscar Arena
    [588] = 1322, -- Altar of Fangs (its journal row points at the raid map, so name/ID fallbacks matter)
}

-- challengeMapID -> premade group finder activity IDs (all difficulties)
ns.FALLBACK_ACTIVITY_IDS = {
    [249] = { 512, 513, 514, 515, 660, 661 },
    [250] = { 503, 504, 505, 542, 645 },
    [399] = { 1173, 1174, 1175, 1176 },
    [587] = { 1749, 1750, 1751, 1950 },
    [584] = { 1699, 1700, 1701, 1949 },
    [586] = { 1721, 1722, 1723, 1952 },
    [585] = { 1754, 1755, 1756, 1951 },
    [588] = { 1930, 1931, 1932, 1933 },
}

-- Name overrides for cases where the challenge map name differs from the
-- journal instance name (mega-dungeon wings etc.). normalized name -> normalized name
ns.NAME_ALIASES = {
    -- ["tazavesh streets of wonder"] = "tazavesh the veiled market",
}

-------------------------------------------------------------------------------
-- Upgrade classes
-------------------------------------------------------------------------------
ns.UPGRADE_NONE = 0
ns.UPGRADE_STAT = 1   -- same level once upgraded free, better stats (Match level only)
ns.UPGRADE_ILVL = 2   -- immediate ilvl gain, same or lower potential
ns.UPGRADE_TRACK = 3  -- higher fully-upgraded potential
ns.UPGRADE_WANT = 4   -- user-flagged

ns.UPGRADE_COLOR = {
    [ns.UPGRADE_NONE] = { 0.55, 0.55, 0.55 },
    [ns.UPGRADE_STAT] = { 1.00, 0.60, 0.25 },
    [ns.UPGRADE_ILVL] = { 1.00, 0.82, 0.00 },
    [ns.UPGRADE_TRACK] = { 0.10, 1.00, 0.10 },
    [ns.UPGRADE_WANT] = { 0.40, 0.75, 1.00 },
}

-- Nebulous Voidcore (bonus roll) accent colour
ns.VC_COLOR = { 0.78, 0.55, 1.00 }
ns.VC_HEX = "|cffc78cff"

ns.UPGRADE_LABEL = {
    [ns.UPGRADE_NONE] = "no upgrade",
    [ns.UPGRADE_STAT] = "stat upgrade",
    [ns.UPGRADE_ILVL] = "ilvl upgrade",
    [ns.UPGRADE_TRACK] = "track upgrade",
    [ns.UPGRADE_WANT] = "wanted",
}
