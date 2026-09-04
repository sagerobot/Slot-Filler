-- Headless harness: stubs enough of the WoW API to load Slot Filler under
-- plain Lua 5.1 and exercise its logic. Run from the repo root:
--   lua tests/harness.lua
-- Numbers follow Midnight Season 2 (Champion 1/6 = 292, +10 = 311 Hero 3/6,
-- vault/Voidcore at +10 = 318 Myth 1/6).
local ROOT = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local ADDON_DIR = ROOT .. "/SlotFiller/"

local failures = 0
local function check(cond, msg)
    if cond then
        print("  ok   " .. msg)
    else
        failures = failures + 1
        print("  FAIL " .. msg)
    end
end

-------------------------------------------------------------------------------
-- Generic widget stub: unknown method-shaped keys (SetX, GetX, IsX, ...) are
-- no-ops returning nil; any other key (regions such as .Text or .ScrollBar)
-- is nil, like a real frame that never had it.
-------------------------------------------------------------------------------
local Widget = {}
local METHOD_PREFIXES = { "Set", "Get", "Is", "Register", "Unregister", "Enable", "Disable", "Hook",
    "Clear", "Show", "Hide", "Create", "Start", "Stop", "Add", "Remove", "Num", "Update", "Refresh",
    "Apply", "Play", "Raise", "Lower", "Can", "Has" }
Widget.__index = function(t, k)
    local v = rawget(Widget, k)
    if v ~= nil then return v end
    if type(k) ~= "string" then return nil end
    for _, p in ipairs(METHOD_PREFIXES) do
        if k:sub(1, #p) == p then
            local f = function() end
            rawset(t, k, f)
            return f
        end
    end
    return nil
end
local function NewWidget(kind, name)
    local w = setmetatable({ _kind = kind, _name = name, _shown = false, _scripts = {}, _children = {} }, Widget)
    if name then _G[name] = w end
    return w
end
function Widget:SetScript(ev, fn) self._scripts[ev] = fn end
function Widget:HookScript(ev, fn)
    local old = self._scripts[ev]
    self._scripts[ev] = function(...) if old then old(...) end fn(...) end
end
function Widget:GetScript(ev) return self._scripts[ev] end
function Widget:Show() self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end
function Widget:Hide()
    local was = self._shown
    self._shown = false
    if was and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self._shown end
function Widget:IsVisible() return self._shown end
function Widget:GetHeight() return self._h or 400 end
function Widget:GetWidth() return self._w or 300 end
function Widget:SetSize(w, h) self._w, self._h = w, h end
function Widget:SetHeight(h) self._h = h end
function Widget:SetWidth(w) self._w = w end
function Widget:GetLeft() return self._left or 100 end
function Widget:GetTop() return self._top or 500 end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetScale() return 1 end
function Widget:GetFrameLevel() return 1 end
function Widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Widget:CreateFontString() return NewWidget("FontString") end
function Widget:CreateTexture() return NewWidget("Texture") end
function Widget:GetFontString() return NewWidget("FontString") end
function Widget:GetStringWidth() return 40 end
function Widget:GetChecked() return self._checked end
function Widget:SetChecked(v) self._checked = v end
function Widget:GetFrames() return self._frames or {} end
function Widget:RegisterCallback(ev, fn) self._cb = self._cb or {}; self._cb[ev] = fn end
function Widget:RegisterEvent(ev) self._events = self._events or {}; self._events[ev] = true end
function Widget:SetText(t) self._text = t end
function Widget:GetText() return self._text end

-------------------------------------------------------------------------------
-- Globals
-------------------------------------------------------------------------------
_G.CreateFrame = function(kind, name, parent, template) return NewWidget(kind, name) end
_G.UIParent = NewWidget("Frame", "UIParent")
_G.GameTooltip = NewWidget("GameTooltip", "GameTooltip")
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.geterrorhandler = function() return function(err) print("  ERROR " .. tostring(err)); failures = failures + 1 end end
_G.hooksecurefunc = function(a, b, c) end
_G.InCombatLockdown = function() return false end
_G.IsModifiedClick = function() return false end
_G.date = os.date
_G.time = os.time
_G.select = select
_G.print = print
for _, g in ipairs({ "HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "BACKSLOT", "CHESTSLOT", "WRISTSLOT", "HANDSSLOT", "WAISTSLOT",
    "LEGSSLOT", "FEETSLOT", "FINGER0SLOT", "FINGER1SLOT", "TRINKET0SLOT", "TRINKET1SLOT", "MAINHANDSLOT", "SECONDARYHANDSLOT" }) do
    _G[g] = g
end
_G.ITEM_UPGRADE_TOOLTIP_FORMAT_STRING = "Upgrade Level: %s %d/%d"
_G.ITEM_UPGRADE_TOOLTIP_FORMAT = "Upgrade Level: %d/%d"
_G.Enum = {
    ItemClass = { Weapon = 2, Armor = 4 }, ItemSlotFilterType = { NoFilter = 15 }, BagIndex = {}, TooltipDataType = { Item = 0 },
    ItemRedundancySlot = { Head = 0, Neck = 1, Shoulder = 2, Chest = 3, Waist = 4, Legs = 5, Feet = 6, Wrist = 7, Hand = 8, Finger = 9,
        Trinket = 10, Cloak = 11, Twohand = 12, MainhandWeapon = 13, OnehandWeapon = 14, OnehandWeaponSecond = 15, Offhand = 16 },
}
_G.DifficultyUtil = { ID = { DungeonChallenge = 8, DungeonMythic = 23, PrimaryRaidLFR = 17, PrimaryRaidNormal = 14, PrimaryRaidHeroic = 15, PrimaryRaidMythic = 16 } }
_G.C_Texture = { GetAtlasInfo = function() return nil end }
_G.ScrollUtil = { InitScrollFrameWithScrollBar = function() end }
_G.TooltipDataProcessor = { AddTooltipPostCall = function() end }
_G.TooltipUtil = { GetDisplayedItem = function() return nil end }
_G.STAT_CRITICAL_STRIKE, _G.STAT_HASTE, _G.STAT_MASTERY, _G.STAT_VERSATILITY = "Critical Strike", "Haste", "Mastery", "Versatility"
_G.ScrollBoxListMixin = { Event = { OnUpdate = "OnUpdate" } }
_G.Settings = nil
_G.SlashCmdList = {}
_G.issecretvalue = function() return false end

_G.IsShiftKeyDown = function() return false end

-- timers: collected and run manually
local timers = {}
_G.C_Timer = { After = function(delay, fn) table.insert(timers, { t = delay, fn = fn }) end }
local function RunTimers()
    local guard = 0
    while #timers > 0 and guard < 200 do
        guard = guard + 1
        local list = timers
        timers = {}
        for _, t in ipairs(list) do t.fn() end
    end
end

_G.C_AddOns = { GetAddOnMetadata = function() return "test" end, LoadAddOn = function() return true end, IsAddOnLoaded = function() return false end }
_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
_G.UnitName = function() return "Erunak", nil end

-- specialization, as the 12.1 client has it: the active spec under
-- C_SpecializationInfo, the loot spec and per-ID lookups as globals
_G.C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function(i) return 72, "Fury", "", 132347 end,
    GetNumSpecializationsForClassID = function() return 3 end,
}
_G.GetLootSpecialization = function() return 0 end
-- talent loadouts: [specID] = { { id, name }, ... }; SELECTED_LOADOUT[specID] = id
_G.LOADOUTS = {}
_G.SELECTED_LOADOUT = {}
_G.C_ClassTalents = {
    GetConfigIDsBySpecID = function(specID)
        local ids = {}
        for _, l in ipairs(LOADOUTS[specID] or {}) do ids[#ids + 1] = l.id end
        return ids
    end,
    GetLastSelectedSavedConfigID = function(specID) return SELECTED_LOADOUT[specID] or 0 end,
}
_G.C_Traits = {
    GetConfigInfo = function(id)
        for _, list in pairs(LOADOUTS) do
            for _, l in ipairs(list) do if l.id == id then return { ID = id, name = l.name, type = 1 } end end
        end
        return nil
    end,
}
_G.GetSpecializationInfoByID = function(id) return id, ({ [71] = "Arms", [72] = "Fury", [73] = "Protection" })[id] or "Arms", "", 132347 end
_G.GetSpecializationInfoForClassID = function(_, i) return ({ 71, 72, 73 })[i], ({ "Arms", "Fury", "Protection" })[i], "", 1 end

-------------------------------------------------------------------------------
-- Items: a tiny fake item database
-- equipLoc, classID, subClassID, icon, name
-------------------------------------------------------------------------------
local ITEMS = {
    [1001] = { "INVTYPE_HEAD", 4, 4, 1, "Crown of Testing" },
    [1002] = { "INVTYPE_TRINKET", 4, 0, 1, "Trinket of Testing" },
    [1003] = { "INVTYPE_2HWEAPON", 2, 8, 1, "Big Sword" },
    [1004] = { "INVTYPE_WEAPON", 2, 7, 1, "Small Sword" },
    [1005] = { "INVTYPE_FINGER", 4, 0, 1, "Ring of Testing", { CRIT = 50, VERS = 50 } },
    [1009] = { "INVTYPE_FINGER", 4, 0, 1, "Ring of Haste", { HASTE = 60, MASTERY = 40, PRIMARY = 100 } },
    [1006] = { "INVTYPE_SHIELD", 4, 6, 1, "Shield of Testing" },
    [1007] = { "INVTYPE_CLOAK", 4, 1, 1, "Cloak of Testing" },
    [1008] = { "INVTYPE_CHEST", 4, 4, 1, "Chest of Testing", { HASTE = 70, MASTERY = 50 } },
    [2001] = { nil, 12, 0, 1, "Quest Thing" },
    [1010] = { "", 15, 0, 1, "Legguard Token", nil, "LEGSSLOT" }, -- tier token: not equippable, the journal names its slot
    [270912] = { "", 15, 0, 1, "Venomcast Idol" }, -- a real one: no slot named, the season table knows it
    [270909] = { "", 15, 0, 1, "Slumbering Coil Curio" }, -- traded for any set slot
    -- the class set from the journal's Class Sets tab
    [7001] = { "INVTYPE_HEAD", 4, 3, 1, "Venom Hood", { CRIT = 60, HASTE = 40 } },
    [7003] = { "INVTYPE_SHOULDER", 4, 3, 1, "Venom Mantle", { HASTE = 60, VERS = 40 } },
    [7005] = { "INVTYPE_CHEST", 4, 3, 1, "Venom Hauberk", { HASTE = 70, MASTERY = 30 } },
    [7010] = { "INVTYPE_HAND", 4, 3, 1, "Venom Grips", { CRIT = 50, VERS = 50 } },
    [7007] = { "INVTYPE_LEGS", 4, 3, 1, "Venom Legguards", { MASTERY = 60, HASTE = 40 } },
    -- the PvP set: eight pieces at a higher base level, not the tier set
    [7101] = { "INVTYPE_HEAD", 4, 3, 1, "Warmonger's Helm" }, [7103] = { "INVTYPE_SHOULDER", 4, 3, 1, "Warmonger's Epaulets" },
    [7105] = { "INVTYPE_CHEST", 4, 3, 1, "Warmonger's Chestguard" }, [7110] = { "INVTYPE_HAND", 4, 3, 1, "Warmonger's Grips" },
    [7107] = { "INVTYPE_LEGS", 4, 3, 1, "Warmonger's Leggings" }, [7109] = { "INVTYPE_WRIST", 4, 3, 1, "Warmonger's Armguards" },
    [7106] = { "INVTYPE_WAIST", 4, 3, 1, "Warmonger's Cinch" }, [7108] = { "INVTYPE_FEET", 4, 3, 1, "Warmonger's Greaves" },
    -- equipped
    [5001] = { "INVTYPE_HEAD", 4, 4, 1, "Old Helm", { HASTE = 80, MASTERY = 40 } },
    [5013] = { "INVTYPE_TRINKET", 4, 0, 1, "Trinket A" },
    [5014] = { "INVTYPE_TRINKET", 4, 0, 1, "Trinket B" },
    [5016] = { "INVTYPE_2HWEAPON", 2, 8, 1, "Equipped 2H" },
    [5017] = { "INVTYPE_2HWEAPON", 2, 8, 1, "Equipped 2H OH" },
    [5011] = { "INVTYPE_FINGER", 4, 0, 1, "Ring A", { HASTE = 60, CRIT = 30 } },
    [5012] = { "INVTYPE_FINGER", 4, 0, 1, "Ring B", { MASTERY = 50, VERS = 20, PRIMARY = 90 } },
    [5015] = { "INVTYPE_CLOAK", 4, 1, 1, "Old Cloak" },
    [5005] = { "INVTYPE_CHEST", 4, 4, 1, "Old Chest", { HASTE = 20, MASTERY = 20 } },
}
local function Link(id) return string.format("|cffa335ee|Hitem:%d::::::::80:72::::::|h[%s]|h|r", id, ITEMS[id][5]) end
_G.BAGS = {} -- itemID -> count in bags (C_Item.GetItemCount)

-- Fake upgrade-track bonus IDs, sequential per (track, step):
-- Adventurer 20001-20006, Veteran 20007-20012, Champion 20013-20018, Hero 20019-20024, Myth 20025-20030
local TRACKS = { "Adventurer", "Veteran", "Champion", "Hero", "Myth" }
local BASES = { 266, 279, 292, 305, 318 }
local OFFS = { 0, 3, 6, 10, 13, 16 }
local function BonusFor(track, step) return 20000 + (track - 1) * 6 + step end
local function BonusInfo(b)
    if not b or b < 20001 or b > 20030 then return nil end
    local idx = b - 20001
    local t, st = math.floor(idx / 6) + 1, idx % 6 + 1
    return TRACKS[t], st, BASES[t] + OFFS[st], BASES[t] + 16
end
local function LinkWithBonus(id, bonus) return string.format("|cffa335ee|Hitem:%d::::::::80:72:::1:%d|h[%s]|h|r", id, bonus, ITEMS[id][5]) end
local function BonusesOfLink(link)
    local body = tostring(link):match("(item:[%-%d:]*)")
    if not body then return {} end
    local f = {}
    for x in (body .. ":"):gmatch("([^:]*):") do f[#f + 1] = x end
    local n = tonumber(f[14]) or 0
    local ids = {}
    for i = 1, n do ids[#ids + 1] = tonumber(f[14 + i]) end
    return ids, f
end
local function BonusOfLink(link)
    for _, b in ipairs(BonusesOfLink(link)) do if b >= 20001 and b <= 20030 then return b end end
    return nil
end
local function HasBonus(link, id) for _, b in ipairs(BonusesOfLink(link)) do if b == id then return true end end return false end
local function ContextOf(link) local _, f = BonusesOfLink(link) return f and f[13] or "" end
-- end-of-dungeon track/step per keystone level (Season 2)
local function EodBonus(level)
    if not level or level < 2 then return BonusFor(3, 1) end
    local map = { [2] = { 3, 2 }, [3] = { 3, 2 }, [4] = { 3, 3 }, [5] = { 3, 4 }, [6] = { 4, 1 }, [7] = { 4, 1 }, [8] = { 4, 2 }, [9] = { 4, 2 } }
    local ts = map[level] or { 4, 3 }
    return BonusFor(ts[1], ts[2])
end

_G.C_Item = {
    GetItemInfoInstant = function(idOrLink)
        local id = tonumber(idOrLink) or tonumber(tostring(idOrLink):match("item:(%d+)"))
        local it = ITEMS[id]
        if not it then return nil end
        return id, "Armor", "Plate", it[1], it[4], it[2], it[3]
    end,
    GetDetailedItemLevelInfo = function(link)
        local uid = tonumber(tostring(link):match("item:(%d+)"))
        if UNCACHED and UNCACHED[uid] then return nil end
        local _, _, ilvl = BonusInfo(BonusOfLink(link))
        if ilvl then return ilvl end -- a track bonus sets the level even with a context
        if ContextOf(link) == "23" then return 292 end
        local b2 = tonumber(tostring(link):match("item:%d+::::::::80:72:::1:(%d+)"))
        local id = tonumber(tostring(link):match("item:(%d+)"))
        return EQUIPPED_ILVL and EQUIPPED_ILVL[id] or 0
    end,
    GetItemInfo = function(idOrLink)
        local id = tonumber(idOrLink)
        local it = id and ITEMS[id]
        if it and id >= 7000 then return it[5], string.format("|cffa335ee|Hitem:%d::::::::80:72::::::|h[%s]|h|r", id, it[5]) end
        return nil
    end,
    IsItemDataCachedByID = function(id) return not (UNCACHED and UNCACHED[id]) end,
    RequestLoadItemDataByID = function(id) _G.REQUESTED_ITEMS = (REQUESTED_ITEMS or 0) + 1 end,
    GetItemCount = function(id) return BAGS[id] or 0 end,
    GetItemStats = function(link)
        local id = tonumber(tostring(link):match("item:(%d+)"))
        local st = ITEMS[id] and ITEMS[id][6]
        local out = {}
        if st then
            out.ITEM_MOD_CRIT_RATING_SHORT = st.CRIT
            out.ITEM_MOD_HASTE_RATING_SHORT = st.HASTE
            out.ITEM_MOD_MASTERY_RATING_SHORT = st.MASTERY
            out.ITEM_MOD_VERSATILITY = st.VERS
            out.ITEM_MOD_INTELLECT_SHORT = st.PRIMARY
        end
        return out
    end,
    GetItemUpgradeInfo = function(link)
        local track, st, _, maxIlvl = BonusInfo(BonusOfLink(link))
        if track then return { currentLevel = st, maxLevel = 6, maxItemLevel = maxIlvl, trackString = track } end
        local id = tonumber(tostring(link):match("item:(%d+)"))
        if id == 5011 then return { currentLevel = 3, maxLevel = 6, maxItemLevel = 334, trackString = "Myth" } end
        return nil
    end,
}

-- equipped gear: slot -> { itemID, ilvl, upgradeLine }
local EQUIPPED = {}
_G.EQUIPPED_ILVL = {}
local function Equip(slot, itemID, ilvl, upgradeLine)
    EQUIPPED[slot] = itemID and { itemID = itemID, ilvl = ilvl, line = upgradeLine } or nil
    if itemID then EQUIPPED_ILVL[itemID] = ilvl end
end
local TRACK_INDEX = { Adventurer = 1, Veteran = 2, Champion = 3, Hero = 4, Myth = 5 }
_G.GetInventoryItemLink = function(_, slot)
    local e = EQUIPPED[slot]
    if not e then return nil end
    local track, st = tostring(e.line or ""):match("Upgrade Level: (%a+) (%d+)/6")
    if track and TRACK_INDEX[track] then return LinkWithBonus(e.itemID, BonusFor(TRACK_INDEX[track], tonumber(st))) end
    return Link(e.itemID)
end
_G.GetInventoryItemTexture = function(_, slot) return EQUIPPED[slot] and 1 or nil end
_G.C_TooltipInfo = {
    GetInventoryItem = function(_, slot)
        local e = EQUIPPED[slot]
        if not e then return nil end
        local lines = { { leftText = ITEMS[e.itemID][5] }, { leftText = "Item Level " .. e.ilvl } }
        if e.line then table.insert(lines, { leftText = e.line }) end
        return { lines = lines }
    end,
    GetBagItem = function() return nil end,
    GetHyperlink = function(link)
        local track, st, ilvl = BonusInfo(BonusOfLink(link))
        -- the journal context keeps its own upgrade line (like the live client)
        if ContextOf(link) == "23" then track, st = "Champion", 1; ilvl = ilvl or 292 end
        if not track and HasBonus(link, 3524) then track, st, ilvl = "Champion", 1, 292 end
        if not track then return { lines = { { leftText = "Some Item" } } } end
        return { lines = { { leftText = "Some Item" }, { leftText = "Item Level " .. ilvl }, { leftText = string.format("Upgrade Level: %s %d/6", track, st) } } }
    end,
}
-- Nebulous Voidcache tooltips: what a bonus roll can still give (the pool)
_G.VOIDCACHE_TIPS = {
    [278289] = { "- |cffa335eeChest of Testing|r", "\226\128\147\194\160Venomcast Idol", "  -  Ring of Haste" }, -- the Twin Fangs: legs token rolled already, no Curio (en dash and no-break space too)
    [279623] = { "- Crown of Testing", "- Trinket of Testing" },                          -- Murder Row: the sword rolled already
    [279619] = { "Small Sword", "Shield of Testing" },                                    -- the Blinding Vale: no markers at all, only the header
}
_G.VOIDCACHE_LOADING = { [279619] = 2 }  -- two reads list nothing before the client has it
_G.VOIDCACHE_NEEDS_JOURNAL = { [278289] = 3002, [279623] = 1304 } -- listed only once the journal loot was asked for
_G.JOURNAL_TOUCHED = {}
-- a cache the client resolves later: every read gets a data instance id, the
-- list is there only on the read made after TOOLTIP_DATA_UPDATE for that id
_G.VOIDCACHE_ASYNC = { [279621] = { "- Kings' Ring" } }
_G.VOIDCACHE_INSTANCE, _G.VOIDCACHE_RESOLVED_FOR = 0, nil
C_TooltipInfo.GetItemByID = function(id, quality, context, level)
    _G.VOIDCACHE_READS = (VOIDCACHE_READS or 0) + 1
    _G.LAST_VOIDCACHE_ARGS = { id, context, level }
    local need = VOIDCACHE_NEEDS_JOURNAL[id]
    if need and not JOURNAL_TOUCHED[need] then return { lines = { { leftText = "Nebulous Voidcache" }, { leftText = "Binds when picked up" } } } end
    local left = VOIDCACHE_LOADING[id]
    if left and left > 0 then
        VOIDCACHE_LOADING[id] = left - 1
        return { lines = { { leftText = "Nebulous Voidcache" } } }
    end
    local items = VOIDCACHE_TIPS[id]
    if VOIDCACHE_ASYNC[id] then
        if VOIDCACHE_RESOLVED_FOR == id then
            VOIDCACHE_RESOLVED_FOR = nil
            items = VOIDCACHE_ASYNC[id]
        else
            VOIDCACHE_INSTANCE = VOIDCACHE_INSTANCE + 1
            _G.LAST_VOIDCACHE_INSTANCE = VOIDCACHE_INSTANCE
            return { dataInstanceID = VOIDCACHE_INSTANCE, lines = { { leftText = "Nebulous Voidcache: Kings' Rest" }, { leftText = "Binds when picked up" } } }
        end
    end
    if not items then return nil end
    local lines = { { leftText = "Nebulous Voidcache: Somewhere" }, { leftText = "Item Level 318" }, { leftText = "Binds when picked up" },
        { leftText = "Use: Transmute a Nebulous Voidcore into a piece of equipment for your Loot Specialization." },
        { leftText = " " }, { leftText = "Contains one of the following items:" } }
    for _, t in ipairs(items) do lines[#lines + 1] = { leftText = t } end
    return { lines = lines }
end
_G.C_CurrencyInfo = { GetCurrencyInfo = function(id) if id == 3418 then return { quantity = 2 } elseif id == 3465 then return { quantity = 1 } end return nil end }
_G.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemLink = function() return nil end }

-- Free upgrade levels (Midnight): WATERMARKS[redundancySlot] = ilvl; nil = the client reports nothing
_G.WATERMARKS = nil
local REDUNDANCY_OF = { INVTYPE_HEAD = 0, INVTYPE_NECK = 1, INVTYPE_SHOULDER = 2, INVTYPE_CHEST = 3, INVTYPE_WAIST = 4, INVTYPE_LEGS = 5,
    INVTYPE_FEET = 6, INVTYPE_WRIST = 7, INVTYPE_HAND = 8, INVTYPE_FINGER = 9, INVTYPE_TRINKET = 10, INVTYPE_CLOAK = 11,
    INVTYPE_2HWEAPON = 12, INVTYPE_WEAPONMAINHAND = 13, INVTYPE_WEAPON = 14, INVTYPE_SHIELD = 16 }
_G.C_ItemUpgrade = {
    GetHighWatermarkForSlot = function(r)
        if WATERMARKS and WATERMARKS[r] then return WATERMARKS[r], WATERMARKS[r] end
    end,
    GetHighWatermarkSlotForItem = function(link)
        local id = tonumber(tostring(link):match("item:(%d+)"))
        return ITEMS[id] and REDUNDANCY_OF[ITEMS[id][1]] or nil
    end,
}

-- season / challenge mode
local MAPS = {
    [587] = { "Murder Row", 2813 },
    [584] = { "The Blinding Vale", 2859 },
    [249] = { "Kings' Rest", 1762 },
}
-- Mythic+ rating: season bests per map (587 timed +10 in 1500 s, 584 depleted +12, 249 never run)
_G.RATINGS = {
    [587] = { intime = { level = 10, durationSec = 1500, dungeonScore = 326.25, completionDate = 0 } },
    [584] = { overtime = { level = 12, durationSec = 2100, dungeonScore = 300, completionDate = 0 } },
}
_G.OVERALL_OVERRIDE = nil
local function OverallScore()
    if OVERALL_OVERRIDE then return OVERALL_OVERRIDE end
    local sum = 0
    for _, r in pairs(RATINGS) do
        local best = 0
        if r.intime then best = math.max(best, r.intime.dungeonScore) end
        if r.overtime then best = math.max(best, r.overtime.dungeonScore) end
        sum = sum + best
    end
    return sum
end
_G.C_ChallengeMode = {
    GetMapTable = function() local t = {} for id in pairs(MAPS) do table.insert(t, id) end table.sort(t) return t end,
    GetMapUIInfo = function(id) local m = MAPS[id]; if m then return m[1], id, 1800, 1, 1, m[2] end end,
    GetOverallDungeonScore = OverallScore,
    GetDungeonScoreRarityColor = function() return { r = 1, g = 0.5, b = 0 } end,
    GetKeystoneLevelRarityColor = function() return { r = 0.64, g = 0.21, b = 0.93 } end,
}
_G.C_PlayerInfo = {
    GetPlayerMythicPlusRatingSummary = function() return { currentSeasonScore = OverallScore(), runs = {} } end,
}
-- Season 2 curve
local EOD = { [2] = 295, [3] = 295, [4] = 298, [5] = 302, [6] = 305, [7] = 305, [8] = 308, [9] = 308, [10] = 311 }
local VAULT = { [2] = 305, [3] = 305, [4] = 308, [5] = 308, [6] = 311, [7] = 315, [8] = 315, [9] = 315, [10] = 318 }
_G.API_FLAT = false -- simulate reward data not loaded yet
_G.C_MythicPlus = {
    GetCurrentSeason = function() return 30 end,
    GetRewardLevelForDifficultyLevel = function(k)
        if API_FLAT then return 302, 292 end
        return VAULT[k] or 318, EOD[k] or 311
    end,
    GetRewardLevelFromKeystoneLevel = function(k) if API_FLAT then return 302 end return VAULT[k] or 318 end,
    RequestMapInfo = function() _G.REQUESTED_MAPINFO = (REQUESTED_MAPINFO or 0) + 1 end,
    RequestCurrentAffixes = function() end,
    GetSeasonBestForMap = function(id)
        local r = RATINGS[id]
        if not r then return nil, nil end
        return r.intime, r.overtime
    end,
    RequestRewards = function() _G.REQUESTED_REWARDS = (REQUESTED_REWARDS or 0) + 1 end,
}

-- encounter journal
local JOURNAL = {
    [1] = { { id = 100, name = "Old Dungeon", map = 999 }, { id = 1304, name = "Murder Row", map = 2813 } },
    [2] = {
        { id = 1304, name = "Murder Row", map = 2813 },
        { id = 1309, name = "The Blinding Vale", map = 2859 },
        { id = 1041, name = "Kings' Rest", map = 1762 },
    },
}
local LOOT = {
    [1304] = { 1001, 1002, 1003, 2001 },
    [1309] = { 1004, 1005, 1006, 1007 },
    [1041] = { 1008, 1005 },
}
-- raids (tier 2): a multi-boss raid and the one-boss lair, which has a
-- "World" difficulty (205) in place of LFR. Later bosses drop a step higher.
local RAIDS = {
    { id = 1500, name = "Serpent Hollow", diffs = { [17] = true, [14] = true, [15] = true, [16] = true },
      bosses = { { id = 3001, name = "Nek'zali", step = 1 }, { id = 3002, name = "The Twin Fangs", step = 2 } } },
    { id = 1501, name = "The Tidebound Grotto", diffs = { [205] = true, [14] = true, [15] = true, [16] = true },
      bosses = { { id = 3010, name = "Nymrissa Wavecaller", step = 1 } } },
    -- the season's world bosses: the journal calls Normal valid for them
    -- (as seen in 12.1) and shows no difficulty selector
    { id = 1502, name = "Midnight", diffs = { [205] = true, [14] = true }, display = false,
      bosses = { { id = 3020, name = "Lu'ashal", step = 1 } } },
}
local RAID_LOOT = { [3001] = { 1001, 1005 }, [3002] = { 1008, 1009, 1010, 270912, 270909 }, [3010] = { 1003, 1002 }, [3020] = { 1001 } }
local RAID_TRACK = { [17] = 2, [205] = 2, [14] = 3, [15] = 4, [16] = 5 } -- difficulty -> track index
local function RaidByID(id) for _, r in ipairs(RAIDS) do if r.id == id then return r end end end
local function BossByID(id) for _, r in ipairs(RAIDS) do for _, b in ipairs(r.bosses) do if b.id == id then return b end end end end
local ej = { tier = 1, instance = nil, encounter = nil, diff = 23, classID = 0, specID = 0, preview = 0 }
local lootDelayed = { [1309] = 1 } -- first read has no links
_G.C_LootJournal = {
    GetClassAndSpecFilters = function() return 0, 0 end,
    SetClassAndSpecFilters = function(c, s) _G.LJ_FILTER = { c, s } end,
    GetFilteredItemSets = function() return { { setID = 900, name = "Old Set", itemLevel = 250 }, { setID = 901, name = "Venom Set", itemLevel = 279 },
        { setID = 902, name = "Venomous Warmonger's Links", itemLevel = 300 } } end,
    GetItemSetItems = function(setID)
        if setID == 902 then return { { itemID = 7101 }, { itemID = 7103 }, { itemID = 7105 }, { itemID = 7110 }, { itemID = 7107 }, { itemID = 7109 }, { itemID = 7106 }, { itemID = 7108 } } end
        if setID ~= 901 then return {} end
        return { { itemID = 7001 }, { itemID = 7003 }, { itemID = 7005 }, { itemID = 7010 }, { itemID = 7007 } }
    end,
}
_G.EJ_GetNumTiers = function() return 2 end
_G.EJ_GetCurrentTier = function() return ej.tier end
_G.EJ_SelectTier = function(t) ej.tier = t end
_G.EJ_GetInstanceByIndex = function(i, isRaid)
    if isRaid then
        if ej.tier ~= 2 then return nil end
        local r = RAIDS[i]
        if not r then return nil end
        -- 12.1 order: the link precedes shouldDisplayDifficulty, then isRaid
        return r.id, r.name, "", 1, 1, 1, 1, "[" .. r.name .. "]", r.display ~= false, true, 0
    end
    local inst = JOURNAL[ej.tier][i]
    if not inst then return nil end
    return inst.id, inst.name, "", 1, 1, 1, 1, 0, "", true, inst.map
end
_G.EJ_SelectInstance = function(id) ej.instance = id; ej.encounter = nil end
_G.EJ_SelectEncounter = function(id) ej.encounter = id end
_G.EJ_GetEncounterInfoByIndex = function(i, instanceID)
    local r = RaidByID(instanceID)
    local b = r and r.bosses[i]
    if not b then return nil end
    return b.name, "", b.id, 0, "", instanceID, 0, instanceID
end
_G.EJ_GetCreatureInfo = function(_, encounterID) return 1, "Boss", "", 0, 4242 end
_G.EJ_SetDifficulty = function(d) ej.diff = d end
_G.EJ_GetDifficulty = function() return ej.diff end
_G.EJ_IsValidInstanceDifficulty = function(d)
    local r = RaidByID(ej.instance)
    if r then return r.diffs[d] == true end
    if d == 8 then return ej.tier == 2 end
    return d == 23
end
_G.EJ_SetLootFilter = function(c, s) ej.classID, ej.specID = c, s end
_G.EJ_GetLootFilter = function() return ej.classID, ej.specID end
_G.EJ_GetNumLoot = function()
    JOURNAL_TOUCHED[ej.encounter or ej.instance] = ej.diff
    if ej.encounter then return RAID_LOOT[ej.encounter] and #RAID_LOOT[ej.encounter] or 0 end
    return LOOT[ej.instance] and #LOOT[ej.instance] or 0
end
_G.C_EncounterJournal = {
    SetSlotFilter = function() end,
    SetPreviewMythicPlusLevel = function(level) ej.preview = level end,
    GetInstanceForGameMap = function(mapID)
        for _, list in pairs(JOURNAL) do
            for _, inst in ipairs(list) do if inst.map == mapID then return inst.id end end
        end
        return nil
    end,
    GetLootInfoByIndex = function(i)
        if ej.encounter then
            local id = RAID_LOOT[ej.encounter] and RAID_LOOT[ej.encounter][i]
            if not id then return nil end
            local boss = BossByID(ej.encounter)
            local link = LinkWithBonus(id, BonusFor(RAID_TRACK[ej.diff] or 4, boss.step))
            return { itemID = id, encounterID = ej.encounter, name = ITEMS[id][5], link = link, icon = 1,
                slot = ITEMS[id][7] and _G[ITEMS[id][7]] or "Slot", armorType = "Plate" }
        end
        local id = LOOT[ej.instance] and LOOT[ej.instance][i]
        if not id then return nil end
        local delayed = lootDelayed[ej.instance]
        if delayed and delayed > 0 then
            lootDelayed[ej.instance] = delayed - 1
            return { itemID = id, encounterID = 1 }
        end
        local link
        if ej.instance == 1041 or ej.diff ~= 8 then
            link = string.format("|cffa335ee|Hitem:%d::::::::80:72::23:1:3524|h[%s]|h|r", id, ITEMS[id][5])
        else
            link = LinkWithBonus(id, EodBonus(ej.preview))
        end
        return { itemID = id, encounterID = 1, name = ITEMS[id][5], link = link, icon = 1, slot = "Slot", armorType = "Plate" }
    end,
}

-- LFG
_G.C_LFGList = {
    GetActivityInfoTable = function(id)
        if id == 9999 then return { fullName = "The Blinding Vale (Mythic Keystone)", shortName = "Blinding Vale", groupFinderActivityGroupID = 0, isMythicPlusActivity = true, mapID = 0 } end
        return nil
    end,
    GetActivityGroupInfo = function() return nil end,
    GetSearchResultInfo = function(resultID)
        if resultID == 1 then return { activityIDs = { 1749 }, leaderName = "x", name = "+13 chill run" } end
        if resultID == 2 then return { activityIDs = { 9999 }, leaderName = "y", name = "LF healer" } end
        if resultID == 3 then return { activityIDs = { 1699 }, leaderName = "z", name = "11 key, timed pls" } end
        return nil
    end,
}
_G.PVEFrame = NewWidget("Frame", "PVEFrame")
_G.LFGListFrame = NewWidget("Frame", "LFGListFrame")
LFGListFrame.SearchPanel = NewWidget("Frame")
LFGListFrame.SearchPanel.ScrollBox = NewWidget("Frame")

-------------------------------------------------------------------------------
-- Load the addon
-------------------------------------------------------------------------------
local ns = {}
local files = {}
for line in io.lines(ADDON_DIR .. "SlotFiller.toc") do
    if line:match("^[%w_]+%.lua$") then files[#files + 1] = line end
end
for _, f in ipairs(files) do
    local chunk, err = loadfile(ADDON_DIR .. f)
    assert(chunk, err)
    chunk("SlotFiller", ns)
end
print("loaded " .. #files .. " files")

-- Equip: Fury warrior with two 2H (Titan's Grip), Season 2 numbers
Equip(1, 5001, 302, "Upgrade Level: Champion 4/6")      -- head: Champion (to 308) -> +10 drop 311 Hero is a track upgrade
Equip(13, 5013, 321, "Upgrade Level: Hero 6/6")          -- trinket A maxed Hero
Equip(14, 5014, 308, "Upgrade Level: Hero 2/6")          -- trinket B Hero 2/6 (to 321) -> drop 311 is ilvl-only; Voidcore Myth is a track upgrade
Equip(16, 5016, 311, "Upgrade Level: Hero 3/6")          -- MH Hero 3/6
Equip(17, 5017, 295, "Upgrade Level: Champion 2/6")      -- OH Champion 2/6 -> 2H drop is a track upgrade via OH
Equip(11, 5011, 324, "Upgrade Level: Myth 3/6")          -- ring A Myth (to 334)
Equip(12, 5012, 295, "Upgrade Level: Veteran 6/6")       -- ring B Veteran maxed -> track upgrade
Equip(15, 5015, 308, "Upgrade Level: Champion 6/6")      -- cloak Champion maxed -> Hero 3/6 drop is a track upgrade (+3)
Equip(5, 5005, 311, "Upgrade Level: Hero 3/6")           -- chest Hero 3/6 -> drop 311 = no upgrade; Voidcore Myth = track upgrade

-- Fire lifecycle
local ev = ns.eventFrame._scripts.OnEvent
ev(ns.eventFrame, "ADDON_LOADED", "SlotFiller")
check(ns:TrackKeyForName("Myth") == "Myth", "English track names are their own keys")
check(ns.db ~= nil and ns.cdb ~= nil, "saved variables initialised")
check(#ns.tracks == 5, "track table built from season defaults (" .. #ns.tracks .. ")")
check(ns.trackByKey.Champion.min == 292 and ns.trackByKey.Champion.max == 308, "Champion 292-308")
check(ns.trackByKey.Hero.ilvls[3] == 311 and ns.trackByKey.Myth.max == 334, "Hero 3/6 = 311, Myth 6/6 = 334")
ev(ns.eventFrame, "PLAYER_LOGIN")
RunTimers()
check(#ns.dungeons == 3, "dungeon pool built from C_ChallengeMode (" .. #ns.dungeons .. ")")
check(ns.dungeonByMapID[587] and ns.dungeonByMapID[587].instanceMapID == 2813, "instance map id from GetMapUIInfo")
check((REQUESTED_REWARDS or 0) > 0, "RequestRewards called at login")

-- gear
ns:ScanGear()
check(ns.gear[1].track and ns.gear[1].track.key == "Champion", "head resolved to Champion track")
check(ns.gear[1].potential == 308, "head potential = Champion max 308 (" .. tostring(ns.gear[1].potential) .. ")")
check(ns.gear[14].potential == 321, "trinket B potential = Hero max 321")
check(ns.gear[11].track and ns.gear[11].track.key == "Myth" and ns.gear[11].potential == 334, "ring A resolved to Myth (to 334) via C_Item.GetItemUpgradeInfo")
check(ns.gear[11].trackName == "Myth" and ns.gear[11].cur == 3, "direct upgrade API used before tooltip parsing")
check(ns:TrackDisplayName(ns.trackByKey.Hero) == "Hero" and ns:TrackDisplayName(ns.trackByKey.Myth) == "Myth", "track display names are correct")
check(ns.trackByLocalName["Champion"] ~= nil, "learned localized track name")

-- loot scan (async)
RunTimers()
ev(ns.eventFrame, "EJ_LOOT_DATA_RECIEVED")
RunTimers()
ev(ns.eventFrame, "EJ_LOOT_DATA_RECIEVED")
RunTimers()
check(ns.loot ~= nil, "loot scan finished and cached")
local mr = ns:GetDungeonLoot(587)
check(mr and #mr == 3, "Murder Row: 3 equippable items (quest item dropped) got " .. tostring(mr and #mr))
local bv = ns:GetDungeonLoot(584)
check(bv and #bv == 4, "Blinding Vale scanned after delayed loot data (" .. tostring(bv and #bv) .. ")")
check(ns.cdb.lootCache[30] and ns.cdb.lootCache[30][72], "cache keyed by season and spec")
check(ej.tier == 1, "journal tier restored after scan (" .. tostring(ej.tier) .. ")")
check(ns.dungeonByMapID[587].journalID == 1304, "journal instance via GetInstanceForGameMap")

-- raids: the season's raids and bosses, loot per difficulty
local raids = ns:GetRaids()
check(#raids == 2 and raids[1].name == "Serpent Hollow" and #raids[1].bosses == 2 and #raids[2].bosses == 1, "season raids and bosses read from the journal (" .. #raids .. ")")
check(raids[2].name == "The Tidebound Grotto", "the world-boss entry (no difficulty selector) is left out; the lair stays")
local nek, twin, nym = raids[1].bosses[1], raids[1].bosses[2], raids[2].bosses[1]
check(nek.loot.heroic and #nek.loot.heroic.items == 2 and nek.loot.lfr and nek.loot.normal and nek.loot.mythic, "boss loot scanned at every difficulty")
check(raids[2].difficulties.lfr == 205 and nym.loot.lfr and #nym.loot.lfr.items == 2, "the lair's World difficulty fills the LFR slot")
check(nek.portrait == 4242, "boss portrait kept for the row icon")
local tokenItem = twin.loot.heroic.items[3]
check(tokenItem and tokenItem.itemID == 1010 and tokenItem.token and tokenItem.equipLoc == "INVTYPE_LEGS", "a tier token is kept under the slot the journal names")
local idol = twin.loot.heroic.items[4]
check(idol and idol.itemID == 270912 and idol.token and idol.equipLoc == "INVTYPE_HAND", "the season's own tokens are known by id: Venomcast Idol is hands")
local curio = twin.loot.heroic.items[5]
check(curio and curio.itemID == 270909 and curio.token and curio.equipLoc == "TIER_ANY", "the Curio is a token for any set slot")
check(ns.loot.classSet and ns.loot.classSet.name == "Venom Set" and ns.loot.classSet.tier and ns.loot.classSet.pieces.INVTYPE_HAND.itemID == 7010,
    "the five-slot tier set is read from the Class Sets tab, not the higher-level eight-piece PvP set")
check(idol.piece and idol.piece.itemID == 7010 and idol.piece.name == "Venom Grips", "the hands token carries the class's hands piece")
check(curio.pieces and #curio.pieces == 5 and curio.pieces[1].itemID == 7001 and curio.pieces[5].itemID == 7007, "the Curio carries all five pieces")
check(ns.cdb.lootCache[30][72].raids == raids, "raids cached with the dungeons")
local hctx = ns:GetRaidContext("heroic", nek)
check(hctx.raid and hctx.ilvl == 305 and hctx.track.key == "Hero" and hctx.step == 1 and hctx.source == "journal", "Heroic boss drop: Hero 1/6 from the journal link")
check(hctx.voidcore and hctx.voidcore.ilvl == 318 and hctx.voidcore.track.key == "Myth" and hctx.voidcore.step == 1, "Heroic Voidcore roll: Myth 1/6")
check(ns:GetRaidContext("heroic", twin).ilvl == 308, "a later boss drops higher within the track (308 Hero 2/6)")
-- after a login the client may not hold the later boss's items yet (their
-- links answer nothing): the level remembered at scan time still stands,
-- the items are asked for once, and their arrival evaluates again
check(twin.loot.heroic.items[1].ilvl == 308, "each item's level is remembered at scan time")
_G.UNCACHED = { [1008] = true, [1009] = true, [1010] = true, [270912] = true, [270909] = true }
local itemsBefore = REQUESTED_ITEMS or 0
ns:Evaluate()
local rbCtx = ns.resultByEncounter[3002].ctx
check(rbCtx.ilvl == 308 and rbCtx.source == "journal", "uncached items: the later boss is still judged at 308 Hero 2/6 (" .. tostring(rbCtx.ilvl) .. " " .. tostring(rbCtx.source) .. ")")
local remembered = {}
for i, it in ipairs(twin.loot.heroic.items) do remembered[i] = it.ilvl; it.ilvl = nil end
ns:Evaluate()
rbCtx = ns.resultByEncounter[3002].ctx
check(rbCtx.ilvl == 305 and rbCtx.source == "track", "without a remembered level an unloaded link falls back to Hero 1/6")
for i, it in ipairs(twin.loot.heroic.items) do it.ilvl = remembered[i] end
check((REQUESTED_ITEMS or 0) == itemsBefore + 5 and ns.itemRequests[1008] == true, "each missing item is asked for once")
ns:Evaluate()
check((REQUESTED_ITEMS or 0) == itemsBefore + 5, "evaluating again asks for nothing")
_G.UNCACHED = nil
ns.eventFrame._scripts.OnEvent(ns.eventFrame, "ITEM_DATA_LOAD_RESULT", 1008, true)
ns.eventFrame._scripts.OnEvent(ns.eventFrame, "ITEM_DATA_LOAD_RESULT", 1009, true)
RunTimers()
check(ns.resultByEncounter[3002].ctx.ilvl == 308 and ns.resultByEncounter[3002].ctx.source == "journal", "when the items arrive the boss is judged at 308 Hero 2/6 again")
check(ns.itemRequests[1008] == false, "an answered item is not asked again")
local mctx = ns:GetRaidContext("mythic", nek)
check(mctx.ilvl == 318 and mctx.voidcore.ilvl == 334 and mctx.voidcore.potential == 334, "Mythic: Myth 1/6 drop, fully upgraded Voidcore roll")
local lctx = ns:GetRaidContext("lfr", nek)
check(lctx.ilvl == 279 and lctx.track.key == "Veteran" and lctx.voidcore.ilvl == 292 and lctx.voidcore.track.key == "Champion", "LFR: Veteran drop, Champion 1/6 roll")
check(ns:GetRaidContext("normal").ilvl == 292 and ns:GetRaidContext("normal").source == "track", "without a boss the track's first step stands in")
-- the season table ships the real raid's levels: by boss name, else by position
local va = { name = "The Venomous Abyss", bosses = {} }
local function VABoss(name, index) local b = { name = name, index = index, loot = {} }; va.bosses[#va.bosses + 1] = b; return b end
local nekReal, explorers, vashnik, ulatek, unknown = VABoss("Nek'zali the Soulcoiler", 1), VABoss("The Lost Explorers", 3), VABoss("Vashnik the Malignant", 4), VABoss("Ula'tek", 8), VABoss("Someone New", 5)
local hero, myth, vet = ns.trackByKey.Hero, ns.trackByKey.Myth, ns.trackByKey.Veteran
check(ns:ShippedBossLevel(va, nekReal, "heroic", hero) == 305 and ns:ShippedBossLevel(va, explorers, "heroic", hero) == 308, "shipped levels: Nek'zali Hero 1/6, the Lost Explorers Hero 2/6")
check(ns:ShippedBossLevel(va, vashnik, "mythic", myth) == 324 and ns:ShippedBossLevel(va, ulatek, "heroic", hero) == 315, "Vashnik Myth 3/6, Ula'tek Hero 4/6")
check(ns:ShippedBossLevel(va, ulatek, "mythic", myth) == 344, "the last two Mythic bosses leave the track at 344")
check(ns:ShippedBossLevel(va, unknown, "heroic", hero) == 311, "an unknown name falls back to its journal position (5th: Hero 3/6)")
check(ns:ShippedBossLevel({ name = "Tidebound Grotto" }, { name = "Nymrissa Wavecaller", index = 1 }, "lfr", vet) == 279, "the lair's World drop is Veteran 1/6")
check(ns:ShippedBossLevel(ns:GetRaids()[1], nek, "heroic", hero) == nil, "a raid the table does not know gets nothing shipped")
local uctx = ns:GetRaidContext("mythic", ulatek, va)
check(uctx.ilvl == 344 and uctx.source == "season" and uctx.voidcore.ilvl == 344 and uctx.potential == 344, "Ula'tek on Mythic: 344 from the season table, the roll no lower")
local ectx = ns:GetRaidContext("heroic", explorers, va)
check(ectx.ilvl == 308 and ectx.step == 2 and ectx.source == "season" and ectx.voidcore.ilvl == 318, "the Lost Explorers on Heroic: Hero 2/6 from the season table, Myth 1/6 roll")
check(ns.journalTier[1304] == 2, "instance mapped to its last (current season) tier")
check(ns.loot.dungeons[587].difficulty == 8, "Murder Row read at Mythic Keystone difficulty (" .. tostring(ns.loot.dungeons[587].difficulty) .. ")")

-- evaluation at +10
ns.db.targetKey = 10
ns:Evaluate()
local ctx = ns.dropCtx
check(ctx.ilvl == 311 and ctx.source == "api", "drop ilvl at +10 from API = 311")
check(ctx.track and ctx.track.key == "Hero" and ctx.step == 3 and ctx.potential == 321, "drop resolved as Hero 3/6 (to 321)")
check(ctx.voidcore and ctx.voidcore.ilvl == 318 and ctx.voidcore.track.key == "Myth" and ctx.voidcore.step == 1 and ctx.voidcore.potential == 334, "Voidcore at +10 = 318 Myth 1/6 (to 334)")
local r = ns:ResultForDungeon(ns.dungeonByMapID[587])
local byItem = {}
for _, e in ipairs(r.items) do byItem[e.item.itemID] = e end
check(byItem[1001].class == ns.UPGRADE_TRACK, "head drop vs Champion 4/6 = track upgrade")
check(byItem[1002].slotID == 14 and byItem[1002].class == ns.UPGRADE_ILVL, "trinket drop targets the weaker trinket and is an ilvl upgrade")
check(byItem[1002].voidcore and byItem[1002].voidcore.class == ns.UPGRADE_TRACK, "same trinket from a Voidcore roll (Myth) is a track upgrade")
check(byItem[1003].slotID == 17 and byItem[1003].class == ns.UPGRADE_TRACK, "2H drop with Titan's Grip targets the weaker hand (OH) as track upgrade")
check(r.upgrades == 3 and r.total == 3, "Murder Row: 3/3 drop upgrades")

local r2 = ns:ResultForDungeon(ns.dungeonByMapID[584])
byItem = {}
for _, e in ipairs(r2.items) do byItem[e.item.itemID] = e end
check(byItem[1004].slotID == 16, "1H drop while wielding two 2H targets MH")
check(byItem[1004].class == ns.UPGRADE_NONE and byItem[1004].voidcore.class == ns.UPGRADE_TRACK, "1H drop: no upgrade over Hero 3/6, but Myth roll is")
check(byItem[1005].slotID == 12 and byItem[1005].class == ns.UPGRADE_TRACK, "ring drop targets Veteran ring as track upgrade")
check(byItem[1006].class == ns.UPGRADE_NONE and byItem[1006].reason == "off hand holds a weapon", "shield vs equipped 2H off-hand: not an upgrade")
check(byItem[1007].class == ns.UPGRADE_TRACK and byItem[1007].gain == 3, "cloak: Champion 6/6 (308) -> Hero 3/6 (311) is a track upgrade with +3")

local r3 = ns:ResultForDungeon(ns.dungeonByMapID[249])
byItem = {}
for _, e in ipairs(r3.items) do byItem[e.item.itemID] = e end
check(byItem[1008].class == ns.UPGRADE_NONE and byItem[1008].voidcore.class == ns.UPGRADE_TRACK, "chest Hero 3/6 vs Hero 3/6 drop = none; Voidcore Myth = track upgrade")
check(byItem[1005].slotID == 12, "ring in second dungeon still targets Veteran ring")
check(r3.chance == 0.5, "Kings' Rest: 50% drop chance")

check(ns.results[1].upgrades >= ns.results[2].upgrades, "results sorted by drop upgrades")
ns:SetItemState(1005, "want")
ns.db.sortMode = "wanted"
ns:Evaluate()
check(ns.results[1].wanted == 1 and ns.results[#ns.results].wanted == 0, "results sorted by wanted items (" .. ns.results[1].dungeon.name .. ")")
check(ns:ResultForDungeon(ns.dungeonByMapID[584]).wantedItems[1].item.itemID == 1005, "wanted item listed for its dungeon")
ns:SetItemState(1005, nil)
ns.db.sortMode = "upgrades"

-- raid bosses at the Raid tab's difficulty (Heroic by default)
ns:Evaluate()
check(#ns.raidResults == 2 and #ns.raidResults[1].bosses == 2, "bosses evaluated per raid")
local rb = ns.resultByEncounter[3002]
check(rb and rb.sourceName == "The Twin Fangs" and rb.ctx.raid and rb.ctx.difficultyName == "Heroic" and rb.ctx.ilvl == 308, "boss result carries its name and Heroic context")
byItem = {}
for _, e in ipairs(rb.items) do byItem[e.item.itemID] = e end
check(byItem[1008].class == ns.UPGRADE_NONE and byItem[1008].voidcore.class == ns.UPGRADE_TRACK, "Heroic chest (308) is no drop upgrade over Hero 3/6, but the Myth 1/6 roll is")
check(byItem[1009].slotID == 12 and byItem[1009].class == ns.UPGRADE_TRACK, "Heroic ring vs the Veteran ring is a track upgrade")
local rn = ns.resultByEncounter[3001]
byItem = {}
for _, e in ipairs(rn.items) do byItem[e.item.itemID] = e end
check(byItem[1001].class == ns.UPGRADE_TRACK and rn.upgrades == 2, "Nek'zali on Heroic: head and ring are track upgrades")
ns:SetRaidDifficulty("mythic")
RunTimers()
rb = ns.resultByEncounter[3002]
byItem = {}
for _, e in ipairs(rb.items) do byItem[e.item.itemID] = e end
check(rb.ctx.ilvl == 321 and byItem[1008].class == ns.UPGRADE_TRACK, "on Mythic the later boss drops Myth 2/6 (321): a track upgrade for the chest")
ns:SetRaidDifficulty("lfr")
RunTimers()
rn = ns.resultByEncounter[3001]
local lfrRing
for _, e in ipairs(rn.items) do if e.item.itemID == 1005 then lfrRing = e end end
check(rn.ctx.ilvl == 279 and rn.upgrades == 0 and lfrRing.voidcore.class == ns.UPGRADE_TRACK, "on LFR nothing is a drop upgrade; the Champion roll would still help the Veteran ring")
ns:SetRaidDifficulty("heroic")
RunTimers()

-- the Gear tab draws from dungeons, raids or both
ns.db.gearSource = "raid"
local sm = ns:SlotSummary()
check(sm[1].count == 2 and sm[1].sources["b3001"] and sm[1].sources["b3002"] and not sm[1].sources["d587"], "Gear tab from raids only: head upgrades from Nek'zali and the Curio's hood")
ns.db.gearSource = "mplus"
sm = ns:SlotSummary()
check(sm[1].count == 1 and sm[1].sources["d587"] and not sm[1].sources["b3001"], "from dungeons only: from Murder Row")
ns.db.gearSource = "both"
sm = ns:SlotSummary()
check(sm[1].count == 3, "both: three head upgrades")

-- Voidcore targets: a second flag per item, never mixed into the counts
ns:SetVoidcoreTarget(1008, true)
RunTimers()
check(ns:IsVoidcoreTarget(1008) and ns:VoidcoreItemIDs()[1] == 1008, "chest marked as a Voidcore target")
r3 = ns:ResultForDungeon(ns.dungeonByMapID[249])
check(r3.voidcore == 1 and r3.voidcoreItems[1].item.itemID == 1008 and r3.upgrades == 1, "Kings' Rest lists it as a Voidcore target without counting it as a drop upgrade")
check(ns.resultByEncounter[3002].voidcore == 1, "and so does the boss that drops it")
local tokenEval, idolEval, curioEval
for _, e in ipairs(ns.resultByEncounter[3002].items) do
    if e.token and e.token.itemID == 1010 then tokenEval = e end
    if e.token and e.token.itemID == 270912 then idolEval = e end
    if e.token and e.token.itemID == 270909 then curioEval = e end
end
check(tokenEval and tokenEval.item.itemID == 7007 and tokenEval.slotID == 7 and tokenEval.class == ns.UPGRADE_TRACK and tokenEval.reason == "empty slot",
    "the legs token is judged as the class's legguards: a track upgrade for the empty slot")
check(idolEval and idolEval.item.itemID == 7010 and idolEval.slotID == 10 and idolEval.stats and idolEval.stats.CRIT == 50, "the hands token is judged as the grips, stats and all")
local tokenLink, tokenKind = ns:LinkForContext(curioEval.token, ns.resultByEncounter[3002].ctx)
check(tokenLink == curioEval.token.link and tokenKind == "base", "a token's own link is shown, nothing rewritten")
check(curioEval and curioEval.pieces and #curioEval.pieces == 5 and curioEval.item.itemID == 7003 and curioEval.slotID == 3 and curioEval.reason == "empty slot",
    "the Curio stands as its best piece: the mantle for the empty shoulders")
check(curioEval.pieces[1].item.itemID == 7001 and curioEval.pieces[1].slotID == 1 and curioEval.pieces[1].class == ns.UPGRADE_TRACK and not curioEval.pieces[1].pieces,
    "each of its pieces is judged for its own slot")
check(ns.resultByEncounter[3002].upgrades == 4, "the Curio counts once in the boss's drops (" .. ns.resultByEncounter[3002].upgrades .. ")")
-- the omni token cannot be bonus rolled; slot tokens can
check(curio.noRoll and curio.pieces[1].noRoll and not idol.noRoll and not idol.piece.noRoll, "the Curio and its pieces are marked as not rollable, slot tokens are not")
check(curioEval.voidcore == nil and curioEval.pieces[1].voidcore == nil and idolEval.voidcore and idolEval.voidcore.class == ns.UPGRADE_TRACK,
    "no roll verdict for the Curio's pieces; the hands token's grips roll as Myth 1/6")
ns:SetVoidcoreTarget(7003, true)
ns:Evaluate()
check(ns.resultByEncounter[3002].voidcore == 1 and ns:IsVoidcoreTarget(7003), "a Curio piece marked as a target is not counted for the boss")
ns:SetVoidcoreTarget(7003, false)
ns:Evaluate()
sm = ns:SlotSummary()
check(sm[5].voidcore[1] and sm[5].voidcore[1].source == "Kings' Rest" and sm[5].count == 0, "slot summary lists the Voidcore target, count unchanged")
ns:SetItemState(1008, "exclude")
check(not ns:IsVoidcoreTarget(1008), "excluding an item drops it as a Voidcore target")
ns:SetVoidcoreTarget(1008, true)
check(ns:GetItemState(1008) == nil, "marking it again lifts the exclusion")
check(ns:ExportWanted() == "SF2:72::1008", "export carries Voidcore targets (" .. ns:ExportWanted() .. ")")
ns:SetVoidcoreTarget(1008, false)
local added = ns:ImportWanted("SF2:72:1005:1008")
check(added == 2 and ns:GetItemState(1005) == "want" and ns:IsVoidcoreTarget(1008), "import restores both lists")
ns:SetItemState(1005, nil); ns:SetVoidcoreTarget(1008, false)
RunTimers()

-- countIlvlUpgrades off
ns.db.countIlvlUpgrades = false
ns:Evaluate()
r = ns:ResultForDungeon(ns.dungeonByMapID[587])
check(r.upgrades == 2, "ilvl-only upgrades excluded when disabled (" .. r.upgrades .. ")")
ns.db.countIlvlUpgrades = true

-- Match level: drops judged as upgraded free to the slot's level. Until the
-- client reports its watermarks, the weaker candidate slot's own level stands in.
ns:SetMatchLevel(true)
RunTimers()
check(ns.db.matchLevel and ns.watermarkSource == "gear", "Match level on; nothing from the client yet, equipped levels stand in")
ns:SetTargetKey(8); RunTimers()
check(ns.dropCtx.ilvl == 308 and ns.dropCtx.track.key == "Hero" and ns.dropCtx.step == 2, "+8 drop = Hero 2/6 (308)")
r3 = ns:ResultForDungeon(ns.dungeonByMapID[249])
byItem = {}
for _, e in ipairs(r3.items) do byItem[e.item.itemID] = e end
local m = byItem[1008].matched
check(m and m.ilvl == 311 and m.step == 3 and m.track.key == "Hero" and byItem[1008].freeLevel == 311, "chest drop at +8 is judged at the chest's own 311 (Hero 3/6)")
check(byItem[1008].class == ns.UPGRADE_STAT and byItem[1008].gain == 0 and byItem[1008].fit > byItem[1008].equippedFit, "same level, better stats: a stat upgrade")
check(ns:CountsAsUpgrade(byItem[1008]) and r3.upgrades == 2 and r3.trackUpgrades == 1, "stat upgrades count in Drops, not as track upgrades")
check(ns.dropCtx.voidcore.ilvl == 315 and byItem[1008].voidcore.class == ns.UPGRADE_ILVL and byItem[1008].voidcore.gain == 4 and not byItem[1008].voidcoreMatched, "the +8 roll (315 Hero 4/6) is above the slot level and stays an ilvl upgrade")
r = ns:ResultForDungeon(ns.dungeonByMapID[587])
byItem = {}
for _, e in ipairs(r.items) do byItem[e.item.itemID] = e end
check(byItem[1002].freeLevel == 308 and not byItem[1002].matched and byItem[1002].class == ns.UPGRADE_NONE, "trinket pair: the weaker trinket's 308 is the free level; a 308 drop with no better stats is nothing")
ns.db.countIlvlUpgrades = false
ns:Evaluate()
r3 = ns:ResultForDungeon(ns.dungeonByMapID[249])
check(r3.upgrades == 1, "stat upgrades follow the immediate-upgrade setting")
ns.db.countIlvlUpgrades = true
ns:SetMatchLevel(false)
ns:Evaluate()
r3 = ns:ResultForDungeon(ns.dungeonByMapID[249])
byItem = {}
for _, e in ipairs(r3.items) do byItem[e.item.itemID] = e end
check(byItem[1008].class == ns.UPGRADE_NONE and byItem[1008].gain == -3 and not byItem[1008].matched and not byItem[1008].freeLevel, "off: the +8 chest is judged at 308 again")
-- the client's watermarks: Chest 318, Rings 330, Trinkets 305
_G.WATERMARKS = { [3] = 318, [9] = 330, [10] = 305 }
ns:SetMatchLevel(true)
ns:SetTargetKey(10); RunTimers()
check(ns.watermarks[3] == 318 and ns.watermarks[9] == 330 and ns.watermarkSource == "api", "watermarks read from C_ItemUpgrade")
r3 = ns:ResultForDungeon(ns.dungeonByMapID[249])
byItem = {}
for _, e in ipairs(r3.items) do byItem[e.item.itemID] = e end
m = byItem[1008].matched
check(m and m.ilvl == 318 and m.step == 5 and byItem[1008].class == ns.UPGRADE_ILVL and byItem[1008].gain == 7, "chest drop (311 Hero 3/6) raised to the 318 mark: Hero 5/6, +7 over the chest")
m = byItem[1005].matched
check(m and m.ilvl == 321 and m.step == 6 and byItem[1005].class == ns.UPGRADE_TRACK, "ring drop raised to the top of its track (Hero 6/6), not to the 330 mark")
m = byItem[1005].voidcoreMatched
check(m and m.ilvl == 328 and m.step == 4 and m.track.key == "Myth", "the ring's Myth roll goes to Myth 4/6 (328), the last step under 330")
local chestItem
for _, it in ipairs(ns:GetDungeonLoot(249)) do if it.itemID == 1008 then chestItem = it end end
local ml, mk = ns:LinkForContext(chestItem, byItem[1008].matched)
check(mk == "exact" and BonusOfLink(ml) == BonusFor(4, 5), "the tooltip link is the item at Hero 5/6")
r = ns:ResultForDungeon(ns.dungeonByMapID[587])
byItem = {}
for _, e in ipairs(r.items) do byItem[e.item.itemID] = e end
check(byItem[1002].freeLevel == 308 and not byItem[1002].matched, "a mark under the weaker trinket (305) never lowers the free level")
_G.WATERMARKS = nil
ns:SetMatchLevel(false)
ns:ScanGear()
RunTimers()
check(ns.watermarks[3] == nil and ns.watermarkSource == "gear", "watermarks cleared when the client reports nothing")

-- slot states
ns.cdb.slotState[1] = "skip"
ns:Evaluate()
r = ns:ResultForDungeon(ns.dungeonByMapID[587])
byItem = {}
for _, e in ipairs(r.items) do byItem[e.item.itemID] = e end
check(byItem[1001].class == ns.UPGRADE_NONE and byItem[1001].reason == "slot skipped", "skipped slot ignores drops")
ns.cdb.slotState[1] = nil
ns:SetItemState(1002, "exclude")
ns:Evaluate()
r = ns:ResultForDungeon(ns.dungeonByMapID[587])
byItem = {}
for _, e in ipairs(r.items) do byItem[e.item.itemID] = e end
check(byItem[1002].class == ns.UPGRADE_NONE and byItem[1002].voidcore.class == ns.UPGRADE_NONE, "excluded item ignored for drop and Voidcore")
ns:SetItemState(1002, nil)
ns:SetItemState(1008, "want")
ns:Evaluate()
r3 = ns:ResultForDungeon(ns.dungeonByMapID[249])
byItem = {}
for _, e in ipairs(r3.items) do byItem[e.item.itemID] = e end
check(byItem[1008].class == ns.UPGRADE_WANT, "wanted item counts")
check(ns.cdb.itemStateBySpec[72][1008] == "want", "item state kept per spec")
check(r3.wanted == 1 and ns:WantedItemIDs()[1] == 1008, "wanted item counted for its dungeon")
local sum = ns:SlotSummary()
check(sum[5].wanted[1] and sum[5].wanted[1].eval.item.itemID == 1008 and sum[5].wanted[1].source == "Kings' Rest", "slot summary names the wanted item and where it drops")
check(sum[5].wanted[2] and sum[5].wanted[2].source == "The Twin Fangs" and sum[5].wanted[2].ctx.raid, "and the raid boss that drops it too")
check(sum[1].bestDrop and sum[1].bestDrop.eval.item.itemID == 1001, "slot summary names the best drop for the head slot")
-- the wanted chest turns up in the bags: it leaves the list on its own
BAGS[1008] = 1
ns:CheckObtained()
RunTimers()
check(ns:GetItemState(1008) == nil, "wanted item removed once obtained")
BAGS[1008] = nil
-- a drop already in the bags is owned: no upgrade, no roll
do
BAGS[1007] = 1
ns:Evaluate()
local ownedEval
for _, e in ipairs(ns:ResultForDungeon(ns.dungeonByMapID[584]).items) do if e.item.itemID == 1007 then ownedEval = e end end
check(ownedEval and ownedEval.owned and ownedEval.class == ns.UPGRADE_NONE and ownedEval.reason == "owned" and ownedEval.voidcore.reason == "owned",
    "a cloak already in the bags is owned: neither the drop nor the roll is an upgrade")
check(ns.RollValue(ns, ownedEval) == 0, "an owned item is worth nothing to a roll")
BAGS[1007] = nil
ns:Evaluate()
for _, e in ipairs(ns:ResultForDungeon(ns.dungeonByMapID[584]).items) do if e.item.itemID == 1007 then ownedEval = e end end
check(not ownedEval.owned and ownedEval.class == ns.UPGRADE_TRACK, "out of the bags it is an upgrade again")
-- Syndicator remembers the bank between sessions, with each slot's link:
-- a Champion cloak in this character's bank and a Myth ring in the
-- warband bank; another character's data is not asked for
_G.Syndicator = { API = {
    IsReady = function() return true end,
    GetCurrentCharacter = function() return "Tester-Realm" end,
    GetCharacter = function(name)
        if name ~= "Tester-Realm" then return nil end
        return { bags = { {} }, bank = { { { itemID = 1007, itemLink = LinkWithBonus(1007, BonusFor(3, 1)), itemCount = 1 } } }, equipped = {}, void = {} }
    end,
    GetWarband = function() return { bank = { { slots = { { itemID = 1005, itemLink = LinkWithBonus(1005, BonusFor(5, 1)), itemCount = 1 } } } } } end,
} }
ns:ClearOwnedCache()
local cloakCopy, ringCopy = ns:OwnedCopy(1007), ns:OwnedCopy(1005)
check(cloakCopy and cloakCopy.where == "bank" and cloakCopy.track and cloakCopy.track.key == "Champion" and cloakCopy.potential == 308, "Syndicator: the banked cloak is known at Champion 1/6, up to 308")
check(ringCopy and ringCopy.where == "warband bank" and ringCopy.track.key == "Myth" and not ns:OwnsItem(1004), "the warband-banked ring is known at Myth; the sword is not owned")
ns:Evaluate()
local cloakEval, ringEval2
for _, e in ipairs(ns:ResultForDungeon(ns.dungeonByMapID[584]).items) do
    if e.item.itemID == 1007 then cloakEval = e elseif e.item.itemID == 1005 then ringEval2 = e end
end
check(cloakEval and cloakEval.owned and cloakEval.reason == nil and cloakEval.class == ns.UPGRADE_TRACK, "a Hero drop of the cloak still beats the Champion copy: an upgrade, with the copy noted")
check(ringEval2 and ringEval2.reason == "owned" and ringEval2.class == ns.UPGRADE_NONE, "a Hero drop of the ring is redundant next to the Myth copy")
_G.Syndicator = nil
ns:ClearOwnedCache()
check(not ns:OwnsItem(1007), "without it the client's own counts stand")
ns:Evaluate()
end
-- a drop already put through the Catalyst: the worn set piece carries its
-- exact stats, so the drop is owned as "catalyzed"
do
    local wasHead = EQUIPPED[1]
    ITEMS[1001][6] = { CRIT = 60, HASTE = 40 }          -- the Crown's stats are the set hood's
    Equip(1, 7001, 321, "Upgrade Level: Hero 6/6")     -- the hood it became, worn
    ns:ClearStatCache(); ns:ScanGear(); ns:Evaluate()
    local crown
    for _, e in ipairs(ns:ResultForDungeon(ns.dungeonByMapID[587]).items) do if e.item.itemID == 1001 then crown = e end end
    check(crown and crown.owned and crown.owned.catalyzed and crown.owned.itemID == 7001 and crown.reason == "owned" and crown.class == ns.UPGRADE_NONE,
        "the Crown is owned, catalyzed into the worn Venom Hood")
    check(ns:StatsAlike({ CRIT = 75, MASTERY = 116 }, { CRIT = 60, MASTERY = 93 }) and not ns:StatsAlike({ CRIT = 75, MASTERY = 116 }, { CRIT = 116, MASTERY = 75 }),
        "stats alike means the same secondaries in the same proportions, whatever the level")
    ITEMS[1001][6] = nil
    EQUIPPED[1] = wasHead
    ns:ClearStatCache(); ns:ScanGear(); ns:Evaluate()
    for _, e in ipairs(ns:ResultForDungeon(ns.dungeonByMapID[587]).items) do if e.item.itemID == 1001 then crown = e end end
    check(not crown.owned, "with different stats worn it is a drop again")
end
-- share the list
ns:SetItemState(1002, "want"); ns:SetItemState(1005, "want")
local exported = ns:ExportWanted()
check(exported == "SF2:72:1002,1005:", "wanted list exported (" .. exported .. ")")
ns:ClearItemStates()
check(#ns:WantedItemIDs() == 0, "wanted list cleared")
local added = ns:ImportWanted(exported)
check(added == 2 and ns:GetItemState(1002) == "want" and ns:GetItemState(1005) == "want", "wanted list imported")
check(not ns:ImportWanted("nonsense"), "bad list rejected")
ns:ClearItemStates()
RunTimers()

-- key level change
ns:SetTargetKey(4)
RunTimers()
check(ns.dropCtx.ilvl == 298 and ns.dropCtx.track.key == "Champion" and ns.dropCtx.step == 3, "+4 drop = Champion 3/6 (298)")
check(ns.dropCtx.voidcore.ilvl == 308 and ns.dropCtx.voidcore.track.key == "Hero" and ns.dropCtx.voidcore.step == 2, "+4 Voidcore = Hero 2/6 (308)")
ns:SetTargetKey(10)
RunTimers()

-- item links per key level / Voidcore
do
local head
for _, it in ipairs(ns:GetDungeonLoot(587)) do if it.itemID == 1001 then head = it end end
check(head and head.links and head.links[10] and BonusOfLink(head.links[10]) == BonusFor(4, 3), "journal preview link captured for +10 (Hero 3/6)")
check(head.links[2] and BonusOfLink(head.links[2]) == BonusFor(3, 2) and head.links[3] == nil, "preview links stored only where the level changes")
local link, kind = ns:LinkForContext(head, ns.dropCtx)
check(kind == "exact" and BonusOfLink(link) == BonusFor(4, 3), "tooltip link at +10 is Hero 3/6")
ns:SetTargetKey(5); RunTimers()
link, kind = ns:LinkForContext(head, ns.dropCtx)
check(kind == "exact" and BonusOfLink(link) == BonusFor(3, 4), "tooltip link at +5 is Champion 4/6")
ns:SetTargetKey(10); RunTimers()
ns:StepTargetKey(1); RunTimers()
check(ns.db.targetKey == 10 and not ns.dropCtx.isVoidcore, "the selector stops at the last useful key")
local vcCtx = { ilvl = 318, step = 1, track = ns.trackByKey.Myth, key = 10, isVoidcore = true }
link, kind = ns:LinkForContext(head, vcCtx)
check(kind == "exact" and BonusOfLink(link) == BonusFor(5, 1), "Voidcore tooltip link is Myth 1/6 via discovered bonus id")
check(ns.db.linkBonus[30] and ns.db.linkBonus[30].targets["318/1/Myth"] == BonusFor(5, 1), "discovered bonus id cached per season")
ns:StepTargetKey(-1); RunTimers()
check(ns.db.targetKey == 9, "stepping down from +10 gives +9")
ns:SetTargetKey(10); RunTimers()
ns.db.linkBonus = {}
ns:ClearLinkCache()
local l2 = ns:LinkAtLevel(head.link, 311, 3, "Hero")
check(l2 and BonusOfLink(l2) == BonusFor(4, 3), "bonus discovery from the base link alone finds Hero 3/6")
local l3 = ns:LinkAtLevel(head.link, 318, 1, "Myth")
check(l3 and BonusOfLink(l3) == BonusFor(5, 1), "bonus discovery distinguishes Myth 1/6 from Hero 5/6 at the same item level")
-- links without any track bonus (journal at plain Mythic): anchors come from equipped gear
ns.db.linkBonus = {}
ns:ClearLinkCache()
local chest
for _, it in ipairs(ns:GetDungeonLoot(249)) do if it.itemID == 1008 then chest = it end end
check(chest and HasBonus(chest.link, 3524) and BonusOfLink(chest.link) == nil and not chest.links, "Kings' Rest links carry only the Mythic tag 3524")
ns.gearAnchors = nil
local l4 = ns:LinkAtLevel(chest.link, 311, 3, "Hero")
check(l4 and BonusOfLink(l4) == BonusFor(4, 3) and ContextOf(l4) ~= "23", "track bonus grafted from gear anchors with the pinning context cleared")
check(ns.gearAnchors and #ns.gearAnchors >= 1, "gear anchors learned from equipped items")
check(not ns.db.linkBonus[30].known[3524], "difficulty tag 3524 is not treated as a track bonus")
local l5 = ns:LinkAtLevel(chest.link, 318, 1, "Myth")
check(l5 and BonusOfLink(l5) == BonusFor(5, 1) and ContextOf(l5) ~= "23", "Voidcore link (Myth 1/6) built with the context removed, not mislabelled Champion 1/6")
local l7 = ns:LinkAtLevel(chest.link, 305, 1, "Hero")
check(l7 and BonusOfLink(l7) == BonusFor(4, 1) and ContextOf(l7) ~= "23", "+6 link (Hero 1/6) is not mislabelled by the journal context")
local l8 = ns:LinkAtLevel(chest.link, 318, 1, "Myth")
local pi, pn, pc = ns:ProbeLink(l8)
check(pi == 318 and pn == "Myth" and pc == 1, "Voidcore link renders as 318 Myth 1/6")
local l6, k6 = ns:LinkForContext(chest, ns.dropCtx)
check(k6 == "exact" and BonusOfLink(l6) == BonusFor(4, 3), "tooltip link for a bonus-less item is exact at +10")
-- resolved links are remembered: no tooltip renders the second time round
local probes = 0
local realHyperlink = C_TooltipInfo.GetHyperlink
C_TooltipInfo.GetHyperlink = function(...) probes = probes + 1; return realHyperlink(...) end
local l6b, k6b = ns:LinkForContext(chest, ns.dropCtx)
check(l6b == l6 and k6b == "exact" and probes == 0, "resolved links are cached (" .. probes .. " tooltip renders)")
ns:Evaluate()
check(probes == 0, "a full evaluation renders no tooltips once links are cached (" .. probes .. ")")
C_TooltipInfo.GetHyperlink = realHyperlink
ns:PrintLinkDiagnostics()

-- reward API not loaded yet: flat curve -> season fallback table
API_FLAT = true
ns:ClearRewardCache()
local ilvl, src = ns:RewardIlvl(10)
check(ilvl == 311 and src == "api", "a flat reward API keeps the last good answer (" .. tostring(ilvl) .. ", " .. tostring(src) .. ")")
ns:ClearRewardCache(true)
ilvl, src = ns:RewardIlvl(10)
check(ilvl == 311 and src == "fallback", "with nothing remembered it falls back to the season table (" .. tostring(ilvl) .. ", " .. tostring(src) .. ")")
local v, vsrc = ns:VaultIlvl(10)
check(v == 318 and vsrc == "fallback", "vault level from fallback table")
end
check(ns:RewardIlvl(2) == 295 and ns:RewardIlvl(15) == 311, "fallback covers +2 and beyond the table")
local requestsBefore = REQUESTED_REWARDS or 0
local dungeonUpdates = 0
ns:On("DUNGEONS_UPDATED", function() dungeonUpdates = dungeonUpdates + 1 end)
ns:Evaluate()
RunTimers()
check((REQUESTED_REWARDS or 0) == requestsBefore, "evaluating with a flat API does not request season data (no request/event loop)")
ev(ns.eventFrame, "CHALLENGE_MODE_MAPS_UPDATE")
RunTimers()
check(dungeonUpdates == 0 and #ns.dungeons == 3, "an update event with the same pool rebuilds nothing")
API_FLAT = false
ns:ClearRewardCache()
RunTimers()
check(ns:RewardIlvl(10) == 311 and select(2, ns:RewardIlvl(10)) == "api", "API used again once the curve rises")

-- combat: evaluations wait for the fight to end
local evaluations = 0
ns:On("RESULTS_UPDATED", function() evaluations = evaluations + 1 end)
_G.InCombatLockdown = function() return true end
ns:Fire("SETTINGS_CHANGED")
RunTimers()
check(evaluations == 0 and ns.evaluatePending == true, "no evaluation in combat; one is pending")
_G.InCombatLockdown = function() return false end
ev(ns.eventFrame, "PLAYER_REGEN_ENABLED")
RunTimers()
check(evaluations == 1 and ns.evaluatePending == nil, "the pending evaluation runs when combat ends")

-- calibration: stale defaults (previous season, 13 lower); equipped items must rebuild the table
ns.db.trackOverride = nil
ns.SEASON.championBase = 279
ns.trackOffsetApplied = nil
ns:ApplyTrackDefaults()
check(ns.trackByKey.Hero.min == 292, "stale defaults applied (Hero base 292)")
ns:ScanGear()
check(ns.trackOffsetApplied == 13, "stale defaults auto-calibrated by +13 (" .. tostring(ns.trackOffsetApplied) .. ")")
check(ns.trackByKey.Hero.min == 305 and ns.trackByKey.Hero.max == 321, "Hero after calibration = 305-321")
check(ns.db.calibratedChampionBase == 292, "calibrated base remembered in saved variables")
-- no defaults at all: bootstrap purely from gear
ns.SEASON.championBase = 0
ns.db.calibratedChampionBase = nil
ns.tracksCalibrated = nil
ns:ApplyTrackDefaults()
check(not ns:HasTrackData(), "no track data without defaults")
ns:ScanGear()
check(ns:HasTrackData() and ns.trackByKey.Champion.min == 292, "track table bootstrapped from equipped items")
check(ns.gear[1].track and ns.gear[1].track.key == "Champion" and ns.gear[1].potential == 308, "gear re-resolved after bootstrap")
local t = ns:ResolveTrack("Held", 2, 6, 308)
check(t and t.key == "Hero", "non-English track name resolved structurally")
check(ns:TrackKeyForName("Held") == "Hero", "non-English name learned")
ns.SEASON.championBase = 292

-- activity mapping
check(ns:DungeonForActivity(1749) == ns.dungeonByMapID[587], "activity id -> dungeon via fallback table")
check(ns:DungeonForActivity(9999) == ns.dungeonByMapID[584], "activity name -> dungeon via name match")
check(ns.DungeonForResult(1) == ns.dungeonByMapID[587], "search result -> dungeon")

-- keystone tooltips
local km, kl = ns.KeystoneFromLink("|cffa335ee|Hkeystone:180653:587:12:9:10:0:0|h[Keystone: Murder Row (12)]|h|r")
check(km == 587 and kl == 12, "keystone link parsed")
local kt = { lines = {}, AddLine = function(self, text) table.insert(self.lines, text) end, Show = function() end }
ns:AddKeystoneTooltip(kt, 587, 12)
check(#kt.lines >= 2 and kt.lines[2]:find("Slot Filler:", 1, true) and kt.lines[2]:find("+12", 1, true), "keystone tooltip evaluates at the key's level")
local kt2 = { lines = {}, AddLine = function(self, text) table.insert(self.lines, text) end, Show = function() end }
ns:AddKeystoneTooltip(kt2, 249, 5)
check(#kt2.lines >= 2 and kt2.lines[2]:find("+5", 1, true), "keystone tooltip for a lower key")

-- Mythic+ rating: score model
check(ns:TimedScore(2) == 155 and ns:TimedScore(5) == 215 and ns:TimedScore(7) == 260 and ns:TimedScore(10) == 320 and ns:TimedScore(12) == 365,
    "timed score table (+2 155, +5 215, +7 260, +10 320, +12 365)")
check(ns:TimedScore(10, 1800, 1500) == 326.25, "timer bonus: 300 s under a 30 min timer = +6.25")
check(ns:TimedScore(10, 1800, 1000) == 335, "timer bonus capped at +15")
check(ns:TimedScore(10, 1800, 1900) == nil and ns:TimedScore(1) == 0, "over time is not modelled; below +2 scores nothing")

-- rating data read from the client
ns.ratingDirty = true
local rating = ns:ReadRatings()
check(rating.ready and rating.overall == 626.25, "overall rating read (" .. tostring(rating.overall) .. ")")
local r587, r584, r249 = ns:DungeonRating(587), ns:DungeonRating(584), ns:DungeonRating(249)
check(r587.timed and r587.level == 10 and r587.floor == 11, "timed +10 at 326.25: next gain from +11")
check(r584.hasRun and not r584.timed and r584.level == 12 and r584.floor == 10, "depleted +12 at 300: a timed +10 already gains")
check(not r249.hasRun and r249.score == 0 and r249.floor == 2, "never run: starts at +2")
check(ns.ratingCheck and ns.ratingCheck.checked == 1 and ns.ratingCheck.off == 0, "formula matches the game's score for the timed run")
check(ns:RatingGain(587, 12) == 38.75 and ns:RatingGain(587, 10) == 0, "gain at a level")

-- plans: target 1200 (need 573.75), no cap
ns:SetRatingMaxKey(30)
ns:SetRatingTarget(1200)
local plans, pinfo = ns:RatingPlans()
local function PlanText(p)
    local t = {}
    for _, run in ipairs(p.runs) do t[#t + 1] = string.format("%d@%d", run.mapID, run.level) end
    return table.concat(t, " ")
end
check(#plans == 3 and plans[1].count == 1 and plans[2].count == 2 and plans[3].count == 3, "three plans, one per run count (" .. #plans .. ")")
check(PlanText(plans[1]) == "249@26", "fastest: one run at +26 (" .. PlanText(plans[1]) .. ")")
check(PlanText(plans[2]) == "249@17 584@17", "two runs at +17 (" .. PlanText(plans[2]) .. ")")
check(PlanText(plans[3]) == "249@15 584@14 587@14" and plans[3].total == 573.75, "easiest: three runs, lowest keys (" .. PlanText(plans[3]) .. ")")
check(plans[1].maxLevel >= plans[2].maxLevel and plans[2].maxLevel >= plans[3].maxLevel, "max key never rises with more runs")
check(plans[1].fastest and plans[3].easiest and not plans[2].fastest, "first plan is Fastest, last is Easiest")
check(ns:SelectedRatingPlan() == plans[3], "the easiest plan is selected by default")
ns:SetRatingRuns(2)
check(ns:SelectedRatingPlan() == plans[2] and ns:PlannedRun(584).gain == 140 and ns:PlannedRun(587) == nil, "Runs picks the plan by count; planned run per dungeon")
ns:SetRatingRuns(1)
ns:SetRatingMaxKey(20)
plans = ns:RatingPlans()
check(#plans == 2 and plans[1].count == 2, "a max key of 20 drops the one-run plan")
check(ns:SelectedRatingPlan() == plans[1], "an unavailable run count falls back to the next larger plan")
ns:SetRatingRuns(nil)
ns:SetRatingMaxKey(nil)
local cap, capAuto = ns:RatingMaxKey()
check(cap == 12 and capAuto, "automatic max key = highest timed key + 2 (" .. tostring(cap) .. ")")
ns:SetRatingTarget(1000)
plans = ns:RatingPlans()
check(#plans == 2 and PlanText(plans[1]) == "249@12 584@11" and PlanText(plans[2]) == "249@11 584@11 587@11", "plans under the automatic cap (" .. PlanText(plans[1]) .. " / " .. PlanText(plans[2]) .. ")")
ns:SetRatingTarget(1200)
plans, pinfo = ns:RatingPlans()
check(#plans == 1 and pinfo.partial and plans[1].partial and plans[1].maxLevel == 12 and plans[1].total == 468.75, "out of reach under the cap: one partial plan with everything at the cap")
ns:SetRatingMaxKey(2)
plans = ns:RatingPlans()
check(#plans == 1 and plans[1].partial and PlanText(plans[1]) == "249@2" and plans[1].total == 155, "cap +2: partial plan is the one +2")
ns:SetRatingMaxKey(30)
ns:ToggleAvoidDungeon(249)
ns:SetRatingTarget(650)
plans = ns:RatingPlans()
check(ns:IsDungeonAvoided(249) and #plans == 1 and PlanText(plans[1]) == "584@11" and plans[1].runs[1].gain == 35, "avoiding a dungeon: the depleted +12 is planned as a timed +11 (" .. PlanText(plans[1]) .. ")")
ns:ToggleAvoidDungeon(249)
plans = ns:RatingPlans()
check(not ns:IsDungeonAvoided(249) and PlanText(plans[1]) == "249@2", "avoid toggles back")
ns:SetRatingTarget(600)
plans, pinfo = ns:RatingPlans()
check(#plans == 0 and pinfo.reached, "target already reached: no plans")

-- target: automatic milestone, custom stepping
ns:SetRatingTarget(nil)
local tgt, tauto, ttab = ns:RatingTarget()
check(tgt == 2000 and tauto and ttab == "2000", "automatic target is the next milestone (" .. tostring(tgt) .. ")")
OVERALL_OVERRIDE = 2100; ns.ratingDirty = true
check(ns:RatingTarget() == 2500, "next milestone above 2100 is 2500")
OVERALL_OVERRIDE = 3050; ns.ratingDirty = true
check(ns:RatingTarget() == 3100, "past the last milestone: next hundred")
OVERALL_OVERRIDE = nil; ns.ratingDirty = true
ns:SetRatingTarget(2050)
tgt, tauto, ttab = ns:RatingTarget()
check(tgt == 2050 and not tauto and ttab == "custom", "a custom target")
ns:StepRatingTarget(-1)
check(select(3, ns:RatingTarget()) == "2000", "stepping onto a milestone selects its tab")
ns:SetRatingTarget(nil)

-- requests: planning never asks the server; a completed run asks once, after combat
local mapInfoBefore = REQUESTED_MAPINFO or 0
ns.ratingDirty = true
ns:RatingPlans()
ev(ns.eventFrame, "CHALLENGE_MODE_MAPS_UPDATE")
RunTimers()
check((REQUESTED_MAPINFO or 0) == mapInfoBefore, "reading ratings and planning never request map info")
_G.InCombatLockdown = function() return true end
ev(ns.eventFrame, "CHALLENGE_MODE_COMPLETED")
RunTimers()
check((REQUESTED_MAPINFO or 0) == mapInfoBefore and ns.ratingRequestPending == true, "a run finished in combat waits")
_G.InCombatLockdown = function() return false end
ev(ns.eventFrame, "PLAYER_REGEN_ENABLED")
RunTimers()
check((REQUESTED_MAPINFO or 0) == mapInfoBefore + 1 and not ns.ratingRequestPending, "map info requested once combat ends")

-- stat priority: Manual mode by default, starting from the gear order until a click saves one
local order, src = ns:GetStatPriority()
check(ns:GetStatMode() == "manual" and ns:GetManualStatPriority() == nil, "Manual mode by default, nothing saved yet")
check(src == "gear" and order[1] == "HASTE" and order[2] == "MASTERY" and order[3] == "CRIT" and order[4] == "VERS",
    "stat priority learned from gear (" .. table.concat(order or {}, ">") .. ")")
local fake = { challengeMapID = 9999, name = "Fake Keep" }
ns.loot.dungeons[9999] = { items = {
    { itemID = 1005, name = "Ring of Testing", link = Link(1005), equipLoc = "INVTYPE_FINGER", icon = 1 },
    { itemID = 1009, name = "Ring of Haste", link = Link(1009), equipLoc = "INVTYPE_FINGER", icon = 1 },
} }
local fr = ns:EvaluateDungeonAt(fake, 10)
check(fr.items[1].item.itemID == 1009 and fr.items[2].item.itemID == 1005, "same-slot drops ordered by stat fit")
check(fr.items[1].fit and math.abs(fr.items[1].fit - 0.8667) < 0.001, "Haste/Mastery ring fits 0.87 (top two stats)")
check(fr.items[2].fit and math.abs(fr.items[2].fit - 0.1667) < 0.001, "Crit/Vers ring fits 0.17 (bottom two stats)")
check(fr.items[1].equippedStats and fr.items[1].equippedStats.MASTERY == 50, "equipped ring stats read for the tooltip")
check(fr.items[1].value == nil, "no weighted value without a scale")
local settingsFires = 0
ns:On("SETTINGS_CHANGED", function() settingsFires = settingsFires + 1 end)
ns:SetStatPriority({ "VERS", "CRIT", "MASTERY", "HASTE" })
check(settingsFires == 1, "saving a manual order fires SETTINGS_CHANGED once")
RunTimers()
fr = ns:EvaluateDungeonAt(fake, 10)
check(fr.items[1].item.itemID == 1005, "manual priority reverses the order")
check(select(2, ns:GetStatPriority()) == "manual", "manual priority reported")
ns:SetStatMode("auto")
RunTimers()
check(select(2, ns:GetStatPriority()) == "gear" and ns:GetManualStatPriority() ~= nil, "Auto follows the gear and keeps the manual order")
ns:SetStatMode("manual")
check(select(2, ns:GetStatPriority()) == "manual" and ns:GetStatPriority()[1] == "VERS", "back to Manual restores it")
ns:SetStatPriority(nil)
RunTimers()
check(select(2, ns:GetStatPriority()) == "gear" and ns:GetStatMode() == "manual", "forgetting the manual order starts from the gear again")

-- Pawn scale import: weights order the stats and value the drops
local PAWN = '( Pawn: v1: "Erunak - Restoration Raid": Class=Shaman, Spec=Restoration, Intellect=81.97, CritRating=46.19, HasteRating=39.07, Versatility=36.99, MasteryRating=30.47, Leech=1.69, Avoidance=0.02, Indestructible=0.01, MovementSpeed=0.01 )'
local parsed, perr = ns:ParsePawnString(PAWN)
check(parsed and parsed.name == "Erunak - Restoration Raid" and parsed.class == "Shaman" and parsed.spec == "Restoration", "Pawn string header parsed")
check(parsed and math.abs(parsed.weights.CRIT - 46.19) < 0.001 and math.abs(parsed.weights.PRIMARY - 81.97) < 0.001 and math.abs(parsed.weights.LEECH - 1.69) < 0.001, "Pawn weights parsed")
check(parsed and parsed.primary == "Intellect", "primary stat remembered by name")
check(not ns:ParsePawnString("hello"), "garbage is rejected")
settingsFires = 0
local imported, pIndex = ns:ImportPawnString(PAWN)
check(settingsFires == 1, "importing a profile fires SETTINGS_CHANGED once")
RunTimers()
check(imported and pIndex == 1 and ns:StatProfileName() == "Erunak - Restoration Raid", "import saves an active profile named after the scale")
check(imported.gear and imported.gear[1] and imported.gear[1].itemID == 5001 and #ns:StatProfileGearDiff(imported) == 0, "a profile remembers the gear it was made for")
do
    local fakeButton = { Text = { SetText = function(self, t) self.text = t end } }
    ns.UI.RefreshStatProfileButton(fakeButton)
    check(not fakeButton.Text.text:find("gear changed", 1, true), "the weights button is quiet while the gear matches")
    local wasHead = EQUIPPED[1]
    Equip(1, 7001, 318, "Upgrade Level: Hero 5/6")
    ns:ScanGear()
    local diff = ns:StatProfileGearDiff(imported)
    check(#diff == 1 and diff[1].slotID == 1 and diff[1].from.itemID == 5001 and diff[1].to.itemID == 7001, "a new helm shows as one changed slot, old and new named")
    ns.UI.RefreshStatProfileButton(fakeButton)
    check(fakeButton.Text.text:find("gear changed", 1, true), "the weights button says the gear changed")
    EQUIPPED[1] = wasHead
    ns:ScanGear()
    check(#ns:StatProfileGearDiff(imported) == 0, "back in the old helm it is quiet again")
end
check(ns:GetStatMode() == "auto", "importing weights switches to Auto")
check(ns.cdb.statProfiles[ns:GetEvalSpecID()][1] == imported and ns.db.statProfiles == nil, "profiles live in the per-character saved variables")
order, src = ns:GetStatPriority()
check(imported and src == "weights" and order[1] == "CRIT" and order[2] == "HASTE" and order[3] == "VERS" and order[4] == "MASTERY",
    "weights order the stats (" .. table.concat(order or {}, ">") .. ")")
fr = ns:EvaluateDungeonAt(fake, 10)
check(fr.items[1].fit and math.abs(fr.items[1].fit - 0.328) < 0.01 or fr.items[2].fit and math.abs(fr.items[2].fit - 0.328) < 0.01, "fit uses the real weights")
check(fr.items[1].value and fr.items[2].value and fr.items[1].value > fr.items[2].value, "same-slot drops ordered by weighted value")
check(fr.items[1].item.itemID == 1009, "the ring with a primary stat is worth more")
check(fr.items[1].valueGain and math.abs(fr.items[1].valueGain - (11760 - 9640.6)) < 0.5, "value gain vs the equipped ring (" .. tostring(fr.items[1].valueGain) .. ")")
check(fr.items[1].voidcore and fr.items[1].voidcore.value, "Voidcore roll valued too")
local wtext = ns:StatWeightsText(imported, true)
check(wtext:find("^Int 82, Cri 46, Has 39") ~= nil, "weights text lists the largest first (" .. wtext .. ")")

-- several named profiles per spec
local PAWN2 = '( Pawn: v1: "Erunak - Restoration M+": Class=Shaman, Spec=Restoration, Intellect=80, HasteRating=60, MasteryRating=50, CritRating=30, Versatility=20 )'
local second, secondIndex = ns:ImportPawnString(PAWN2, "Mythic+")
RunTimers()
check(second and secondIndex == 2 and ns:StatProfileName() == "Mythic+" and second.pawnName == "Erunak - Restoration M+", "second import is a new profile under the given name, now in use")
order = ns:GetStatPriority()
check(order[1] == "HASTE" and order[2] == "MASTERY", "the profile in use orders the stats (" .. table.concat(order or {}, ">") .. ")")
fr = ns:EvaluateDungeonAt(fake, 10)
check(fr.items[1].item.itemID == 1009 and fr.items[1].value and math.abs(fr.items[1].value - (ns:ItemValue(Link(1009), second) or 0)) < 0.01, "values come from the profile in use")
check(#ns:GetStatProfiles() == 2, "both profiles kept")
do
    local again, againIndex = ns:ImportPawnString((PAWN:gsub("CritRating=%d+%.?%d*", "CritRating=99")))
    check(againIndex == 1 and again == imported and #ns:GetStatProfiles() == 2 and imported.weights.CRIT == 99 and ns:StatProfileName() == "Erunak - Restoration Raid",
        "re-importing the same scale replaces its profile in place, newer weights win")
    ns:ImportPawnString(PAWN)
    check(#ns:GetStatProfiles() == 2 and imported.weights.CRIT ~= 99, "and again: still two profiles, the weights the latest paste")
end
check(ns:SetActiveStatProfile(1) and ns:StatProfileName() == "Erunak - Restoration Raid", "switching back to the first profile")
RunTimers()
order = ns:GetStatPriority()
check(order[1] == "CRIT", "priority follows the switch")
fr = ns:EvaluateDungeonAt(fake, 10)
check(fr.items[1].value and math.abs(fr.items[1].value - (ns:ItemValue(Link(1009), imported) or 0)) < 0.01, "values follow the switch (no stale cache)")
check(ns:RenameStatProfile(1, "  Raid ") and ns:StatProfileName() == "Raid", "rename trims and applies")
check(not ns:RenameStatProfile(1, "  "), "empty name rejected")
check(ns:FindStatProfile("mythic+") == 2 and ns:FindStatProfile("2") == 2 and ns:FindStatProfile("nope") == nil, "profiles found by name (any case) or number")
-- the spec a string is saved for: its own Spec= when it is one of ours
do
    local PROT = '( Pawn: v1: "Sager - Protection": Class=Warrior, Spec=Protection, Strength=70, HasteRating=60, MasteryRating=50, Versatility=40, CritRating=30 )'
    local ARMS = '( Pawn: v1: "Sager - Arms": Class=Warrior, Spec=Arms, Strength=70, CritRating=60, MasteryRating=50, HasteRating=40, Versatility=30 )'
    check(ns:PawnScaleSpecID(ns:ParsePawnString(PROT)) == 73 and ns:PawnScaleSpecID(ns:ParsePawnString(PAWN)) == nil,
        "a Warrior Protection string is for Protection; a Shaman's is for no spec of ours")
    check(ns:PawnScaleSpecID({ class = "Warrior", spec = "PROTECTION" }) == 73 and ns:PawnScaleSpecID({ spec = "arms" }) == 71 and ns:PawnScaleSpecID({ class = "DeathKnight", spec = "Blood" }) == nil,
        "class and spec match in any case; the class is optional")
    local beforeEval = #ns:GetStatProfiles()
    local prot, protIndex, protSpec = ns:ImportPawnString(PROT)
    check(prot and protSpec == 73 and protIndex == 1 and ns.cdb.statProfiles[73][1] == prot and ns.cdb.statProfile[73] == 1 and ns.cdb.statMode[73] == "auto",
        "importing while evaluating Fury saves the Protection string under Protection and switches that spec to it")
    check(#ns:GetStatProfiles() == beforeEval and ns:StatProfileName() == "Raid", "the evaluated spec keeps its profiles and the one in use")
    check(prot.gear == nil and #ns:StatProfileGearDiff(prot) == 0, "gear worn for another spec is not remembered as what the weights were made for")
    check(ns:PawnSavedText(prot, 73):find("for Protection", 1, true) and ns:PawnSavedText(prot, 73):find("The window shows Fury", 1, true),
        "the chat line names the spec it went to and points at the spec button")
    check(ns:PawnSavedText(imported, 72):find("The string says Shaman Restoration", 1, true), "a string for another class says so")
    local arms, _, armsSpec = ns:ImportPawnString(ARMS, nil, 73)
    check(arms and armsSpec == 73 and ns.cdb.statProfiles[73][2] == arms and ns.cdb.statProfile[73] == 2, "a spec given outright wins over the string's own")
    check(ns:FindPlayerSpec("prot").id == 73 and ns:FindPlayerSpec("ARMS").id == 71 and ns:FindPlayerSpec(72).name == "Fury" and ns:FindPlayerSpec("holy") == nil,
        "specs found by name, the start of one, or ID")
    SlashCmdList.SLOTFILLER("pawn arms " .. PROT)
    check(#ns.cdb.statProfiles[71] == 1 and ns.cdb.statProfiles[71][1].pawnName == "Sager - Protection", "/sf pawn <spec> <string> saves for that spec")
    SlashCmdList.SLOTFILLER("pawn holy " .. PROT)
    check(#ns.cdb.statProfiles[71] == 1 and #ns.cdb.statProfiles[73] == 2, "a spec we do not have saves nothing")
    ns.cdb.statProfiles[71], ns.cdb.statProfiles[73], ns.cdb.statProfile[73], ns.cdb.statMode[73] = nil, nil, nil, nil
end
SlashCmdList.SLOTFILLER("pawn use Mythic+")
RunTimers()
check(ns:StatProfileName() == "Mythic+", "/sf pawn use <name>")
SlashCmdList.SLOTFILLER("pawn rename 2 Keys")
check(ns:StatProfileName() == "Keys", "/sf pawn rename <n> <name>")
SlashCmdList.SLOTFILLER("pawn")
SlashCmdList.SLOTFILLER("pawn clear")
RunTimers()
check(select(2, ns:GetStatPriority()) == "gear" and ns:GetStatWeights() == nil and #ns:GetStatProfiles() == 2, "/sf pawn clear uses no profile but keeps them")
SlashCmdList.SLOTFILLER("pawn use 2")
check(ns:DeleteStatProfile(1) and ns:StatProfileName() == "Keys" and #ns:GetStatProfiles() == 1, "deleting an earlier profile keeps the one in use")
SlashCmdList.SLOTFILLER("pawn delete keys")
RunTimers()
check(#ns:GetStatProfiles() == 0 and ns:GetStatWeights() == nil, "/sf pawn delete <name> removes the profile in use")
SlashCmdList.SLOTFILLER("pawn " .. PAWN)
RunTimers()
check(ns:GetStatWeights() and ns:GetStatWeights().name == "Erunak - Restoration Raid", "/sf pawn imports with original casing")
ns:SetActiveStatProfile(nil)
RunTimers()
ns.loot.dungeons[9999] = nil

-- UI smoke test: show/hide with PVEFrame
PVEFrame._shown = true
ns.db.anchorSide = "left"
ns:ShowWindow(false)
RunTimers()
check(ns:IsWindowShown(), "window shown")
check(ns:CurrentPage() == "dungeons", "Dungeons tab first")

-- the drawer: folded away, a tab stands in; the setting says when the window opens by itself
check(not ns:IsDrawerShown(), "no drawer tab while the window is open")
ns:HideWindow(true)
check(not ns:IsWindowShown() and ns:IsDrawerShown() and SlotFillerDrawer:IsShown(), "folded away by hand: the drawer tab shows")
check(ns.userExpanded == false and not ns:AutoExpanded(), "folded by hand sticks for this Group Finder visit")
ns:UpdateAutoVisibility()
check(not ns:IsWindowShown(), "the Always rule does not reopen it")
SlotFillerDrawer:GetScript("OnClick")(SlotFillerDrawer)
check(ns:IsWindowShown() and not ns:IsDrawerShown() and ns.userExpanded == true, "the drawer tab opens the window")
ns.userExpanded = nil
ns.db.autoExpand = "premade"
LFGListFrame._shown = false
ns:UpdateAutoVisibility()
check(not ns:IsWindowShown() and ns:IsDrawerShown(), "Premade: folded away off the Premade Groups tab")
LFGListFrame._shown = true
ns:UpdateAutoVisibility()
check(ns:IsWindowShown() and not ns:IsDrawerShown(), "Premade: opens on the Premade Groups tab")
LFGListFrame._shown = false
ns:UpdateAutoVisibility()
check(not ns:IsWindowShown(), "Premade: folds away again on leaving it")
ns.db.autoExpand = "never"
LFGListFrame._shown = true
ns:UpdateAutoVisibility()
check(not ns:IsWindowShown() and ns:IsDrawerShown(), "Never: only the drawer tab")
ns.db.autoExpand = "always"
ns:UpdateAutoVisibility()
check(ns:IsWindowShown() and not ns:IsDrawerShown(), "Always: open again")
RunTimers()
-- Escape: next to the Group Finder the window is not a special frame (one
-- press closes both); on its own it is
local function IsSpecial()
    for _, name in ipairs(UISpecialFrames) do if name == "SlotFillerFrame" then return true end end
    return false
end
check(not IsSpecial(), "next to the Group Finder, Escape is left to the Group Finder")
PVEFrame:GetScript("OnHide")(PVEFrame)
PVEFrame._shown = false
ns:ShowWindow(true)
check(IsSpecial(), "on its own, Escape closes the window")
PVEFrame._shown = true
PVEFrame:GetScript("OnShow")(PVEFrame)
check(not IsSpecial(), "back next to the Group Finder, Escape is its again")
RunTimers()
local wb = SlotFillerFrame.Toolbar.WeightsButton
check(wb and wb.Text:GetText():find("none", 1, true) ~= nil, "toolbar shows that no weight profile is in use")
check(wb:GetScript("OnEnter") == nil, "the weights button carries no tooltip of its own (it would sit on the open menu)")
wb:GetScript("OnClick")(wb)
check(ns.UI.IsMenuShown(), "weights menu opens")
do
    local entries = wb.entries()
    local profiles = ns:GetStatProfiles()
    check(#entries == #profiles + 1 and type(entries[1].tip) == "function" and type(entries[#entries].tip) == "table", "each menu row carries its own tip: the profile's weights, or what None means")
    local lines = {}
    local tip = { AddLine = function(_, t) lines[#lines + 1] = tostring(t) end }
    entries[1].tip(tip)
    check(lines[1] == tostring(profiles[1].name) and lines[2]:find("Intellect", 1, true), "a profile row's tip names it and lists its weights (" .. tostring(lines[1]) .. ": " .. tostring(lines[2]) .. ")")
end
wb:GetScript("OnClick")(wb)
check(not ns.UI.IsMenuShown(), "clicking again closes it")
do
    local sb = SlotFillerFrame.Toolbar.SpecButton
    check(sb.entries and sb:GetScript("OnEnter") == nil, "the spec button is a dropdown without a tooltip of its own")
    local entries = sb.entries()
    check(#entries == 4 and entries[1].checked and entries[1].text:find("Loot spec", 1, true) and entries[1].tip and entries[4].text == "Protection",
        "its menu: follow the loot spec (checked, with a tip), then every spec")
    entries[4].onClick()
    check(ns.cdb.evalSpecID == 73 and ns:GetEvalSpecID() == 73 and sb.Text:GetText() == "Protection", "picking Protection pins the window to it")
    check(sb.entries()[4].checked and not sb.entries()[1].checked, "the pinned spec is the checked row")
    sb.entries()[1].onClick()
    check(ns.cdb.evalSpecID == nil and ns:GetEvalSpecID() == 72 and sb.Text:GetText():find("loot spec", 1, true), "Loot spec follows the loot spec again")
end
ns:SetActiveStatProfile(1)
check(wb.Text:GetText():find("Weights:|r Restoration Raid", 1, true) ~= nil, "toolbar shows the profile in use without the character name (the spec stays: this Warrior has no Restoration) (" .. tostring(wb.Text:GetText()) .. ")")
do
    local specName = ns:SpecName(ns:GetEvalSpecID())
    check(ns:StatProfileLabel({ name = "Erunak - " .. specName .. " M+" }) == "M+" and ns:StatProfileLabel({ name = "erunak-" .. specName:lower() .. ": Keys" }) == "Keys",
        "labels drop a leading character name and spec name in any case, with any separator")
    check(ns:StatProfileLabel({ name = specName .. " Raid" }) == "Raid" and ns:StatProfileLabel({ name = "Erunak" }) == "Erunak" and ns:StatProfileLabel({ name = "Mythic+" }) == "Mythic+",
        "either prefix alone goes; a name that is just the character name, or has no prefix, stays whole")
    check(ns:StatProfileLabel({ name = "Erunak - " .. specName }) == specName, "a name that is only the two prefixes keeps the spec")
end
ns:SetActiveStatProfile(nil)
RunTimers()
ns.uiExpandedMapID = 587
ns:RefreshWindow()
ns:ShowPage("gear")
check(ns:CurrentPage() == "gear", "Gear tab shown")
ns.uiExpandedSlotID = 11
ns:RefreshWindow()
do
    local ringRow, secondRing
    for _, r in ipairs(ns.UI.Pools.gearRows) do
        if r:IsShown() and r.slotID == 11 then ringRow = r end
        if r:IsShown() and r.slotID == 12 then secondRing = r end
    end
    check(ringRow and not secondRing and ringRow.Name:GetText():find("^Rings") and ringRow.Name:GetText():find("·", 1, true), "rings are one Gear row showing both worn rings (" .. tostring(ringRow and ringRow.Name:GetText()) .. ")")
    local ringDrops = 0
    for _, it in ipairs(ns.UI.Pools.gearItems) do if it:IsShown() and it.eval and it.eval.slotID == 12 then ringDrops = ringDrops + 1 end end
    check(ringDrops > 0, "the drops judged against the weaker ring list under that one row")
    ns:CycleSlotState(11, 12)
    check(ns:GetSlotState(11) == "want" and ns:GetSlotState(12) == "want", "right-click sets both rings")
    ns:CycleSlotState(11, 12); ns:CycleSlotState(11, 12)
    check(ns:GetSlotState(11) == "auto" and ns:GetSlotState(12) == "auto", "and cycles both back to Auto")
end
ns:RefreshWindow()
ns.db.gearSort = "upgrades"
ns:RefreshWindow()
ns.db.gearSort = "slot"
ns:ShowPage("raid")
check(ns:CurrentPage() == "raid", "Raid tab shown")
ns.uiExpandedEncounterID = 3001
ns:RefreshWindow()
local raidPage = SlotFillerFrame.Pages.raid
check(raidPage.Strip.Tabs.selectedTabID == "heroic", "difficulty strip shows Heroic")
ns:SetRaidDifficulty("mythic")
RunTimers()
check(raidPage.Strip.Tabs.selectedTabID == "mythic", "difficulty strip follows the setting")
-- the Curio row opens into its five pieces
ns.uiExpandedEncounterID = 3002
ns:RefreshWindow()
local curioRow
for _, it in ipairs(ns.UI.Pools.raidItems) do if it:IsShown() and it.eval and it.eval.token and it.eval.token.itemID == 270909 then curioRow = it end end
check(curioRow and curioRow.Name:GetText():find("Slumbering Coil Curio", 1, true) and curioRow.Arrow:IsShown() and #curioRow.eval.pieces == 5, "the Curio row shows the token with an arrow")
local rowsBefore = 0
for _, it in ipairs(ns.UI.Pools.raidItems) do if it:IsShown() then rowsBefore = rowsBefore + 1 end end
curioRow:GetScript("OnClick")(curioRow, "LeftButton")
local rowsAfter, pieceNames = 0, {}
for _, it in ipairs(ns.UI.Pools.raidItems) do
    if it:IsShown() then
        rowsAfter = rowsAfter + 1
        if it.eval and it.eval.item.piece and not it.eval.pieces then pieceNames[#pieceNames + 1] = it.eval.item.name end
    end
end
check(ns.uiExpandedTokenID == 270909 and rowsAfter == rowsBefore + 5 and #pieceNames == 5, "clicking it lists the five pieces beneath (" .. rowsAfter .. " rows, was " .. rowsBefore .. ")")
curioRow:GetScript("OnClick")(curioRow, "LeftButton")
check(ns.uiExpandedTokenID == nil, "clicking again closes it")
-- a slot token: the token row with its piece beneath, or the piece in its place
local function TokenRow(id)
    for _, it in ipairs(ns.UI.Pools.raidItems) do
        if it:IsShown() and it.eval and it.eval.token and it.eval.token.itemID == id then return it end
    end
end
local legsRow = TokenRow(1010)
check(legsRow and legsRow.Name:GetText():find("Legguard Token", 1, true) and legsRow.Arrow:IsShown() and legsRow.eval.pieces and #legsRow.eval.pieces == 1,
    "a slot token shows as the token with an arrow")
local before = 0
for _, it in ipairs(ns.UI.Pools.raidItems) do if it:IsShown() then before = before + 1 end end
legsRow:GetScript("OnClick")(legsRow, "LeftButton")
local after, shownPiece = 0, nil
for _, it in ipairs(ns.UI.Pools.raidItems) do
    if it:IsShown() then
        after = after + 1
        if it.eval and it.eval.item.itemID == 7007 and not it.eval.pieces then shownPiece = it end
    end
end
check(ns.uiExpandedTokenID == 1010 and after == before + 1 and shownPiece and shownPiece.Name:GetText():find("Venom Legguards", 1, true), "clicking it shows the legguards beneath")
check(shownPiece.VC:IsShown() and legsRow.VC:IsShown(), "slot token rows keep the Voidcore star")
local curioRow2
for _, it in ipairs(ns.UI.Pools.raidItems) do if it:IsShown() and it.eval and it.eval.token and it.eval.token.itemID == 270909 then curioRow2 = it end end
check(curioRow2 and not curioRow2.VC:IsShown(), "the Curio row has no Voidcore star")

-- weight profiles follow equipment sets; the box under Ask Mr. Robot's window
do
    _G.EQUIPPED_SET = nil
    _G.C_EquipmentSet = {
        GetEquipmentSetIDs = function() return { 1, 2 } end,
        GetEquipmentSetInfo = function(id)
            if id == 1 then return "Raid", 1, 1, EQUIPPED_SET == "Raid" end
            if id == 2 then return "M+", 1, 2, EQUIPPED_SET == "M+" end
        end,
    }
    local activeBefore = ns:GetActiveStatProfile()
    local n0 = #ns:GetStatProfiles()
    local raidProfile, raidIndex = ns:ImportPawnString('( Pawn: v1: "Erunak - Restoration Raid": Class=Shaman, Spec=Restoration, Intellect=80, CritRating=70, HasteRating=60, Versatility=40, MasteryRating=20 )')
    local mplusProfile, mplusIndex = ns:ImportPawnString('( Pawn: v1: "Erunak - Restoration M+": Class=Shaman, Spec=Restoration, Intellect=80, HasteRating=60, MasteryRating=50, CritRating=30, Versatility=20 )', "Keys")
    raidProfile.setName, mplusProfile.setName = nil, nil
    check(raidIndex == 1 and mplusIndex == n0 + 1 and ns:StatProfileSet(raidProfile) == "Raid" and ns:StatProfileSet(mplusProfile) == "M+",
        "profiles match sets by the end of their names: 'Erunak - Restoration Raid' -> Raid (replacing the old Raid weights), the Pawn name '... M+' -> M+")
    _G.EQUIPPED_SET = "M+"
    check(ns:FollowBuild() == mplusIndex and ns:GetActiveStatProfile() == mplusIndex, "wearing the M+ set switches to its profile")
    _G.EQUIPPED_SET = "Raid"
    ns:ScanGear()
    local followed = ns:StatProfileSet(ns:GetStatProfiles()[ns:GetActiveStatProfile()])
    check(followed == "Raid" and ns:GetActiveStatProfile() ~= mplusIndex, "a gear change while wearing the Raid set switches to a profile that follows Raid")
    local stays = ns:GetActiveStatProfile()
    ns:SetActiveStatProfile(mplusIndex)
    ns:ScanGear()
    check(ns:GetActiveStatProfile() == mplusIndex, "a profile picked by hand stays through gear changes while the set worn is the same")
    check(ns:FollowBuild(true) == stays and ns:GetActiveStatProfile() == stays, "forced, it follows the set again")
    _G.EQUIPPED_SET = nil
    check(ns:FollowBuild() == nil and ns:GetActiveStatProfile() == stays, "no set worn: the profile stays")

    -- talent loadouts: the build selected for the spec beats the set worn
    LOADOUTS[72] = { { id = 101, name = "Raid" }, { id = 102, name = "M+" } }
    check(select(2, ns:StatProfileLoadout(raidProfile)) == "Raid" and select(2, ns:StatProfileLoadout(mplusProfile)) == "M+",
        "profiles match loadouts by the end of their names too")
    SELECTED_LOADOUT[72] = 102
    _G.EQUIPPED_SET = "Raid"
    check(ns:FollowBuild() == mplusIndex and ns:GetActiveStatProfile() == mplusIndex, "the M+ loadout selected while wearing the Raid set: the M+ profile wins")
    SELECTED_LOADOUT[72] = 101
    ns.eventFrame._scripts.OnEvent(ns.eventFrame, "TRAIT_CONFIG_UPDATED", 1)
    RunTimers()
    check(ns:GetActiveStatProfile() ~= mplusIndex and ns:StatProfileLoadout(ns:GetStatProfiles()[ns:GetActiveStatProfile()]) == 101,
        "loading the Raid loadout switches to a profile that follows it")
    local pasted = ns:ImportPawnString('( Pawn: v1: "Erunak - Something Else": Class=Shaman, Spec=Restoration, Intellect=80, HasteRating=61, MasteryRating=50, CritRating=30, Versatility=20 )')
    check(pasted and pasted.loadoutID == 101 and select(2, ns:StatProfileLoadout(pasted)) == "Raid", "a string pasted with no matching name follows the loadout selected when it was pasted")
    ns:DeleteStatProfile((ns:FindStatProfile("Erunak - Something Else")))
    SELECTED_LOADOUT[72] = nil
    LOADOUTS[72] = nil
    _G.EQUIPPED_SET = nil
    ns:FollowBuild()
    ns:DeleteStatProfile(mplusIndex)
    ns:SetActiveStatProfile(activeBefore)
    -- the AMR box, with the setups the AMR addon imported
    _G.AskMrRobot = { Show = function() end, Hide = function() end, db = { char = { GearSetups = {
        { Label = "Restoration Raid", SpecSlot = 1, Gear = { [1] = { id = 7001 }, [5] = { id = 5005 } }, TalentConfigId = "101" },
        { Label = "Restoration M+", SpecSlot = 1, Gear = { [1] = { id = 5001 } } },
        { Label = "Elemental", SpecSlot = 3, Gear = {} },
    } } } }
    local setups = ns:AmrSetups()
    check(#setups == 3 and setups[1].label == "Restoration Raid" and setups[1].gear[1] == 7001 and setups[1].loadoutID == 101 and setups[2].loadoutID == nil,
        "the setups AMR imported are read with their gear and talent loadout")
    _G.AmrUiFrame1 = NewWidget("Frame", "AmrUiFrame1"); AmrUiFrame1:SetSize(800, 600); AmrUiFrame1:Show()
    local amrBox = ns:ShowAmrBox()
    check(amrBox and amrBox:IsShown() and amrBox.Edit and amrBox.Import, "the Pawn box appears under AMR's window")
    local before = #ns:GetStatProfiles()
    amrBox.Edit:SetText('( Pawn: v1: "Erunak - Restoration Raid": Class=Shaman, Spec=Restoration, Intellect=80, CritRating=70, HasteRating=60, Versatility=40, MasteryRating=20 )')
    amrBox.Import:GetScript("OnClick")(amrBox.Import)
    local saved = ns:GetStatProfiles()[1]
    check(#ns:GetStatProfiles() == before and saved.weights.CRIT == 70 and amrBox.Result:GetText():find("for the Restoration Raid setup", 1, true),
        "pasting a Pawn string there replaces that setup's profile (" .. tostring(amrBox.Result:GetText()) .. ")")
    check(saved and saved.amrSetup == "Restoration Raid" and saved.setName == "Restoration Raid" and saved.gear[1].itemID == 7001, "the profile's gear is the setup's gear, its set the setup's label")
    check(saved.loadoutID == 101, "and its talent loadout the setup's")
    local diff = ns:StatProfileGearDiff(saved)
    check(#diff >= 1 and diff[1].slotID == 1 and diff[1].from.itemID == 7001 and diff[1].to.itemID == 5001, "wearing the old helm instead of the setup's counts as changed gear")
    check(amrBox.Result:GetText():find("Still without weights:", 1, true) and amrBox.Result:GetText():find("Restoration M+", 1, true) and not amrBox.Result:GetText():find("Elemental", 1, true),
        "the box lists this spec's setups still without weights")
    ns:ImportPawnString(PAWN)
    ns:SetActiveStatProfile(activeBefore)
    AmrUiFrame1:Hide()
    check(not amrBox:IsShown(), "the box hides with AMR's window")
    _G.AmrUiFrame1 = nil
    _G.AskMrRobot = nil
    _G.C_EquipmentSet = nil
end

-- Voidcore: the roll pools read from the Voidcache tooltips
do
ns:ClearVoidcorePools()
local ejTierBefore = ej.tier
local vcSources = ns:VoidcoreSources()
check(#vcSources > 0 and not vcSources[1].tooltipRead and vcSources[1].ready and vcSources[1].count > 0, "pools come from the loot table at once; the game's lists are queued")
RunTimers()
vcSources = ns:VoidcoreSources()
local vcByName = {}
for _, src in ipairs(vcSources) do vcByName[src.name] = src end
local twinS, mrS, bvS, krS = vcByName["The Twin Fangs"], vcByName["Murder Row"], vcByName["The Blinding Vale"], vcByName["Kings' Rest"]
check(twinS and twinS.ready and twinS.count == 3 and twinS.context == 6 and twinS.kind == "boss", "the Twin Fangs' Mythic pool holds three items (dash, en dash and spaced markers)")
check(JOURNAL_TOUCHED[3002] == 16 and JOURNAL_TOUCHED[1304] == 8 and ej.tier == ejTierBefore, "each source's journal loot was asked for at its difficulty, the journal's tier put back")
check(ns.VoidcacheListedName("Item Level 318") == nil and ns.VoidcacheListedName("Contains one of the following items:") == nil, "header lines are not items")
local inPool = {}
for _, e in ipairs(twinS.items) do inPool[(e.token or e.item).itemID] = true end
check(inPool[1008] and inPool[1009] and inPool[270912] and not inPool[1010] and not inPool[270909], "pool items matched by name, the token by its token name; the rolled token and the Curio absent")
check(twinS.usable == 3 and twinS.chance == 1 and twinS.targets == (ns:IsVoidcoreTarget(1008) and 1 or 0), "every pool item would be a Myth roll upgrade (" .. twinS.usable .. "/" .. twinS.count .. ")")
check(twinS.ideal <= twinS.usable and twinS.idealChance <= twinS.chance, "ideal rolls are a subset of usable ones (" .. twinS.ideal .. "/" .. twinS.usable .. ")")
check(ns.IdealRoll(ns, { fit = 0.9 }, { class = ns.UPGRADE_TRACK }) and not ns.IdealRoll(ns, { fit = 0.3 }, { class = ns.UPGRADE_TRACK })
    and ns.IdealRoll(ns, {}, { class = ns.UPGRADE_TRACK }) and ns.IdealRoll(ns, { fit = 0.6, equippedFit = 0.5 }, { class = ns.UPGRADE_TRACK })
    and ns.IdealRoll(ns, { fit = 0.3 }, { class = ns.UPGRADE_TRACK, valueGain = 12 }) and not ns.IdealRoll(ns, { fit = 0.9 }, { class = ns.UPGRADE_NONE }),
    "ideal: fits at 75%, or beats the worn piece, or gains weighted value; never a non-upgrade")
check(twinS.ev > 0 and twinS.best and twinS.bestValue >= twinS.ev and twinS.value / twinS.count == twinS.ev and twinS.bestValue <= 30 * 1.25 * 1.25 * 3,
    "the expected gain is the mean roll value, empty slots capped; the best item is named (" .. tostring(twinS.best and twinS.best.item.name) .. " +" .. twinS.bestValue .. ")")
local ringEval, chestEval
for _, e in ipairs(twinS.items) do if e.item.itemID == 1009 then ringEval = e elseif e.item.itemID == 1008 then chestEval = e end end
local ringValue = ns.RollValue(ns, ringEval)
local fitMult = ringEval.rollIdeal and 1.25 or ((ringEval.fit or 1) < 0.5 and 0.5 or 1)
check(ringValue > 0 and ringEval.rollValue == ringValue and math.min(30, ringEval.voidcore.potentialGain or 0) * 0.75 * fitMult * (ns:IsVoidcoreTarget(1009) and 3 or 1) == ringValue,
    "a ring's roll value is its fully upgraded gain (capped) at the ring budget, times the stat fit (" .. ringValue .. ")")
ns:SetVoidcoreTarget(1009, true)
local targeted = ns.RollValue(ns, ringEval)
check(targeted == ringValue * 3, "a Voidcore target counts three times")
ns:SetVoidcoreTarget(1009, false)
local sp = ns:SetProgress()
check(sp.known and sp.total == 5 and sp.worn == 0 and sp.nextBonus == 2 and sp.need == 2 and sp.charges == 1, "set progress: none of the five worn, the 2-piece needs 2, one Catalyst charge")
check(ns:IsCatalystCandidate(chestEval) and not ns:IsCatalystCandidate(ringEval), "a chest is a Catalyst candidate, a ring is not")
local oldHead = ns.gear[1].itemID
ns.gear[1].itemID = 7001
check(ns:SetProgress().worn == 1 and ns:SetProgressText() == "Set 1/5, 2-piece needs 1, 1 Catalyst charge", "a worn set piece counts (" .. tostring(ns:SetProgressText()) .. ")")
ns.gear[1].itemID = oldHead
check(mrS and mrS.ready and mrS.count == 2 and mrS.context == 16 and mrS.level == ns.db.targetKey, "Murder Row read at the selected key (+" .. tostring(mrS and mrS.level) .. "), two items left")
local mrPool = {}
for _, e in ipairs(mrS.items) do mrPool[e.item.itemID] = true end
check(mrPool[1001] and mrPool[1002] and not mrPool[1003], "the rolled sword is out of the dungeon's pool")
check(bvS and bvS.ready and bvS.count == 2 and VOIDCACHE_LOADING[279619] == 0, "read again until the client lists it twice alike: the Blinding Vale holds two (lines after the header, no markers)")
check(vcSources[1].ev >= vcSources[2].ev and (vcSources[#vcSources].missing or vcSources[#vcSources].ready), "sources ordered by the expected value of a roll, unknown caches last")
check(krS and krS.ready and krS.gaveUp and not krS.tooltipRead and krS.count == 2, "a cache the client never lists stays on the loot table (Kings' Rest: 2 items)")
-- the client says the last read resolved: read again at once, the list is there
_G.VOIDCACHE_RESOLVED_FOR = 279621
ev(ns.eventFrame, "TOOLTIP_DATA_UPDATE", LAST_VOIDCACHE_INSTANCE)
krS = nil
for _, src in ipairs(ns:VoidcoreSources()) do if src.name == "Kings' Rest" then krS = src end end
check(krS and krS.tooltipRead and not krS.gaveUp and krS.pool.resolved == 1 and krS.count == 1 and #krS.items == 0 and ns:IsRolled(krS, 1008) and ns:IsRolled(krS, 1005),
    "a data update fetches the game's list at once; loot it no longer names is recorded as rolled (Kings' Rest)")
-- a loot-table pool: marks by hand, and a refill once everything is rolled
local nymS
for _, src in ipairs(ns:VoidcoreSources()) do if src.name == "Nymrissa Wavecaller" then nymS = src end end
check(nymS and not nymS.tooltipRead and nymS.count == 2 and nymS.total == 2, "the lair's pool comes from the loot table: two items")
ns:ToggleRolled(nymS, 1003)
for _, src in ipairs(ns:VoidcoreSources()) do if src.name == "Nymrissa Wavecaller" then nymS = src end end
check(nymS.count == 1 and #nymS.rolledItems == 1 and ns:IsRolled(nymS, 1003) and ns.cdb.rolled[ns:GetLootSpecID()]["b3010:mythic"][1003], "marking the sword rolled takes it out, per spec and pool")
ns:ToggleRolled(nymS, 1002)
for _, src in ipairs(ns:VoidcoreSources()) do if src.name == "Nymrissa Wavecaller" then nymS = src end end
check(nymS.count == 2 and nymS.refilled and not ns:IsRolled(nymS, 1003), "with everything rolled the pool refills")
-- a roll result records its item against the prompt's source
_G.GetSpellConfirmationPromptsInfo = function() return { { displayItemID = 274708, itemContext = 5, treasureContextLevel = 0 } } end
ns:NoteRollPrompt()
_G.GetSpellConfirmationPromptsInfo = nil
ev(ns.eventFrame, "BONUS_ROLL_RESULT", "item", "|cffa335ee|Hitem:1002::::::::80:72::::::|h[Trinket of Testing]|h|r", 1, 72)
RunTimers()
local nymH = ns:VoidcoreSourceFor(274708, 5, nil)
check(nymH and nymH.diffKey == "heroic" and ns:IsRolled(nymH, 1002) and nymH.count == 1, "a roll result takes its item out of the prompted source's pool (Heroic lair)")
ns:SetRolled(nymH, 1002, false)
ev(ns.eventFrame, "TOOLTIP_DATA_UPDATE", 99999)
RunTimers()
ns:VoidcoreSources(); RunTimers()
local readsNow = VOIDCACHE_READS
ns:VoidcoreSources()
RunTimers()
check(VOIDCACHE_READS == readsNow, "ready pools are not read again")
ns:RetryEmptyVoidcorePools()
ns:VoidcoreSources()
check(ns.voidcorePools["279623:16:" .. ns.db.targetKey].ready and not ns.voidcorePools["279621:16:" .. ns.db.targetKey].ready, "opening the tab keeps the lists that were read and asks again for the ones that never came")
RunTimers()
check(ns:VoidcoreSummary(twinS) == string.format("%d ideal, 3 of 3 usable (100%%), +%.1f per roll", twinS.ideal, twinS.ev) .. (twinS.targets > 0 and ", 1 target" or ""), "summary line (" .. tostring(ns:VoidcoreSummary(twinS)) .. ")")
ns:VoidcoreSourceFor(278289, 5, nil); RunTimers()
local hs = ns:VoidcoreSourceFor(278289, 5, nil)
check(hs and hs.diffKey == "heroic" and hs.count == 3 and hs.result.ctx.difficulty == "heroic", "a cache at another difficulty is evaluated at that difficulty")
ns:VoidcoreSourceFor(279623, 16, 8); RunTimers()
local ds = ns:VoidcoreSourceFor(279623, 16, 8)
check(ds and ds.kind == "dungeon" and ds.key == 8 and ds.ready and ds.count == 2, "a dungeon cache is read at the roll's key level (+8)")
_G.GetSpellConfirmationPromptsInfo = function() return { { displayItemID = 278289, itemContext = 5, treasureContextLevel = 0 } } end
local rollText = ns:RollWindowText()
check(rollText and rollText:find("^The Twin Fangs: %d+ ideal, 3 of 3 usable"), "the roll window line names the source and its odds (" .. tostring(rollText) .. ")")
_G.GetSpellConfirmationPromptsInfo = nil
ev(ns.eventFrame, "BONUS_ROLL_RESULT", "item", "|Hitem:1009|h", 1, 72)
RunTimers()
check(next(ns.voidcorePools) == nil, "a roll clears the pools so they are read again")
-- the tab
ns:ShowPage("voidcore")
local vcPage = SlotFillerFrame.Pages.voidcore
check(ns:CurrentPage() == "voidcore" and SlotFillerFrame.Toolbar:IsShown() and vcPage.Strip.Text:GetText():find("2 Voidcores", 1, true), "Voidcore tab shown with the toolbar and the Voidcore count")
for _ = 1, 6 do RunTimers(); ns:RefreshWindow() end
local firstRow = ns.UI.Pools.rollRows[1]
check(firstRow and firstRow.source and firstRow.source.name == ns:VoidcoreSources()[1].name
    and firstRow.Pool:GetText():find(tostring(firstRow.source.ideal) .. "|r|cff888888/" .. tostring(firstRow.source.usable), 1, true) and firstRow.EGain:GetText():find("+", 1, true),
    "rows in the ranked order with ideal/usable and the expected gain")
check(vcPage.Strip.Text:GetText():find("Set 0/5", 1, true) and vcPage.Strip.Text:GetText():find("1 Catalyst charge", 1, true), "the strip shows set progress and Catalyst charges")
local twinRow
for _, r in ipairs(ns.UI.Pools.rollRows) do if r:IsShown() and r.source and r.source.name == "The Twin Fangs" then twinRow = r end end
twinRow:GetScript("OnClick")(twinRow, "LeftButton")
local shownItems = 0
for _, it in ipairs(ns.UI.Pools.rollItems) do if it:IsShown() and it.eval then shownItems = shownItems + 1 end end
local rolledRows = 0
for _, it in ipairs(ns.UI.Pools.rollItems) do if it:IsShown() and it.eval and it.Gain:GetText() == "|cff888888rolled|r" then rolledRows = rolledRows + 1 end end
check(ns.uiExpandedRollKey == 278289 and shownItems == 4 and rolledRows == 1 and ns.UI.Pools.rollItems[1].Gain:GetText():find("|cff", 1, true),
    "clicking a source lists its pool with the roll verdicts, the rolled legs token dimmed below")
local tipLinks2, tipLines2 = {}, {}
GameTooltip.SetHyperlink = function(_, l) tipLinks2[#tipLinks2 + 1] = l end
GameTooltip.AddLine = function(_, t) tipLines2[#tipLines2 + 1] = tostring(t) end
local ringRow
for _, it in ipairs(ns.UI.Pools.rollItems) do if it:IsShown() and it.eval and it.eval.item.itemID == 1009 then ringRow = it end end
ns:ShowItemTooltip(ringRow)
local rollShown, rollVerdict = false, false
for _, l in ipairs(tipLines2) do
    if l:find("Shown as a Voidcore roll", 1, true) then rollShown = true end
    if l:find("Voidcore roll|r:", 1, true) then rollVerdict = true end
end
check(ringRow.roll and rollShown and rollVerdict and BonusOfLink(tipLinks2[1]) == BonusFor(5, 6), "a pool item's tooltip shows the item as the Myth 6/6 roll, with the roll's verdict (" .. tostring(tipLinks2[1]) .. ")")
do
    local chestRow
    for _, it in ipairs(ns.UI.Pools.rollItems) do if it:IsShown() and it.eval and it.eval.item.itemID == 1008 then chestRow = it end end
    tipLines2 = {}
    ns:ShowItemTooltip(chestRow)
    local catalystLine = false
    for _, l in ipairs(tipLines2) do if l:find("Catalyst: can become a set piece", 1, true) and l:find("1 charge", 1, true) then catalystLine = true end end
    check(catalystLine, "a tier-slot item's tooltip says the Catalyst can make it a set piece, with the charges")
end
GameTooltip.SetHyperlink, GameTooltip.AddLine = nil, nil
check(SlotFillerFrame.SettingsButton ~= nil, "the settings cog sits in the title bar")
ns:ToggleOptionsPanel()
check(ns:CurrentPage() == "settings", "the cog opens Settings")
ns:ToggleOptionsPanel()
check(ns:CurrentPage() == "voidcore", "and again returns to the Voidcore tab")
ns:PrintVoidcoreDiagnostics()
ns.uiExpandedRollKey = nil
ns:ShowPage("raid")
ns.uiExpandedEncounterID = 3002
ns:RefreshWindow()
end
-- the token row's tooltip is the token's own; the piece row's is the piece
local tipLinks, tipLines = {}, {}
GameTooltip.SetHyperlink = function(_, l) tipLinks[#tipLinks + 1] = l end
GameTooltip.AddLine = function(_, t) tipLines[#tipLines + 1] = tostring(t) end
ns:ShowItemTooltip(legsRow)
check(tipLinks[1] == legsRow.eval.token.link and tipLinks[1]:find("Legguard Token", 1, true), "the token row shows the token's own tooltip")
local turns, stats = false, false
for _, l in ipairs(tipLines) do
    if l:find("turns into", 1, true) and l:find("Venom Legguards", 1, true) then turns = true end
    if l:find("^Stats:") then stats = true end
end
check(turns and not stats, "it says what the token turns into and shows no stats of its own")
tipLinks, tipLines = {}, {}
ns:ShowItemTooltip(shownPiece)
check(tipLinks[1] and tipLinks[1]:find("Venom Legguards", 1, true), "the piece row shows the piece")
GameTooltip.SetHyperlink, GameTooltip.AddLine = nil, nil
ns.uiExpandedTokenID = nil
ns.db.nestTokens = false
ns:RefreshWindow()
legsRow = TokenRow(1010)
check(legsRow and legsRow.Name:GetText():find("Venom Legguards", 1, true) and not legsRow.Arrow:IsShown(), "with the setting off the piece takes the token's place")
curioRow = nil
for _, it in ipairs(ns.UI.Pools.raidItems) do if it:IsShown() and it.eval and it.eval.token and it.eval.token.itemID == 270909 then curioRow = it end end
check(curioRow and curioRow.Arrow:IsShown() and curioRow.Name:GetText():find("Curio", 1, true), "the any-slot token still opens into its pieces")
ns.db.nestTokens = true
ns.uiExpandedEncounterID = nil
ns:SetRaidDifficulty("heroic")
RunTimers()
ns.db.gearSource = "raid"
ns:ShowPage("gear")
local gearPage = SlotFillerFrame.Pages.gear
check(gearPage.Strip.Tabs.selectedTabID == "raid" and gearPage.Strip.Diff:GetText() == "Heroic", "Gear strip shows the source and the raid difficulty")
ns.db.gearSource = "both"
-- the stars and right-click toggle both ways
ns:ShowPage("dungeons")
ns.uiExpandedMapID = 587
ns:RefreshWindow()
local itemRow = ns.UI.Pools.dungeonItems[1]
check(itemRow and itemRow.eval, "an expanded drop row is available")
local id = itemRow.eval.item.itemID
itemRow.Star.GetParent = function() return itemRow end -- the stub tracks no parents
itemRow.VC.GetParent = function() return itemRow end
itemRow.Star:GetScript("OnClick")(itemRow.Star)
check(ns:GetItemState(id) == "want", "wanted star: first click wants the item")
itemRow.Star:GetScript("OnClick")(itemRow.Star)
check(ns:GetItemState(id) == nil, "wanted star: second click removes it")
itemRow.VC:GetScript("OnClick")(itemRow.VC)
check(ns:IsVoidcoreTarget(id), "Voidcore star: first click marks the target")
itemRow.VC:GetScript("OnClick")(itemRow.VC)
check(not ns:IsVoidcoreTarget(id), "Voidcore star: second click unmarks it")
ns:CycleItemState(id)
check(ns:GetItemState(id) == "exclude", "right-click excludes")
ns:CycleItemState(id)
check(ns:GetItemState(id) == nil, "right-click again includes")
-- an open list keeps its order while you star things; reopening applies the new order
ns.uiExpandedMapID = 584
ns:RefreshWindow()
local pool = ns.UI.Pools.dungeonItems
local before = {}
for i = 1, 4 do before[i] = pool[i].eval and pool[i].eval.item.itemID end
check(before[3] == 1004 and before[4] == 1006, "Blinding Vale opens with the non-upgrades last (" .. table.concat(before, ",") .. ")")
ns:SetItemState(1004, "want")
RunTimers()
check(ns:ResultForDungeon(ns.dungeonByMapID[584]).items[1].item.itemID == 1004, "the wanted sword now sorts first in the results")
local after = {}
for i = 1, 4 do after[i] = pool[i].eval and pool[i].eval.item.itemID end
check(after[3] == 1004 and after[1] == before[1], "but the open list keeps its order (" .. table.concat(after, ",") .. ")")
ns.uiExpandedMapID = nil
ns:RefreshWindow()
ns.uiExpandedMapID = 584
ns:RefreshWindow()
check(pool[1].eval.item.itemID == 1004, "reopening the list applies the new order")
ns:SetItemState(1004, nil)
RunTimers()
ns.uiExpandedMapID = nil

-- IO tab
ns:SetRatingMaxKey(nil)
ns:SetRatingTarget(1000)
local mapInfoBeforeIO = REQUESTED_MAPINFO or 0
ns:ShowPage("io")
check(ns:CurrentPage() == "io" and not SlotFillerFrame.Toolbar:IsShown(), "IO tab shown without the loot toolbar")
check((REQUESTED_MAPINFO or 0) == mapInfoBeforeIO + 1, "opening the IO tab requests map info once")
ns:RefreshWindow()
check((REQUESTED_MAPINFO or 0) == mapInfoBeforeIO + 1, "refreshing the IO tab requests nothing")
local ioPage = SlotFillerFrame.Pages.io
check(ioPage.Head.Rating:GetText():find("626", 1, true) ~= nil, "IO header shows the rating")
check(ioPage.Head.TargetTabs.selectedTabID == "custom" and ioPage.Head.TargetPlus:IsShown() and ioPage.Head.CustomTab.Text:GetText() == "1000",
    "a custom target shows on the Custom tab with its stepper")
check(ioPage.Head.RunsTabs.selectedTabID == 3 and ioPage.Head.RunsTabs.Tabs[2]:IsShown() and not ioPage.Head.RunsTabs.Tabs[3]:IsShown(),
    "Runs strip: one tab per plan, the easiest selected")
check(ioPage.Head.KeyText:GetText():find("+12", 1, true) ~= nil, "Max key box shows the automatic cap")
check(ioPage.Status:GetText():find("^%+374 to go") and ioPage.Status:GetText():find("3 runs for +379 = ", 1, true) and ioPage.Status:GetText():find("1005|r", 1, true),
    "status line shows the distance, the plan's total and the rating at the end (" .. tostring(ioPage.Status:GetText()) .. ")")
ns:SetRatingRuns(2)
check(ioPage.Head.RunsTabs.selectedTabID == 2, "Runs strip follows the selected plan")
local ioRow = ns.UI.Pools.ioRows[1]
check(ioRow and ioRow.mapID == 249 and ioRow.run and ioRow.run.level == 12, "planned runs come first, highest key on top")
ioRow:GetScript("OnClick")(ioRow, "RightButton")
check(ns:IsDungeonAvoided(249) and ns.UI.Pools.ioRows[1].mapID ~= 249, "right-click avoids the dungeon and drops it to the bottom")
local avoidedRow = ns.UI.Pools.ioRows[3]
avoidedRow:GetScript("OnClick")(avoidedRow, "RightButton")
check(not ns:IsDungeonAvoided(249), "right-click again brings it back")
ns.uiExpandedRatingMapID = 249
ns:RefreshWindow()
check(#ns.UI.Pools.ioLadder == 12 and ns.UI.Pools.ioLadder[1].Level:GetText():find("+2", 1, true) and ns.UI.Pools.ioLadder[12].Level:GetText():find("+13", 1, true),
    "key ladder from +2 up to one past the planned +12 (" .. #ns.UI.Pools.ioLadder .. " rows)")
ns.db.ioSort = "gain"
ns:RefreshWindow()
ns.db.ioSort = "best"
ns:RefreshWindow()
check(ns.UI.Pools.ioRows[1].mapID == 249 and ns.UI.Pools.ioRows[2].mapID == 584, "sorting by best puts the lowest score first")
ns.db.ioSort = "plan"
-- the plan ordered by gear drops
check(ioPage.Strip.Order.Text:GetText():find("Rating gained", 1, true) ~= nil and ioPage.Strip.Note:GetText() == "", "order dropdown shows rating gained by default")
local orderEntries = ioPage.Strip.Order.entries()
check(#orderEntries == 2 and orderEntries[1].checked and not orderEntries[2].checked, "order menu: rating gained checked")
ns.db.ioSort = "best"
orderEntries[2].onClick()
check(ns:RatingOrder() == "gear" and ns.db.ioSort == "plan" and ioPage.Strip.Order.Text:GetText():find("Gear drops", 1, true) ~= nil,
    "picking gear drops sets the order and returns to plan sorting")
local g1, g2, g3 = ns.UI.Pools.ioRows[1], ns.UI.Pools.ioRows[2], ns.UI.Pools.ioRows[3]
check(g1.mapID == 584 and g1.gear.upgrades == 2 and g2.mapID == 249 and g2.gear.upgrades == 1,
    "by gear the planned +11 with two drops comes before the planned +12 with one")
check(g3.mapID == 587 and g3.gear.upgrades == 3 and not g3.run, "the unplanned dungeon stays below the plan even with more drops")
check(g1.Name:GetText():find("Vale  |cff", 1, true) and g1.Name:GetText():find("2|r", 1, true) and g1.gearLevel == 11, "the drop count sits next to the name, judged at the planned key")
check(ioPage.Strip.Note:GetText() ~= "", "the strip explains the count")
ns:SetRatingOrder("rating")
check(ns.UI.Pools.ioRows[1].mapID == 249 and ioPage.Strip.Note:GetText() == "", "back to rating order: highest key first, no note")
-- rating on keystone tooltips
local kt3 = { lines = {}, AddLine = function(self, text) table.insert(self.lines, text) end, Show = function() end }
ns:AddKeystoneTooltip(kt3, 587, 12)
check(kt3.lines[#kt3.lines]:find("Rating: 326 -> 365 (+39) if timed", 1, true) ~= nil, "keystone tooltip: rating if timed (" .. tostring(kt3.lines[#kt3.lines]) .. ")")
local kt4 = { lines = {}, AddLine = function(self, text) table.insert(self.lines, text) end, Show = function() end }
ns:AddKeystoneTooltip(kt4, 587, 9)
check(kt4.lines[#kt4.lines]:find("no gain at +9", 1, true) ~= nil, "keystone tooltip: a key below the best gains nothing")
ns.db.ioBadge = false
local kt5 = { lines = {}, AddLine = function(self, text) table.insert(self.lines, text) end, Show = function() end }
ns:AddKeystoneTooltip(kt5, 587, 12)
check(not kt5.lines[#kt5.lines]:find("Rating:", 1, true), "rating lines off with the setting")
ns.db.ioBadge = true
ns:SetRatingTarget(nil)
check(ioPage.Head.TargetTabs.selectedTabID == "2000" and not ioPage.Head.TargetPlus:IsShown(), "automatic target: milestone tab, no stepper")
check(ioPage.Head.RunsTabs.Tabs[1].Text:GetText() == "Max" and ioPage.Status:GetText():find("everywhere reaches", 1, true) ~= nil,
    "out of reach under the cap: the Max tab and the status line say so")
ns:SetRatingRuns(nil)
ns.uiExpandedRatingMapID = nil
ns:ToggleOptionsPanel()
check(ns:CurrentPage() == "settings", "Settings tab shown")
ns:RefreshSettings()
local settings = SlotFillerFrame.Pages.settings
check(settings.StatModeTabs.selectedTabID == "auto" and settings.statHint:GetText() == "From your equipped gear", "Settings shows Auto and where the order comes from")
local before = { unpack((ns:GetStatPriority())) }
local chip = settings.statButtons[1]
chip:GetScript("OnClick")(chip, "RightButton")
local after = ns:GetStatPriority()
check(ns:GetStatMode() == "manual" and after[1] == before[2] and after[2] == before[1], "right-clicking a stat moves it right and starts a manual order")
check(settings.StatModeTabs.selectedTabID == "manual" and settings.statHint:GetText():find("^Left%-click"), "Settings switches to Manual and shows the click hint")
chip:GetScript("OnClick")(chip, "LeftButton")
check(ns:GetStatPriority()[1] == after[1], "the leftmost stat cannot move further left")
ns:SetStatPriority(nil)
ns:SetStatMode("auto")
ns:ToggleOptionsPanel()
check(ns:CurrentPage() == "io" and not SlotFillerFrame.Toolbar:IsShown(), "the cog again: back to the IO tab it came from (" .. ns:CurrentPage() .. ")")
ns:HideWindow(true)
check(not ns:IsWindowShown(), "window hidden")

-- free mode: "Move with Dungeons & Raids" anchors the window to the Group Finder
local sf = SlotFillerFrame
local points = {}
sf.SetPoint = function(self, ...) points[#points + 1] = { ... } end
sf.GetLeft = function() return 100 end
sf.GetTop = function() return 500 end
PVEFrame.GetLeft = function() return 300 end
PVEFrame.GetTop = function() return 600 end
UIParent.GetTop = function() return 768 end
PVEFrame._shown = true
ns.db.anchorSide = "free"
ns.db.freeFollow = true
ns:RememberFreePosition()
check(ns.db.freeOffset and ns.db.freeOffset.x == -200 and ns.db.freeOffset.y == -100, "offset from the Group Finder remembered")
check(ns.db.freePos and ns.db.freePos.x == 100 and ns.db.freePos.y == 500 - 768, "screen position remembered too")
ns:AnchorWindow()
local last = points[#points]
check(last and last[2] == PVEFrame and last[4] == -200 and last[5] == -100, "free window anchored to the Group Finder")
ns.db.freeFollow = false
ns:AnchorWindow()
last = points[#points]
check(last and last[2] == UIParent and last[4] == 100 and last[5] == 500 - 768, "without the option it sits on the screen")
ns.db.freeFollow = true
PVEFrame._shown = false
ns:AnchorWindow()
last = points[#points]
check(last and last[2] == UIParent, "with the Group Finder closed it sits on the screen")
ns.db.freeOffset = nil
PVEFrame._shown = true
ns:AnchorWindow()
last = points[#points]
check(last and last[2] == PVEFrame and ns.db.freeOffset and ns.db.freeOffset.x == -200, "first time next to the Group Finder takes the offset from where the window is")
sf.SetPoint, sf.GetLeft, sf.GetTop, PVEFrame.GetLeft, PVEFrame.GetTop, UIParent.GetTop = nil, nil, nil, nil, nil, nil
ns.db.anchorSide, ns.db.freeFollow, ns.db.freeOffset, ns.db.freePos = "left", false, nil, nil
ns:PrintStatus()

-- slash commands
SlashCmdList.SLOTFILLER("key 8")
RunTimers()
check(ns.db.targetKey == 8, "/sf key 8")
SlashCmdList.SLOTFILLER("help")

print(failures == 0 and "\nALL CHECKS PASSED" or ("\n" .. failures .. " CHECK(S) FAILED"))
os.exit(failures == 0 and 0 or 1)
