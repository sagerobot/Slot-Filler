-- Slot Filler: core namespace, saved variables, events, slash commands.
local ADDON, ns = ...
SlotFiller = ns -- exposed for /dump and other addons

ns.name = ADDON
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"

-------------------------------------------------------------------------------
-- Defaults
-------------------------------------------------------------------------------
ns.DEFAULTS = {
    profile = {
        -- Which key level the "drop" is evaluated at.
        targetKey = 10,
        -- Selector past the last useful key: evaluate the Voidcore roll instead.
        voidcoreMode = false,
        -- Learned upgrade-track bonus IDs per season (Links.lua).
        linkBonus = {},
        -- Count immediate item level upgrades that are not a track upgrade.
        countIlvlUpgrades = true,
        -- Sorting: "upgrades" | "chance" | "slots" | "name"
        sortMode = "upgrades",
        -- Where the window lives relative to PVEFrame: "left" | "right" | "free"
        anchorSide = "left",
        -- Show only while the Premade Groups tab is active (otherwise whenever PVEFrame is open).
        onlyPremadeTab = false,
        -- Auto-show alongside the Group Finder.
        autoShow = true,
        -- Badge on premade group listings.
        lfgBadges = true,
        -- Extra line in the premade group tooltip.
        lfgTooltip = true,
        -- Hide dungeons with zero upgrades.
        hideEmptyDungeons = false,
        -- Hide non-upgrade items inside dungeon lists.
        hideNonUpgrades = false,
        -- Move the Group Finder right when there is no room on the left.
        pushGroupFinder = true,
        -- Collapse item lists by default.
        collapsed = false,
        -- Track table manual overrides (nil = automatic).
        trackOverride = nil,
        -- Scale of the window.
        scale = 1.0,
        -- Free-position storage.
        freePos = nil,
        -- Debug output.
        debug = false,
    },
    char = {
        -- Per-slot manual state: [slotID] = "auto" | "want" | "skip"
        slotState = {},
        -- Per-item overrides: [itemID] = "exclude" | "want"
        itemState = {},
        -- Loot cache: [seasonID] = { [specID] = { time, version, dungeons = { [challengeMapID] = {...} } } }
        lootCache = {},
        -- Spec the window evaluates for (nil = follow loot spec).
        evalSpecID = nil,
    },
}

-------------------------------------------------------------------------------
-- Utilities
-------------------------------------------------------------------------------
local function CopyDefaults(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
ns.CopyDefaults = CopyDefaults

-- issecretvalue only exists on 12.x clients; treat everything as public elsewhere.
ns.issecret = issecretvalue or function() return false end

function ns:Print(...)
    print("|cff4fc3f7Slot Filler|r:", ...)
end

function ns:Debug(...)
    if self.db and self.db.debug then
        print("|cff888888SF|r:", ...)
    end
end

function ns:Round(v)
    return math.floor(v + 0.5)
end

-- Normalise instance / activity names so they can be compared across sources.
function ns:NormalizeName(name)
    if type(name) ~= "string" then return nil end
    local s = name:lower()
    s = s:gsub("%s*%b()%s*$", "")       -- trailing "(Mythic Keystone)"
    s = s:gsub("[%p]", "")               -- punctuation
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

-------------------------------------------------------------------------------
-- Lightweight message bus (internal)
-------------------------------------------------------------------------------
local listeners = {}
function ns:On(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

function ns:Fire(message, ...)
    local list = listeners[message]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

-------------------------------------------------------------------------------
-- Event dispatcher
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame
local handlers = {}

function ns:RegisterEvent(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    -- unknown event names raise on modern clients; never let that break a caller
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok then self:Debug("Unknown event", event) end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-------------------------------------------------------------------------------
-- Timers
-------------------------------------------------------------------------------
-- Debounce helper: calling Schedule(key, delay, fn) repeatedly within delay
-- only runs fn once.
local pending = {}
function ns:Schedule(key, delay, fn)
    if pending[key] then return end
    pending[key] = true
    C_Timer.After(delay, function()
        pending[key] = nil
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end)
end

-------------------------------------------------------------------------------
-- Saved variables
-------------------------------------------------------------------------------
ns:RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    SlotFillerDB = CopyDefaults(SlotFillerDB, ns.DEFAULTS.profile)
    SlotFillerCharDB = CopyDefaults(SlotFillerCharDB, ns.DEFAULTS.char)
    ns.db = SlotFillerDB
    ns.cdb = SlotFillerCharDB
    ns:Fire("DB_READY")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
    ns.playerClassID = select(3, UnitClass("player"))
    ns.playerClassName = select(2, UnitClass("player"))
    ns:Fire("LOGIN")
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
SLASH_SLOTFILLER1 = "/sf"
SLASH_SLOTFILLER2 = "/slotfiller"
SlashCmdList.SLOTFILLER = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "toggle" then
        ns:ToggleWindow()
    elseif cmd == "show" then
        ns:ShowWindow(true)
    elseif cmd == "hide" then
        ns:HideWindow(true)
    elseif cmd == "rescan" or cmd == "scan" then
        ns:RescanLoot(true)
    elseif cmd == "key" then
        local n = tonumber(rest)
        if n then
            ns:SetTargetKey(n)
        elseif rest == "vc" or rest == "voidcore" then
            ns:SetTargetKey(99)
        else
            ns:Print("Usage: /sf key <level> | vc")
        end
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        ns:OpenOptions()
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns:Print("Debug output", ns.db.debug and "enabled" or "disabled")
    elseif cmd == "status" then
        ns:PrintStatus()
    elseif cmd == "link" or cmd == "links" then
        ns:PrintLinkDiagnostics()
    elseif cmd == "reset" then
        if rest == "overrides" then
            wipe(ns.cdb.slotState); wipe(ns.cdb.itemState)
            ns:Print("Slot and item overrides cleared.")
            ns:Fire("SETTINGS_CHANGED")
        elseif rest == "cache" then
            wipe(ns.cdb.lootCache)
            ns:Print("Loot cache cleared. Rescanning.")
            ns:RescanLoot(true)
        elseif rest == "all" then
            wipe(SlotFillerDB); wipe(SlotFillerCharDB)
            SlotFillerDB = CopyDefaults(SlotFillerDB, ns.DEFAULTS.profile)
            SlotFillerCharDB = CopyDefaults(SlotFillerCharDB, ns.DEFAULTS.char)
            ns.db = SlotFillerDB; ns.cdb = SlotFillerCharDB
            ns:Print("All settings reset. Reload the UI (/reload) to apply cleanly.")
        else
            ns:Print("Usage: /sf reset overrides | cache | all")
        end
    else
        ns:Print("Commands:")
        print("  /sf            toggle the window")
        print("  /sf key <n>    evaluate drops at key level n (/sf key vc = Voidcore roll)")
        print("  /sf rescan     rescan dungeon loot tables")
        print("  /sf options    open settings")
        print("  /sf status     print what the addon currently knows")
        print("  /sf link       diagnostics for item tooltips at the selected key")
        print("  /sf reset overrides|cache|all")
        print("  /sf debug      toggle debug output")
    end
end
