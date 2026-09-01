-- Slot Filler: options panel (overlay inside the main window) + Settings entry.
local _, ns = ...

local panel

local function Check(parent, label, tooltip, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.Label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.Label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.Label:SetText(label)
    cb.get, cb.set = get, set
    cb:SetScript("OnClick", function(self)
        self.set(self:GetChecked() and true or false)
        ns:Fire("SETTINGS_CHANGED")
    end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label)
            GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return cb
end

local function Radio(parent, label, value, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
    cb:SetSize(16, 16)
    cb.Label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.Label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.Label:SetText(label)
    cb.value, cb.get, cb.set = value, get, set
    cb:SetScript("OnClick", function(self)
        self.set(self.value)
        ns:Fire("SETTINGS_CHANGED")
        ns:RefreshOptionsPanel()
    end)
    return cb
end

local function Build()
    if panel then return panel end
    local main = SlotFillerFrame
    panel = CreateFrame("Frame", "SlotFillerOptionsPanel", main, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0.04, 0.04, 0.06, 0.98)
    panel:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)
    panel:SetPoint("TOPLEFT", main, "TOPLEFT", 4, -26)
    panel:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -4, 4)
    panel:SetFrameLevel(main:GetFrameLevel() + 20)
    panel:EnableMouse(true)
    panel:Hide()
    ns.optionsPanel = panel

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 30)
    local c = CreateFrame("Frame", nil, scroll)
    c:SetSize(280, 600)
    scroll:SetScrollChild(c)
    scroll:SetScript("OnSizeChanged", function(_, w) c:SetWidth(w) end)
    panel.controls = {}

    local y = -4
    local function Header(text)
        local fs = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", 4, y)
        fs:SetText(text)
        y = y - 18
    end
    local function AddCheck(label, tooltip, key)
        local cb = Check(c, label, tooltip,
            function() return ns.db[key] end,
            function(v) ns.db[key] = v end)
        cb:SetPoint("TOPLEFT", 0, y)
        y = y - 22
        table.insert(panel.controls, cb)
        return cb
    end

    Header("Evaluation")
    AddCheck("Count immediate item level upgrades",
        "Also count drops that are a higher item level than your current item even when they would not upgrade further than it (same or lower track).",
        "countIlvlUpgrades")
    AddCheck("Only show upgrades in item lists",
        "Hide non-upgrade items inside each dungeon's list.",
        "hideNonUpgrades")
    AddCheck("Collapse dungeons by default", nil, "collapsed")

    Header("Window")
    local sideLabel = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sideLabel:SetPoint("TOPLEFT", 4, y)
    sideLabel:SetText("Dock side:")
    local prev = sideLabel
    panel.radios = {}
    for _, def in ipairs({ { "left", "Left of Group Finder" }, { "right", "Right" }, { "free", "Free (drag title)" } }) do
        local r = Radio(c, def[2], def[1],
            function() return ns.db.anchorSide end,
            function(v) ns.db.anchorSide = v; ns:AnchorWindow() end)
        r:SetPoint("LEFT", prev, "RIGHT", 8, 0)
        prev = r.Label
        table.insert(panel.radios, r)
    end
    y = y - 20
    AddCheck("Open with the Group Finder", "Show automatically whenever the Dungeons & Raids window opens.", "autoShow")
    AddCheck("Only on the Premade Groups tab", "Only auto-show while the Premade Groups tab is active.", "onlyPremadeTab")
    local push = AddCheck("Push the Group Finder right when needed",
        "If there is no room on the left of the screen, move the Group Finder right to make space. It moves back when this window closes.",
        "pushGroupFinder")
    push.get = function() return ns.db.pushGroupFinder ~= false end

    -- scale
    local scaleLabel = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("TOPLEFT", 4, y - 4)
    scaleLabel:SetText("Scale:")
    local minus = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    minus:SetSize(20, 18); minus:SetText("-")
    minus:SetPoint("LEFT", scaleLabel, "RIGHT", 8, 0)
    local scaleText = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleText:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    scaleText:SetWidth(36)
    local plus = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    plus:SetSize(20, 18); plus:SetText("+")
    plus:SetPoint("LEFT", scaleText, "RIGHT", 2, 0)
    panel.scaleText = scaleText
    minus:SetScript("OnClick", function()
        ns.db.scale = math.max(0.6, (ns.db.scale or 1) - 0.05)
        ns:AnchorWindow(); ns:RefreshOptionsPanel()
    end)
    plus:SetScript("OnClick", function()
        ns.db.scale = math.min(1.5, (ns.db.scale or 1) + 0.05)
        ns:AnchorWindow(); ns:RefreshOptionsPanel()
    end)
    y = y - 28

    Header("Premade Groups list")
    AddCheck("Upgrade badge on group listings", "Show the number of upgrade drops next to each group in the Premade Groups search results.", "lfgBadges")
    AddCheck("Upgrade line in group tooltips", nil, "lfgTooltip")

    Header("Upgrade tracks")
    local trackText = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trackText:SetPoint("TOPLEFT", 4, y)
    trackText:SetPoint("RIGHT", c, "RIGHT", -4, 0)
    trackText:SetJustifyH("LEFT")
    trackText:SetJustifyV("TOP")
    trackText:SetHeight(90)
    panel.trackText = trackText
    y = y - 94

    local shiftLabel = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shiftLabel:SetPoint("TOPLEFT", 4, y)
    shiftLabel:SetText("Shift all tracks:")
    local sMinus = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    sMinus:SetSize(24, 18); sMinus:SetText("-1")
    sMinus:SetPoint("LEFT", shiftLabel, "RIGHT", 8, 0)
    local sPlus = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    sPlus:SetSize(24, 18); sPlus:SetText("+1")
    sPlus:SetPoint("LEFT", sMinus, "RIGHT", 4, 0)
    local sReset = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    sReset:SetSize(60, 18); sReset:SetText("Reset")
    sReset:SetPoint("LEFT", sPlus, "RIGHT", 8, 0)
    local function Shift(delta)
        local defs = ns:GetTrackDefs()
        for _, d in ipairs(defs) do d.min = d.min + delta; d.max = d.max + delta end
        ns.db.trackOverride = defs
        ns:SetTrackTable(defs)
        ns:ScanGear()
        ns:RefreshOptionsPanel()
    end
    sMinus:SetScript("OnClick", function() Shift(-1) end)
    sPlus:SetScript("OnClick", function() Shift(1) end)
    sReset:SetScript("OnClick", function()
        ns.db.trackOverride = nil
        ns.trackOffsetApplied = nil
        ns:ApplyTrackDefaults()
        ns:ScanGear()
        ns:RefreshOptionsPanel()
    end)
    y = y - 24
    local hint = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 4, y)
    hint:SetPoint("RIGHT", c, "RIGHT", -4, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Tracks are calibrated automatically from the upgrade line on your equipped items. Use the shift buttons only if the numbers look wrong for the current season.")
    hint:SetHeight(40)
    y = y - 44

    Header("Overrides")
    local resetOverrides = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    resetOverrides:SetSize(150, 20); resetOverrides:SetText("Clear slot/item overrides")
    resetOverrides:SetPoint("TOPLEFT", 4, y)
    resetOverrides:SetScript("OnClick", function()
        wipe(ns.cdb.slotState); wipe(ns.cdb.itemState)
        ns:Fire("SETTINGS_CHANGED")
    end)
    local clearCache = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    clearCache:SetSize(110, 20); clearCache:SetText("Rescan loot")
    clearCache:SetPoint("LEFT", resetOverrides, "RIGHT", 6, 0)
    clearCache:SetScript("OnClick", function() ns:RescanLoot(true) end)
    y = y - 30

    c:SetHeight(-y + 10)

    local back = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    back:SetSize(80, 20)
    back:SetText("Back")
    back:SetPoint("BOTTOMRIGHT", -8, 6)
    back:SetScript("OnClick", function() panel:Hide() end)

    local ver = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ver:SetPoint("BOTTOMLEFT", 10, 10)
    ver:SetText("Slot Filler v" .. tostring(ns.version))

    panel:SetScript("OnShow", function() ns:RefreshOptionsPanel() end)
    return panel
end

function ns:RefreshOptionsPanel()
    if not panel or not panel:IsShown() then return end
    for _, cb in ipairs(panel.controls) do cb:SetChecked(cb.get() and true or false) end
    for _, r in ipairs(panel.radios) do r:SetChecked(r.get() == r.value) end
    panel.scaleText:SetText(string.format("%d%%", (ns.db.scale or 1) * 100 + 0.5))
    local lines = {}
    for i = #self.tracks, 1, -1 do
        local t = self.tracks[i]
        table.insert(lines, string.format("%s%s|r: %d - %d (%d steps)",
            t.localizedName and "|cffffffff" or "|cffaaaaaa", self:TrackDisplayName(t), t.min, t.max, t.steps))
    end
    if #lines == 0 then table.insert(lines, "|cffff5555No track data|r") end
    if self.db.trackOverride then table.insert(lines, "|cffff9900(manual override active)|r") end
    panel.trackText:SetText(table.concat(lines, "\n"))
end

function ns:ToggleOptionsPanel()
    Build()
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

function ns:OpenOptions()
    self:ShowWindow(true)
    Build()
    panel:Show()
end

-------------------------------------------------------------------------------
-- Entry in the game's Settings > AddOns list
-------------------------------------------------------------------------------
ns:On("DB_READY", function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local f = CreateFrame("Frame")
    f.name = "Slot Filler"
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Slot Filler")
    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(500)
    desc:SetJustifyH("LEFT")
    desc:SetText("Shows which Mythic+ dungeons drop gear you can use, docked to the Dungeons & Raids window. Settings live inside the window itself.\n\nCommands: /sf, /sf key <n>, /sf rescan, /sf status")
    local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    open:SetText("Open Slot Filler")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        ns:OpenOptions()
    end)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, f, f.name)
    if ok and category then
        pcall(Settings.RegisterAddOnCategory, category)
        ns.settingsCategory = category
    end
end)
