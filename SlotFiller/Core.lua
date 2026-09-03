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
        -- Learned upgrade-track bonus IDs per season (Links.lua).
        linkBonus = {},
        -- Count immediate item level upgrades that are not a track upgrade.
        countIlvlUpgrades = true,
        -- Judge drops as upgraded free to the slot's item level (the client's
        -- watermark), so same-slot drops compare by stats.
        matchLevel = false,
        -- Sorting: "upgrades" | "wanted" | "name"
        sortMode = "upgrades",
        -- Gear tab sorting: "slot" | "upgrades" | "wanted"
        gearSort = "slot",
        -- Gear tab: which drops it lists: "mplus" | "both" | "raid"
        gearSource = "both",
        -- Raid tab: difficulty the bosses are judged at: "lfr" | "normal" | "heroic" | "mythic"
        raidDifficulty = "heroic",
        -- Raid tab sorting: "boss" | "upgrades" | "wanted"
        raidSort = "boss",
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
        -- Same lines on Mythic Keystone tooltips (bags, chat links), at that key's level.
        keystoneTooltip = true,
        -- Hide dungeons with zero upgrades.
        hideEmptyDungeons = false,
        -- Hide non-upgrade items inside dungeon lists.
        hideNonUpgrades = false,
        -- Tier tokens as the token row with the set piece beneath (false:
        -- the piece in the token's place).
        nestTokens = true,
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
        -- Free mode: move along with the Dungeons & Raids window.
        freeFollow = false,
        -- Free mode: offset from the Dungeons & Raids window's top-left corner.
        freeOffset = nil,
        -- IO tab: which plan is shown, by run count (nil = the easiest plan).
        ioRuns = nil,
        -- IO tab sorting: "plan" | "best" | "gain" | "name"
        ioSort = "plan",
        -- IO tab plan order: "rating" (highest key first) | "gear" (most
        -- usable drops at the planned key first)
        ioOrder = "rating",
        -- Rating gain on group listings and keystone tooltips.
        ioBadge = true,
        -- Debug output.
        debug = false,
    },
    char = {
        -- IO tab: target rating (nil = the next milestone above the current rating).
        ioTarget = nil,
        -- IO tab: highest key the plans may use (nil = highest timed key + 2).
        ioMaxKey = nil,
        -- IO tab: dungeons left out of the plans: [challengeMapID] = true
        ioAvoid = {},
        -- Per-slot manual state: [slotID] = "auto" | "want" | "skip"
        slotState = {},
        -- Legacy per-item overrides (moved into itemStateBySpec on first use).
        itemState = {},
        -- Per-spec item overrides: [specID] = { [itemID] = "want" | "exclude" }. "want" is the wanted list.
        itemStateBySpec = {},
        -- Voidcore targets, the drops to spend a Nebulous Voidcore on: [specID] = { [itemID] = true }.
        voidcoreBySpec = {},
        -- Wanted items and Voidcore targets that turned up: [specID] = { [itemID] = time }.
        obtained = {},
        -- Loot cache: [seasonID] = { [specID] = { time, version, dungeons = { [challengeMapID] = {...} } } }
        lootCache = {},
        -- Spec the window evaluates for (nil = follow loot spec).
        evalSpecID = nil,
        -- Manual secondary stat order per spec: [specID] = { "HASTE", ... }.
        statPrio = {},
        -- Stat order mode per spec: [specID] = "auto" (weights, else gear); absent = manual.
        statMode = {},
        -- Stat weight profiles per spec: [specID] = { { name, pawnName, class, spec, weights = { CRIT = n, ... } }, ... }.
        statProfiles = {},
        -- Profile in use per spec: [specID] = index into statProfiles; absent = rank stats from gear.
        statProfile = {},
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
    local raw = strtrim(msg or "")
    msg = raw:lower()
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
        else
            ns:Print("Usage: /sf key <level>")
        end
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        ns:OpenOptions()
    elseif cmd == "match" then
        ns:SetMatchLevel(not ns.db.matchLevel)
        ns:Print("Match level", ns.db.matchLevel and "on: drops are judged as upgraded free to your slot's level." or "off.")
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns:Print("Debug output", ns.db.debug and "enabled" or "disabled")
    elseif cmd == "status" then
        ns:PrintStatus()
    elseif cmd == "link" or cmd == "links" then
        ns:PrintLinkDiagnostics()
    elseif cmd == "pawn" or cmd == "weights" then
        local text = raw:match("^%S+%s*(.-)$") or ""
        local sub, arg = text:match("^(%S+)%s*(.-)$")
        sub = sub and sub:lower() or ""
        local specName = (ns:SpecName(ns:GetEvalSpecID())) or "this spec"
        if text == "" or sub == "list" then
            ns:PrintStatProfiles()
        elseif sub == "clear" or sub == "none" then
            ns:SetStatWeights(nil)
            ns:Print("No weight profile in use for " .. specName .. ". Saved profiles are kept.")
        elseif sub == "use" or sub == "delete" or sub == "rename" then
            local what, newName = arg, nil
            if sub == "rename" then what, newName = arg:match("^(%S+)%s+(.-)%s*$") end
            local i, scale = ns:FindStatProfile(what)
            if sub == "rename" and not (what and newName) then
                ns:Print("Usage: /sf pawn rename <n> <new name>")
            elseif not i then
                ns:Print(string.format("No weight profile called \"%s\" for %s. /sf pawn lists them.", tostring(what or arg), specName))
            elseif sub == "use" then
                ns:SetActiveStatProfile(i)
                ns:Print(string.format("Using weight profile \"%s\" for %s.", scale.name, specName))
            elseif sub == "delete" then
                ns:DeleteStatProfile(i)
                ns:Print(string.format("Deleted weight profile \"%s\" for %s.", scale.name, specName))
            elseif ns:RenameStatProfile(i, newName) then
                ns:Print(string.format("Renamed weight profile to \"%s\".", scale.name))
            else
                ns:Print("Usage: /sf pawn rename <n> <new name>")
            end
        else
            local scale, err = ns:ImportPawnString(text)
            if scale then
                ns:Print(string.format("Saved Pawn scale \"%s\" as weight profile \"%s\" for %s and switched to it.", scale.pawnName or "?", scale.name, specName))
            else
                ns:Print("Could not read that Pawn string:", err)
            end
        end
    elseif cmd == "reset" then
        if rest == "overrides" then
            wipe(ns.cdb.slotState); wipe(ns.cdb.itemState); wipe(ns.cdb.ioAvoid)
            ns:ClearItemStates()
            ns:Fire("RATING_UPDATED")
            ns:Print("Slot, item and avoided-dungeon overrides cleared.")
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
        print("  /sf key <n>    evaluate drops at key level n")
        print("  /sf match      toggle Match level (drops judged as upgraded free to your slot's level)")
        print("  /sf rescan     rescan dungeon loot tables")
        print("  /sf options    open settings")
        print("  /sf status     print what the addon currently knows")
        print("  /sf link       diagnostics for item tooltips at the selected key")
        print("  /sf pawn <string>   save a Pawn scale as a weight profile for the current spec and use it")
        print("  /sf pawn       list weight profiles: use <name>, rename <n> <name>, delete <name>, clear")
        print("  /sf reset overrides|cache|all")
        print("  /sf debug      toggle debug output")
    end
end
