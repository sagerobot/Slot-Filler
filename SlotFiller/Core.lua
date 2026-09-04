-- Slot Filler: namespace, saved variables, events, shared helpers, slash commands.
local ADDON, ns = ...
SlotFiller = ns -- for /dump and other addons

ns.name = ADDON
ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"

-------------------------------------------------------------------------------
-- Saved variable defaults. SlotFillerDB is account-wide (window and display
-- settings); SlotFillerCharDB is per character (everything the addon remembers
-- about you).
-------------------------------------------------------------------------------
ns.DEFAULTS = {
    account = {
        targetKey = 10,             -- key level the drops are judged at
        linkBonus = {},             -- learned upgrade-track bonus IDs per season (Links.lua)
        countIlvlUpgrades = true,   -- count immediate item level gains that are not a track upgrade
        matchLevel = false,         -- judge drops as upgraded free to the slot's level
        sortMode = "upgrades",      -- Dungeons tab: "upgrades" | "wanted" | "name"
        gearSort = "slot",          -- Gear tab: "slot" | "upgrades" | "wanted"
        gearSource = "both",        -- Gear tab drops from: "mplus" | "both" | "raid"
        raidDifficulty = "heroic",  -- Raid tab: "lfr" | "normal" | "heroic" | "mythic"
        raidSort = "boss",          -- Raid tab: "boss" | "upgrades" | "wanted"
        ioSort = "plan",            -- IO tab: "plan" | "best" | "gain" | "name"
        ioOrder = "rating",         -- IO tab plan order: "rating" | "gear"
        ioRuns = nil,               -- IO tab: plan shown, by run count (nil = the easiest)
        ioBadge = true,             -- rating gain on keystone tooltips
        rollSort = "best",          -- Voidcore tab: "best" | "pool" | "chance" | "targets"
        anchorSide = "left",        -- "left" | "right" | "free" of the Dungeons & Raids window
        onlyPremadeTab = false,     -- auto-show only while the Premade Groups tab is active
        autoShow = true,            -- open with the Group Finder
        lfgBadges = true,           -- line under premade group listings
        lfgTooltip = true,          -- lines in premade group tooltips
        keystoneTooltip = true,     -- lines on Mythic Keystone tooltips
        hideEmptyDungeons = false,  -- hide dungeons and bosses with nothing for you
        hideNonUpgrades = false,    -- hide non-upgrade drops inside an open list
        nestTokens = true,          -- tier token rows show the token, the piece beneath
        pushGroupFinder = true,     -- move the Group Finder right when there is no room on the left
        trackOverride = nil,        -- manual track table (Settings > Shift all tracks)
        scale = 1.0,
        freePos = nil,              -- free window: screen position
        freeFollow = false,         -- free window: move with the Dungeons & Raids window
        freeOffset = nil,           -- free window: offset from that window
        debug = false,
    },
    char = {
        ioTarget = nil,             -- IO tab: target rating (nil = the next milestone)
        ioMaxKey = nil,             -- IO tab: highest key the plans may use (nil = automatic)
        ioAvoid = {},               -- IO tab: [challengeMapID] = true for dungeons left out
        slotState = {},             -- [slotID] = "want" | "skip" (absent = auto)
        itemStateBySpec = {},       -- [specID] = { [itemID] = "want" | "exclude" }
        voidcoreBySpec = {},        -- [specID] = { [itemID] = true }: Voidcore targets
        rolled = {},                -- [specID][poolKey][itemID] = time: Voidcore rolls received
        lootCache = {},             -- [seasonID][specID] = scanned loot (Loot.lua)
        evalSpecID = nil,           -- spec the window evaluates for (nil = loot spec)
        statPrio = {},              -- [specID] = manual secondary stat order
        statMode = {},              -- [specID] = "auto" (absent = manual)
        statProfiles = {},          -- [specID] = { scale, ... } weight profiles
        statProfile = {},           -- [specID] = index of the profile in use
    },
}

-------------------------------------------------------------------------------
-- Helpers
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

ns.issecret = issecretvalue

function ns:Print(...)
    print("|cff4fc3f7Slot Filler|r:", ...)
end

function ns:Debug(...)
    if self.db and self.db.debug then print("|cff888888SF|r:", ...) end
end

function ns:Round(v)
    return math.floor(v + 0.5)
end

-- A number the addon may read (not a 12.x secret value), else nil.
function ns.Num(v)
    if type(v) == "number" and not ns.issecret(v) then return v end
    return nil
end

function ns.Tbl(v)
    if type(v) == "table" and not ns.issecret(v) then return v end
    return nil
end

function ns.HexColor(r, g, b)
    return string.format("|cff%02x%02x%02x", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

function ns.StripColor(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The name in an item's link, else its name field.
function ns.ItemName(item)
    return item.link and item.link:match("%[(.-)%]") or item.name or ("item " .. tostring(item.itemID))
end

-- Instance and activity names made comparable across sources.
function ns:NormalizeName(name)
    if type(name) ~= "string" then return nil end
    local s = name:lower()
    s = s:gsub("%s*%b()%s*$", "")       -- trailing "(Mythic Keystone)"
    s = s:gsub("[%p]", "")
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

-------------------------------------------------------------------------------
-- Internal messages, game events, timers
-------------------------------------------------------------------------------
local function Call(list, ...)
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

local listeners = {}
function ns:On(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

function ns:Fire(message, ...)
    if listeners[message] then Call(listeners[message], ...) end
end

local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame
local handlers = {}

function ns:RegisterEvent(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    -- an unknown event name raises; never let that break a caller
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then self:Debug("Unknown event", event) end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if handlers[event] then Call(handlers[event], ...) end
end)

-- Schedule(key, delay, fn) called again within `delay` runs fn once.
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
-- Saved variables and login
-------------------------------------------------------------------------------
local function LoadSavedVariables()
    SlotFillerDB = CopyDefaults(SlotFillerDB, ns.DEFAULTS.account)
    SlotFillerCharDB = CopyDefaults(SlotFillerCharDB, ns.DEFAULTS.char)
    ns.db, ns.cdb = SlotFillerDB, SlotFillerCharDB
end

ns:RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    LoadSavedVariables()
    ns:Fire("DB_READY")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
    ns.playerClassName, ns.playerClassID = select(2, UnitClass("player"))
    ns:Fire("LOGIN")
end)

-------------------------------------------------------------------------------
-- /sf status
-------------------------------------------------------------------------------
function ns:PrintStatus()
    self:Print("Status")
    print("  Season id:", tostring(self:GetSeasonID()), " dungeons:", #self.dungeons)
    local overall = self:OverallRating()
    local chk = self.ratingCheck
    print(string.format("  Rating: %s (formula: %d timed run(s) checked, %d off)%s",
        overall and tostring(self:Round(overall)) or "not loaded", chk and chk.checked or 0, chk and chk.off or 0,
        chk and chk.worst and string.format("; worst %s +%d: expected %.1f, game says %.1f", chk.worst.name, chk.worst.level, chk.worst.expected, chk.worst.actual) or ""))
    local ctx = self:GetDropContext()
    print(string.format("  Target key +%d -> ilvl %s (%s) %s", ctx.key, tostring(ctx.ilvl), ctx.source, self:TrackText(ctx.track, ctx.step)))
    print("  Tracks:")
    for _, t in ipairs(self.tracks) do
        print(string.format("    %s (%s): %d-%d, %d steps", t.key, t.localizedName or "?", t.min, t.max, t.steps))
    end
    print("  Spec:", self:SpecName(self:GetEvalSpecID()), self.cdb.evalSpecID and "(manual)" or "(loot spec)")
    print("  Weights:", self:StatProfileName() or "none", string.format("(%d profile(s) saved for this spec on this character)", #self:GetStatProfiles()))
    print("  Style:", self.Style.mode or "undecided", self.Style.IsSkinned() and "(EllesmereUI skin)" or "")
    print("  Wanted:", table.concat(self:WantedItemIDs(), ", "))
    print("  Voidcore targets:", table.concat(self:VoidcoreItemIDs(), ", "))
    if self.loot then
        local n = 0
        for _ in pairs(self.loot.dungeons or {}) do n = n + 1 end
        print("  Loot cache:", n, "dungeons, scanned", date("%Y-%m-%d %H:%M", self.loot.time or 0))
    else
        print("  Loot cache: none")
    end
    local raids, bosses = self:GetRaids(), 0
    for _, raid in ipairs(raids) do bosses = bosses + #raid.bosses end
    print("  Raids:", #raids, "with", bosses, "boss(es); Raid tab difficulty", self:GetRaidDifficulty())
    local set = self.loot and self.loot.classSet
    if set then
        local n = 0
        for _ in pairs(set.pieces or {}) do n = n + 1 end
        print(string.format("  Class set: %s (%s), %d pieces; tier tokens are judged as its pieces", tostring(set.name), tostring(set.setID), n))
    else
        print("  Class set: none read from the journal; tier tokens are judged by slot only")
    end
    for _, d in ipairs(self.dungeons) do
        local items = self:GetDungeonLoot(d.challengeMapID)
        local entry = self.loot and self.loot.dungeons and self.loot.dungeons[d.challengeMapID]
        print(string.format("    %s  map %d  instance %s  journal %s (tier %s, difficulty %s)  items %s, previews %s", d.name, d.challengeMapID,
            tostring(d.instanceMapID), tostring(d.journalID), tostring(d.journalID and self.journalTier[d.journalID]),
            tostring(entry and entry.difficulty), items and #items or "-", tostring(entry and entry.previews)))
    end
    print("  Gear:")
    for _, s in ipairs(self.SLOTS) do
        local g = self.gear[s.id]
        if g and not g.empty then print(string.format("    %-9s %s", s.key, self.UI.EquippedDesc(g))) end
    end
    local marks = {}
    for r = 0, 16 do
        if self.watermarks[r] then marks[#marks + 1] = string.format("%s %d", self.REDUNDANCY_NAMES[r] or tostring(r), self.watermarks[r]) end
    end
    print(string.format("  Free upgrade levels (Match level %s, %s): %s", self.db.matchLevel and "on" or "off", self.watermarkSource or "not read",
        #marks > 0 and table.concat(marks, ", ") or "none reported by the client; equipped item levels stand in"))
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
local function PawnCommand(text)
    local sub, arg = text:match("^(%S+)%s*(.-)$")
    sub = sub and sub:lower() or ""
    local specName = (ns:SpecName(ns:GetEvalSpecID())) or "this spec"
    if text == "" or sub == "list" then
        ns:PrintStatProfiles()
    elseif sub == "clear" or sub == "none" then
        ns:SetActiveStatProfile(nil)
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
end

local function ResetCommand(what)
    if what == "overrides" then
        wipe(ns.cdb.slotState); wipe(ns.cdb.ioAvoid)
        ns:ClearItemStates()
        ns:Fire("RATING_UPDATED")
        ns:Print("Slot, item and avoided-dungeon overrides cleared.")
    elseif what == "cache" then
        wipe(ns.cdb.lootCache)
        ns:Print("Loot cache cleared. Rescanning.")
        ns:RescanLoot(true)
    elseif what == "all" then
        wipe(SlotFillerDB); wipe(SlotFillerCharDB)
        LoadSavedVariables()
        ns:Print("All settings reset. Reload the UI (/reload) to apply cleanly.")
    else
        ns:Print("Usage: /sf reset overrides | cache | all")
    end
end

local HELP = {
    "  /sf            toggle the window",
    "  /sf key <n>    evaluate drops at key level n",
    "  /sf match      toggle Match level (drops judged as upgraded free to your slot's level)",
    "  /sf rescan     rescan dungeon loot tables",
    "  /sf options    open settings",
    "  /sf status     print what the addon currently knows",
    "  /sf link       diagnostics for item tooltips at the selected key",
    "  /sf voidcore   diagnostics for the bonus roll pools (Voidcache tooltips)",
    "  /sf lfg        diagnostics for the Premade Groups listings on screen",
    "  /sf pawn <string>   save a Pawn scale as a weight profile for the current spec and use it",
    "  /sf pawn       list weight profiles: use <name>, rename <n> <name>, delete <name>, clear",
    "  /sf reset overrides|cache|all",
    "  /sf debug      toggle debug output",
}

SLASH_SLOTFILLER1 = "/sf"
SLASH_SLOTFILLER2 = "/slotfiller"
SlashCmdList.SLOTFILLER = function(msg)
    local raw = strtrim(msg or "")
    local cmd, rest = raw:lower():match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "toggle" then
        ns:ToggleWindow()
    elseif cmd == "show" then
        ns:ShowWindow(true)
    elseif cmd == "hide" then
        ns:HideWindow(true)
    elseif cmd == "rescan" or cmd == "scan" then
        ns:RescanLoot(true)
    elseif cmd == "key" then
        if tonumber(rest) then ns:SetTargetKey(tonumber(rest)) else ns:Print("Usage: /sf key <level>") end
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
    elseif cmd == "voidcore" then
        ns:PrintVoidcoreDiagnostics()
    elseif cmd == "lfg" then
        ns:PrintLFGDiagnostics()
    elseif cmd == "link" or cmd == "links" then
        ns:PrintLinkDiagnostics()
    elseif cmd == "pawn" or cmd == "weights" then
        PawnCommand(raw:match("^%S+%s*(.-)$") or "")
    elseif cmd == "reset" then
        ResetCommand(rest)
    else
        ns:Print("Commands:")
        for _, line in ipairs(HELP) do print(line) end
    end
end
