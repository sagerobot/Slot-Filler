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
_G.Enum = { ItemClass = { Weapon = 2, Armor = 4 }, ItemSlotFilterType = { NoFilter = 15 } }
_G.DifficultyUtil = { ID = { DungeonChallenge = 8, DungeonMythic = 23 } }
_G.ScrollBoxListMixin = { Event = { OnUpdate = "OnUpdate" } }
_G.Settings = nil
_G.SlashCmdList = {}
_G.issecretvalue = function() return false end

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

-- specialization (12.x: C_SpecializationInfo for spec index/info, globals for the rest)
_G.C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function(i) return 72, "Fury", "", 132347 end,
    GetNumSpecializationsForClassID = function() return 3 end,
}
_G.GetLootSpecialization = function() return 0 end
_G.GetSpecializationInfoByID = function(id) return id, id == 72 and "Fury" or "Arms", "", 132347 end
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
    [1008] = { "INVTYPE_CHEST", 4, 4, 1, "Chest of Testing" },
    [2001] = { nil, 12, 0, 1, "Quest Thing" },
    -- equipped
    [5001] = { "INVTYPE_HEAD", 4, 4, 1, "Old Helm", { HASTE = 80, MASTERY = 40 } },
    [5013] = { "INVTYPE_TRINKET", 4, 0, 1, "Trinket A" },
    [5014] = { "INVTYPE_TRINKET", 4, 0, 1, "Trinket B" },
    [5016] = { "INVTYPE_2HWEAPON", 2, 8, 1, "Equipped 2H" },
    [5017] = { "INVTYPE_2HWEAPON", 2, 8, 1, "Equipped 2H OH" },
    [5011] = { "INVTYPE_FINGER", 4, 0, 1, "Ring A", { HASTE = 60, CRIT = 30 } },
    [5012] = { "INVTYPE_FINGER", 4, 0, 1, "Ring B", { MASTERY = 50, VERS = 20, PRIMARY = 90 } },
    [5015] = { "INVTYPE_CLOAK", 4, 1, 1, "Old Cloak" },
    [5005] = { "INVTYPE_CHEST", 4, 4, 1, "Old Chest" },
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
        local _, _, ilvl = BonusInfo(BonusOfLink(link))
        if ilvl then return ilvl end -- a track bonus sets the level even with a context
        if ContextOf(link) == "23" then return 292 end
        local b2 = tonumber(tostring(link):match("item:%d+::::::::80:72:::1:(%d+)"))
        local id = tonumber(tostring(link):match("item:(%d+)"))
        return EQUIPPED_ILVL and EQUIPPED_ILVL[id] or 0
    end,
    GetItemInfo = function() return nil end,
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
_G.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemLink = function() return nil end }

-- season / challenge mode
local MAPS = {
    [587] = { "Murder Row", 2813 },
    [584] = { "The Blinding Vale", 2859 },
    [249] = { "Kings' Rest", 1762 },
}
_G.C_ChallengeMode = {
    GetMapTable = function() local t = {} for id in pairs(MAPS) do table.insert(t, id) end table.sort(t) return t end,
    GetMapUIInfo = function(id) local m = MAPS[id]; if m then return m[1], id, 1800, 1, 1, m[2] end end,
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
    RequestMapInfo = function() end,
    RequestCurrentAffixes = function() end,
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
local ej = { tier = 1, instance = nil, diff = 23, classID = 0, specID = 0, preview = 0 }
local lootDelayed = { [1309] = 1 } -- first read has no links
_G.EJ_GetNumTiers = function() return 2 end
_G.EJ_GetCurrentTier = function() return ej.tier end
_G.EJ_SelectTier = function(t) ej.tier = t end
_G.EJ_GetInstanceByIndex = function(i, isRaid)
    if isRaid then return nil end
    local inst = JOURNAL[ej.tier][i]
    if not inst then return nil end
    return inst.id, inst.name, "", 1, 1, 1, 1, 0, "", true, inst.map
end
_G.EJ_SelectInstance = function(id) ej.instance = id end
_G.EJ_SetDifficulty = function(d) ej.diff = d end
_G.EJ_GetDifficulty = function() return ej.diff end
_G.EJ_IsValidInstanceDifficulty = function(d) if d == 8 then return ej.tier == 2 end return d == 23 end
_G.EJ_SetLootFilter = function(c, s) ej.classID, ej.specID = c, s end
_G.EJ_GetLootFilter = function() return ej.classID, ej.specID end
_G.EJ_GetNumLoot = function() return LOOT[ej.instance] and #LOOT[ej.instance] or 0 end
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
        if resultID == 1 then return { activityIDs = { 1749 }, leaderName = "x" } end
        if resultID == 2 then return { activityIDs = { 9999 }, leaderName = "y" } end
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
local files = { "Core.lua", "Data.lua", "Style.lua", "Tracks.lua", "Gear.lua", "Stats.lua", "Links.lua", "Season.lua", "Loot.lua", "Evaluate.lua", "UI.lua", "Options.lua", "LFGHook.lua" }
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

-- Fire lifecycle (with poisoned learned names from an early build in saved variables)
_G.SlotFillerDB = { learnedTrackNames = { Myth = "Hero", Hero = "Hero" } }
local ev = ns.eventFrame._scripts.OnEvent
ev(ns.eventFrame, "ADDON_LOADED", "SlotFiller")
check(ns:TrackKeyForName("Myth") == "Myth" and ns.db.learnedTrackNames.Myth == nil, "poisoned learned track names are purged; English names win")
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
check(r.upgrades == 3 and r.total == 3 and r.vcUpgrades == 3, "Murder Row: 3/3 drop upgrades, 3/3 Voidcore upgrades")

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
check(r3.vcChance == 1 and r3.chance == 0.5, "Kings' Rest: 50% drop chance, 100% Voidcore chance")

check(ns.results[1].upgrades >= ns.results[2].upgrades, "results sorted by drop upgrades")
ns:SetItemState(1005, "want")
ns.db.sortMode = "wanted"
ns:Evaluate()
check(ns.results[1].wanted == 1 and ns.results[#ns.results].wanted == 0, "results sorted by wanted items (" .. ns.results[1].dungeon.name .. ")")
check(ns:ResultForDungeon(ns.dungeonByMapID[584]).wantedItems[1].item.itemID == 1005, "wanted item listed for its dungeon")
ns:SetItemState(1005, nil)
ns.db.sortMode = "upgrades"

-- countIlvlUpgrades off
ns.db.countIlvlUpgrades = false
ns:Evaluate()
r = ns:ResultForDungeon(ns.dungeonByMapID[587])
check(r.upgrades == 2, "ilvl-only upgrades excluded when disabled (" .. r.upgrades .. ")")
ns.db.countIlvlUpgrades = true

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
ns.cdb.itemState[1008] = "want" -- legacy flat table: moved into the spec on first use
ns:Evaluate()
r3 = ns:ResultForDungeon(ns.dungeonByMapID[249])
byItem = {}
for _, e in ipairs(r3.items) do byItem[e.item.itemID] = e end
check(byItem[1008].class == ns.UPGRADE_WANT, "wanted item counts")
check(ns:GetItemState(1008) == "want" and next(ns.cdb.itemState) == nil and ns.cdb.itemStateBySpec[72][1008] == "want", "legacy item state migrated per spec")
check(r3.wanted == 1 and ns:WantedItemIDs()[1] == 1008, "wanted item counted for its dungeon")
local sum = ns:SlotSummary()
check(sum[5].wanted[1] and sum[5].wanted[1].eval.item.itemID == 1008 and sum[5].wanted[1].dungeon.challengeMapID == 249, "slot summary names the wanted item and where it drops")
check(sum[1].bestDrop and sum[1].bestDrop.eval.item.itemID == 1001, "slot summary names the best drop for the head slot")
-- the wanted chest turns up in the bags: it leaves the list on its own
BAGS[1008] = 1
ns:CheckObtained()
RunTimers()
check(ns:GetItemState(1008) == nil and ns.cdb.obtained[72][1008], "wanted item removed once obtained")
BAGS[1008] = nil
-- share the list
ns:SetItemState(1002, "want"); ns:SetItemState(1005, "want")
local exported = ns:ExportWanted()
check(exported == "SF1:72:1002,1005", "wanted list exported (" .. exported .. ")")
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
check(ns.db.voidcoreMode and ns.db.targetKey == 10 and ns.dropCtx.isVoidcore and ns.dropCtx.ilvl == 318, "selector past +10 becomes Voidcore (318)")
check(ns:TargetLabel():find("Voidcore") ~= nil, "selector label shows Voidcore")
link, kind = ns:LinkForContext(head, ns.dropCtx)
check(kind == "exact" and BonusOfLink(link) == BonusFor(5, 1), "Voidcore tooltip link is Myth 1/6 via discovered bonus id")
check(ns.db.linkBonus[30] and ns.db.linkBonus[30].targets["318/1/Myth"] == BonusFor(5, 1), "discovered bonus id cached per season")
r3 = ns:ResultForDungeon(ns.dungeonByMapID[249])
byItem = {}
for _, e in ipairs(r3.items) do byItem[e.item.itemID] = e end
check(byItem[1008].class == ns.UPGRADE_TRACK, "in Voidcore mode the Hero 3/6 chest drop is a track upgrade")
ns:StepTargetKey(1); RunTimers()
check(ns.db.voidcoreMode, "stepping up from Voidcore stays at Voidcore")
ns:StepTargetKey(-1); RunTimers()
check(not ns.db.voidcoreMode and ns.db.targetKey == 10 and not ns.dropCtx.isVoidcore, "stepping down from Voidcore returns to +10")
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
ns.SEASON_DATA_LATEST.championBase = 279
ns.trackOffsetApplied = nil
ns:ApplyTrackDefaults()
check(ns.trackByKey.Hero.min == 292, "stale defaults applied (Hero base 292)")
ns:ScanGear()
check(ns.trackOffsetApplied == 13, "stale defaults auto-calibrated by +13 (" .. tostring(ns.trackOffsetApplied) .. ")")
check(ns.trackByKey.Hero.min == 305 and ns.trackByKey.Hero.max == 321, "Hero after calibration = 305-321")
check(ns.db.calibratedChampionBase == 292, "calibrated base remembered in saved variables")
-- no defaults at all: bootstrap purely from gear
ns.SEASON_DATA_LATEST.championBase = 0
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
ns.SEASON_DATA_LATEST.championBase = 292

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
check(ns:SetActiveStatProfile(1) and ns:StatProfileName() == "Erunak - Restoration Raid", "switching back to the first profile")
RunTimers()
order = ns:GetStatPriority()
check(order[1] == "CRIT", "priority follows the switch")
fr = ns:EvaluateDungeonAt(fake, 10)
check(fr.items[1].value and math.abs(fr.items[1].value - (ns:ItemValue(Link(1009), imported) or 0)) < 0.01, "values follow the switch (no stale cache)")
check(ns:RenameStatProfile(1, "  Raid ") and ns:StatProfileName() == "Raid", "rename trims and applies")
check(not ns:RenameStatProfile(1, "  "), "empty name rejected")
check(ns:FindStatProfile("mythic+") == 2 and ns:FindStatProfile("2") == 2 and ns:FindStatProfile("nope") == nil, "profiles found by name (any case) or number")
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
ns:SetStatWeights(nil)
RunTimers()
ns.loot.dungeons[9999] = nil

-- UI smoke test: show/hide with PVEFrame
PVEFrame._shown = true
ns.db.anchorSide = "left"
ns:ShowWindow(false)
RunTimers()
check(ns:IsWindowShown(), "window shown")
check(ns:CurrentPage() == "dungeons", "Dungeons tab first")
local wb = SlotFillerFrame.Toolbar.WeightsButton
check(wb and wb.Text:GetText():find("none", 1, true) ~= nil, "toolbar shows that no weight profile is in use")
wb:GetScript("OnClick")(wb)
check(ns.UI.IsMenuShown(), "weights menu opens")
wb:GetScript("OnClick")(wb)
check(not ns.UI.IsMenuShown(), "clicking again closes it")
ns:SetActiveStatProfile(1)
check(wb.Text:GetText():find("Erunak", 1, true) ~= nil, "toolbar shows the profile in use (" .. tostring(wb.Text:GetText()) .. ")")
ns:SetActiveStatProfile(nil)
RunTimers()
ns.uiExpandedMapID = 587
ns:RefreshWindow()
ns:ShowPage("gear")
check(ns:CurrentPage() == "gear", "Gear tab shown")
ns.uiExpandedSlotID = 12
ns:RefreshWindow()
ns.db.gearSort = "upgrades"
ns:RefreshWindow()
ns.db.gearSort = "slot"
ns:ToggleOptionsPanel()
check(ns:CurrentPage() == "settings", "Settings tab shown")
ns:RefreshOptionsPanel()
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
check(ns:CurrentPage() == "dungeons", "back to Dungeons")
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
