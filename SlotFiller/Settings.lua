-- Slot Filler: the Settings page, and the entry in the game's Settings > AddOns list.
local _, ns = ...
local Style, UI = ns.Style, ns.UI

local panel
local ROW_H = 24

function ns:BuildSettingsPage(page)
    panel = page
    local scroll, _, c = Style.ScrollFrame(page, 300)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    panel.controls = {}

    local y = -2
    local rowIndex = 0
    -- Alternating option rows, restarted per section.
    local function Row(height)
        rowIndex = rowIndex + 1
        local row = CreateFrame("Frame", nil, c)
        row:SetPoint("TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", 0, y)
        row:SetHeight(height or ROW_H)
        if rowIndex % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.03)
        end
        y = y - (height or ROW_H)
        return row
    end
    local function Header(text)
        y = y - 8
        local fs = Style.Text(c, 11, 1, 1, 1, 0.41)
        fs:SetPoint("TOPLEFT", 8, y)
        fs:SetText(string.upper(text))
        y = y - 18
        rowIndex = 0
    end
    local function RowLabel(row, text)
        local fs = Style.Text(row, 11, 1, 1, 1, 0.85)
        fs:SetPoint("LEFT", 8, 0)
        fs:SetText(text)
        return fs
    end
    local function AddCheck(label, tooltip, key, indent)
        local row = Row()
        local cb = UI.Check(row, 22)
        cb:SetPoint("LEFT", 4 + (indent or 0), 0)
        cb.Label = UI.Line(row, 11, "LEFT", 1, 1, 1, 0.85)
        cb.Label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.Label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        cb.Label:SetText(label)
        cb.get = function() return ns.db[key] end
        cb.set = function(v) ns.db[key] = v end
        cb:SetScript("OnClick", function(self)
            self.set(self:GetChecked() and true or false)
            ns:Fire("SETTINGS_CHANGED")
        end)
        if tooltip then UI.Tip(cb, "ANCHOR_RIGHT", label, tooltip) end
        table.insert(panel.controls, cb)
        return cb
    end
    local function Hint(text, height)
        local fs = Style.Text(c, 10, 1, 1, 1, 0.53)
        fs:SetPoint("TOPLEFT", 8, y)
        fs:SetPoint("RIGHT", c, "RIGHT", -8, 0)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetHeight(height or 26)
        fs:SetText(text)
        y = y - (height or 26) - 4
        return fs
    end
    -- A labelled text box with a button on its right; Enter and the button
    -- both call onSubmit. Returns the row, box and button.
    local function EditRow(label, buttonText, onSubmit)
        local row = Row(28)
        local lbl = RowLabel(row, label)
        local button = UI.TextButton(row, buttonText, 56, 20)
        button:SetPoint("RIGHT", -6, 0)
        local box = UI.EditBox(row)
        box:SetPoint("LEFT", lbl, "RIGHT", 12, 0)
        box:SetPoint("RIGHT", button, "LEFT", -6, 0)
        button:SetScript("OnClick", onSubmit)
        box:SetScript("OnEnterPressed", onSubmit)
        return row, box, button, lbl
    end
    -- Left-to-right small tabs on the right of a row; onSelect(id).
    local function Switch(row, defs, w, onSelect)
        local tabs = UI.TabStrip(row, defs, w, onSelect)
        tabs:SetPoint("RIGHT", -6, 0)
        return tabs
    end
    local function Stepper(row, onStep)
        local plus = UI.TextButton(row, "+", 22, 20, 13)
        plus:SetPoint("RIGHT", -6, 0)
        local box = CreateFrame("Frame", nil, row)
        box:SetSize(50, 20)
        box:SetPoint("RIGHT", plus, "LEFT", -1, 0)
        Style.Panel(box, { inset = true })
        local text = Style.Text(box, 11)
        text:SetPoint("CENTER", 0, 0)
        local minus = UI.TextButton(row, "-", 22, 20, 13)
        minus:SetPoint("RIGHT", box, "LEFT", -1, 0)
        plus:SetScript("OnClick", function() onStep(1) end)
        minus:SetScript("OnClick", function() onStep(-1) end)
        return text
    end
    local specName = function() return (ns:SpecName(ns:GetEvalSpecID())) or "this spec" end

    Header("Dungeons")
    AddCheck("Count immediate item level upgrades",
        "Also count drops that are a higher item level than your current item even when they would not upgrade further than it (same or lower track).",
        "countIlvlUpgrades")
    local match = AddCheck("Match drops to your slot's item level",
        "Judge every drop as upgraded free to the item level you already have in that slot (rings, trinkets and one-handers: the lower of the pair). Same-level drops with better stats then count as upgrades. Also on the toolbar.",
        "matchLevel")
    match.set = function(v) ns:SetMatchLevel(v) end
    AddCheck("Hide dungeons and bosses with nothing for you", "Hide dungeons and raid bosses with no upgrade drops and no wanted items.", "hideEmptyDungeons")
    AddCheck("Only list upgrades and wanted items under a dungeon", "Hide the other drops when a dungeon is expanded.", "hideNonUpgrades")
    AddCheck("Show tier tokens as the token, the set piece beneath",
        "A raid boss's tier token is judged as the set piece it makes for your class. On: the row shows the token; click it for the piece. Off: the piece takes the token's place. The last boss's any-slot token always lists its five pieces.",
        "nestTokens")

    Header("Wanted list")
    local wantedBox, wantedImport
    local function ImportWanted()
        local n, info = ns:ImportWanted(wantedBox:GetText() or "")
        if n then
            wantedBox:SetText("")
            wantedBox:ClearFocus()
            ns:Print(string.format("Added %d item(s) to the wanted list for %s.", n, specName()))
        else
            ns:Print("Could not read that list:", info)
        end
        ns:RefreshSettings()
    end
    local wantedRow
    wantedRow, wantedBox, wantedImport = EditRow("Share", "Import", ImportWanted)
    local wantedExport = UI.TextButton(wantedRow, "Export", 56, 20)
    wantedExport:SetPoint("RIGHT", wantedImport, "LEFT", -4, 0)
    wantedBox:SetPoint("RIGHT", wantedExport, "LEFT", -6, 0)
    wantedExport:SetScript("OnClick", function()
        wantedBox:SetText(ns:ExportWanted())
        wantedBox:SetFocus()
        wantedBox:HighlightText()
    end)
    UI.Tip(wantedExport, "ANCHOR_RIGHT", "Export", "Puts your wanted list and Voidcore targets for this spec in the box as text you can copy and send to a friend.")
    UI.Tip(wantedImport, "ANCHOR_RIGHT", "Import", "Paste a list a friend exported and press Enter. Items are added to your lists for this spec.")
    local clearRow = Row(28)
    panel.wantedCount = RowLabel(clearRow, "")
    local wantedClear = UI.TextButton(clearRow, "Clear wanted list", 120, 20)
    wantedClear:SetPoint("RIGHT", -6, 0)
    wantedClear:SetScript("OnClick", function()
        for _, id in ipairs(ns:WantedItemIDs()) do ns:SetItemState(id, nil) end
        for _, id in ipairs(ns:VoidcoreItemIDs()) do ns:SetVoidcoreTarget(id, false) end
        ns:RefreshSettings()
    end)
    Hint("Star a drop to want it; the purple star marks what you would spend a Voidcore on. Both leave the list by themselves once the item turns up.", 30)

    Header("Stat weights")
    local profRow = Row(28)
    local profLabel = RowLabel(profRow, "Profile")
    local profDelete = UI.TextButton(profRow, "Delete", 56, 20)
    profDelete:SetPoint("RIGHT", -6, 0)
    local profDrop = UI.StatProfileDropdown(profRow, nil, 20)
    profDrop:SetPoint("LEFT", profLabel, "RIGHT", 12, 0)
    profDrop:SetPoint("RIGHT", profDelete, "LEFT", -6, 0)
    panel.profileDrop, panel.profileDelete = profDrop, profDelete
    profDelete:SetScript("OnClick", function()
        local i, scale = ns:GetActiveStatProfile()
        if i then
            ns:DeleteStatProfile(i)
            ns:Print(string.format("Deleted weight profile \"%s\" for %s.", tostring(scale.name), specName()))
        end
        ns:RefreshSettings()
    end)
    UI.Tip(profDelete, "ANCHOR_RIGHT", "Delete profile", "Forget the selected profile. Stats are ranked from your gear until you pick another one.")

    -- The spec a pasted string is saved for: detected from the string's
    -- own Spec= (falling back to the evaluated spec), or one picked here.
    -- Not remembered: the next paste detects again.
    local pawnBox, pawnSpec
    local pawnSpecID = nil
    local function ImportPawn()
        local scale, err, specID = ns:ImportPawnString(pawnBox:GetText() or "", nil, pawnSpecID)
        if scale then
            pawnBox:SetText("")
            pawnBox:ClearFocus()
            ns:Print(ns:PawnSavedText(scale, specID))
        else
            ns:Print("Could not read that Pawn string:", err)
        end
        ns:RefreshSettings()
    end
    local pawnRow, pawnLabel
    pawnRow, pawnBox, _, pawnLabel = EditRow("Pawn string", "Import", ImportPawn)
    local function RefreshPawnSpec()
        pawnSpec.Text:SetText(pawnSpecID and (ns:SpecName(pawnSpecID)) or "|cffaaaaaaDetect spec|r")
    end
    pawnSpec = UI.Dropdown(pawnRow, 108, 20, function()
        local entries = { { text = "Detect from the string", checked = pawnSpecID == nil, onClick = function() pawnSpecID = nil; RefreshPawnSpec() end,
            tip = { "Detect the spec", "Reads the Spec= in the string itself. A string for another class, or without one, goes to the spec the window shows." } } }
        for _, spec in ipairs(ns:GetPlayerSpecs()) do
            entries[#entries + 1] = { text = spec.name, checked = pawnSpecID == spec.id, onClick = function() pawnSpecID = spec.id; RefreshPawnSpec() end,
                tip = { spec.name, "The next paste is saved for " .. spec.name .. ", whatever the string says." } }
        end
        return entries
    end)
    pawnSpec:SetPoint("LEFT", pawnLabel, "RIGHT", 12, 0)
    pawnBox:SetPoint("LEFT", pawnSpec, "RIGHT", 4, 0)
    RefreshPawnSpec()
    panel.pawnSpec, panel.pawnBox = pawnSpec, pawnBox
    UI.Tip(pawnBox, "ANCHOR_RIGHT", "Pawn string",
        "Paste a Pawn scale string (from Pawn, Raidbots or a guide) and press Enter. It is saved as a new profile named after the scale, under the spec it names, and used right away: its weights order the stats, and tooltips compare a drop's weighted value with your equipped item.")

    local nameBox
    local function RenameProfile()
        local i, scale = ns:GetActiveStatProfile()
        nameBox:ClearFocus()
        if i and ns:RenameStatProfile(i, nameBox:GetText() or "") then
            ns:Print(string.format("Renamed weight profile to \"%s\".", scale.name))
        end
        ns:RefreshSettings()
    end
    _, nameBox, panel.nameRename = EditRow("Name", "Rename", RenameProfile)
    panel.nameBox = nameBox
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ns:RefreshSettings() end)
    UI.Tip(nameBox, "ANCHOR_RIGHT", "Profile name", "Rename the selected profile: type a name and press Enter. Short names such as Raid or M+ read best in the window.")
    Hint("Keep one profile per situation, say Raid and Mythic+, and switch with the Weights button in the window or here. Profiles belong to this character and spec.", 30)

    -- Stat priority: a Manual / Auto switch, the four stats best first, and
    -- one line under them saying how to arrange them (Manual) or where the
    -- order comes from (Auto).
    Header("Stat priority")
    local modeRow = Row(26)
    RowLabel(modeRow, "Order")
    panel.StatModeTabs = Switch(modeRow, {
        { "manual", "Manual", "Your own order for this spec: click the stats to arrange them." },
        { "auto", "Auto", "Follows the weight profile in use, or your equipped gear without one." },
    }, 60, function(mode) ns:SetStatMode(mode); ns:RefreshSettings() end)

    local prioRow = Row(26)
    RowLabel(prioRow, "Best first")
    panel.statButtons = {}
    local prevBtn
    for i = 1, #ns.STATS do
        local b = UI.TextButton(prioRow, "", 40, 20, 10)
        if prevBtn then b:SetPoint("RIGHT", prevBtn, "LEFT", -1, 0) else b:SetPoint("RIGHT", -6, 0) end
        b.index = #ns.STATS - i + 1 -- laid out right to left
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, button)
            -- Left-click moves the stat left (better), right-click right. A
            -- click in Auto mode starts a manual order from the shown one.
            local list = { unpack(ns:GetStatPriority() or ns.STAT_DEFAULT_ORDER) }
            local j = self.index + (button == "RightButton" and 1 or -1)
            if j < 1 or j > #list then return end
            list[self.index], list[j] = list[j], list[self.index]
            ns:SetStatPriority(list)
            ns:RefreshSettings()
        end)
        b:HookScript("OnEnter", function(self)
            if not self.statName then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.statName)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        panel.statButtons[b.index] = b
        prevBtn = b
    end
    local hintRow = Row(22)
    panel.statHint = UI.Line(hintRow, 10, "LEFT", 1, 1, 1, 0.53)
    panel.statHint:SetPoint("LEFT", 8, 0)
    panel.statHint:SetPoint("RIGHT", -6, 0)

    Header("Window")
    local sideRow = Row(26)
    RowLabel(sideRow, "Dock side")
    local sideTip = "Left or right of the Dungeons & Raids window, or free: drag the title bar to place it."
    panel.DockTabs = Switch(sideRow, { { "left", "Left", sideTip }, { "right", "Right", sideTip }, { "free", "Free", sideTip } }, 60, function(side)
        ns.db.anchorSide = side
        ns:AnchorWindow()
        ns:Fire("SETTINGS_CHANGED")
    end)
    -- Free mode only: anchor the window to the Group Finder so it moves along
    -- when another addon moves that.
    local follow = AddCheck("Move with Dungeons & Raids",
        "Stay put next to the Dungeons & Raids window: when that window is moved, this one moves with it.",
        "freeFollow", 16)
    follow.set = function(v)
        ns.db.freeFollow = v
        ns:RememberFreePosition()
        ns:AnchorWindow()
    end
    panel.followCheck = follow
    -- The drawer tab stands in for the window whenever it is folded away;
    -- this is when the window opens by itself.
    local openRow = Row(26)
    RowLabel(openRow, "Opens by itself")
    panel.OpenTabs = Switch(openRow, {
        { "always", "Always", "Open whenever the Dungeons & Raids window opens." },
        { "premade", "Premade", "Opens when you go to the Premade Groups tab and folds away when you leave it." },
        { "never", "Never", "Stays folded away until you click the drawer tab." },
    }, 62, function(mode)
        ns.db.autoExpand = mode
        ns.userExpanded = nil -- the rule applies from the next tab change
        ns:Fire("SETTINGS_CHANGED")
    end)
    Hint("A thin drawer tab sits on the Dungeons & Raids window while this one is folded away: click it to open the window, its X to fold it back.", 30)
    AddCheck("Push the Group Finder right when needed",
        "If there is no room on the left of the screen, move the Group Finder right to make space. It moves back when this window closes.",
        "pushGroupFinder")

    local scaleRow = Row(26)
    RowLabel(scaleRow, "Scale")
    panel.scaleText = Stepper(scaleRow, function(d)
        ns.db.scale = math.max(0.6, math.min(1.5, ns.db.scale + d * 0.05))
        ns:AnchorWindow()
        ns:RefreshSettings()
    end)

    Header("Group Finder & keystones")
    AddCheck("Upgrade badge on group listings", "A line under each group in the Premade Groups search results: how many upgrade drops the dungeon has for you, wanted items and Voidcore targets that drop there.", "lfgBadges")
    AddCheck("Upgrade lines in group tooltips", nil, "lfgTooltip")
    AddCheck("Upgrade lines on keystone tooltips",
        "Show the same lines on Mythic Keystone tooltips: your keystone in the bags and keystone links in chat, evaluated at that key's level.",
        "keystoneTooltip")
    AddCheck("Rating gain on keystone tooltips",
        "The rating a timed run would add, on your keystone's tooltip and on keystone links in chat, at that key's level.",
        "ioBadge")

    Header("Upgrade tracks")
    local trackText = Style.Text(c, 10, 1, 1, 1, 0.85)
    trackText:SetPoint("TOPLEFT", 8, y)
    trackText:SetPoint("RIGHT", c, "RIGHT", -8, 0)
    trackText:SetJustifyH("LEFT")
    trackText:SetJustifyV("TOP")
    trackText:SetSpacing(2)
    trackText:SetHeight(90)
    panel.trackText = trackText
    y = y - 94

    local shiftRow = Row(26)
    RowLabel(shiftRow, "Shift all tracks")
    local sReset = UI.TextButton(shiftRow, "Reset", 52, 20)
    sReset:SetPoint("RIGHT", -6, 0)
    local sPlus = UI.TextButton(shiftRow, "+1", 30, 20)
    sPlus:SetPoint("RIGHT", sReset, "LEFT", -6, 0)
    local sMinus = UI.TextButton(shiftRow, "-1", 30, 20)
    sMinus:SetPoint("RIGHT", sPlus, "LEFT", -1, 0)
    local function Shift(delta)
        local defs = ns:GetTrackDefs()
        for _, d in ipairs(defs) do d.min = d.min + delta end
        ns.db.trackOverride = defs
        ns:SetTrackTable(defs)
        ns:ScanGear()
        ns:RefreshSettings()
    end
    sMinus:SetScript("OnClick", function() Shift(-1) end)
    sPlus:SetScript("OnClick", function() Shift(1) end)
    sReset:SetScript("OnClick", function()
        ns.db.trackOverride = nil
        ns.trackOffsetApplied = nil
        ns:ApplyTrackDefaults()
        ns:ScanGear()
        ns:RefreshSettings()
    end)
    y = y - 4
    Hint("Tracks are calibrated automatically from the upgrade line on your equipped items. Use the shift buttons only if the numbers look wrong for the current season.", 40)

    Header("Reset")
    local btnRow = Row(28)
    local resetOverrides = UI.TextButton(btnRow, "Clear slot & item overrides", 160, 20)
    resetOverrides:SetPoint("LEFT", 6, 0)
    resetOverrides:SetScript("OnClick", function()
        wipe(ns.cdb.slotState)
        ns:ClearItemStates()
    end)
    UI.Tip(resetOverrides, "ANCHOR_RIGHT", "Clear overrides", "Resets every slot to Auto and clears the wanted list and exclusions for this spec.")
    local rescan = UI.TextButton(btnRow, "Rescan loot", 90, 20)
    rescan:SetPoint("LEFT", resetOverrides, "RIGHT", 6, 0)
    rescan:SetScript("OnClick", function() ns:RescanLoot(true) end)
    y = y - 6

    local ver = Style.Text(c, 10, 1, 1, 1, 0.41)
    ver:SetPoint("TOPLEFT", 8, y)
    ver:SetText("Slot Filler v" .. tostring(ns.version))
    y = y - 16

    c:SetHeight(-y + 10)
    panel:SetScript("OnShow", function() ns:RefreshSettings() end)
    return panel
end

function ns:RefreshSettings()
    if not panel or not panel:IsShown() then return end
    for _, cb in ipairs(panel.controls) do cb:SetChecked(cb.get() and true or false) end
    local side = self.db.anchorSide
    if panel.DockTabs.selectedTabID ~= side then Style.SelectTab(panel.DockTabs, side) end
    if panel.OpenTabs.selectedTabID ~= self.db.autoExpand then Style.SelectTab(panel.OpenTabs, self.db.autoExpand) end
    panel.followCheck:SetEnabled(side == "free")
    panel.followCheck:SetAlpha(side == "free" and 1 or 0.4)
    panel.followCheck.Label:SetAlpha(side == "free" and 1 or 0.4)
    panel.scaleText:SetText(string.format("%d%%", self.db.scale * 100 + 0.5))
    local n, v = #self:WantedItemIDs(), #self:VoidcoreItemIDs()
    panel.wantedCount:SetText((n + v) == 0 and "|cff888888Nothing wanted yet for this spec|r"
        or string.format("%d wanted, %s%d Voidcore|r for %s", n, ns.VC_HEX, v, (self:SpecName(self:GetEvalSpecID())) or "this spec"))
    local order, source = self:GetStatPriority()
    local mode = self:GetStatMode()
    if panel.StatModeTabs.selectedTabID ~= mode then Style.SelectTab(panel.StatModeTabs, mode) end
    for i, b in ipairs(panel.statButtons) do
        local s = self.STAT_BY_KEY[(order or self.STAT_DEFAULT_ORDER)[i]]
        b.Text:SetText(s.short)
        b.statName = s.name
        b.Text:SetAlpha(mode == "manual" and 1 or 0.6)
    end
    UI.RefreshStatProfileButton(panel.profileDrop)
    local pIndex, scale = self:GetActiveStatProfile()
    panel.profileDelete:SetEnabled(pIndex ~= nil)
    panel.nameRename:SetEnabled(pIndex ~= nil)
    if not (panel.nameBox.HasFocus and panel.nameBox:HasFocus()) then
        panel.nameBox:SetText(scale and tostring(scale.name) or "")
    end
    if mode == "manual" then
        panel.statHint:SetText("Left-click moves a stat left, right-click moves it right.")
    else
        panel.statHint:SetText(source == "weights" and ("From weight profile " .. tostring(scale and scale.name or "?"))
            or source == "gear" and "From your equipped gear"
            or "Nothing to go on yet: no weight profile, no secondary stats on your gear")
    end
    local lines = {}
    for i = #self.tracks, 1, -1 do
        local t = self.tracks[i]
        lines[#lines + 1] = string.format("%s%s|r: %d - %d (%d steps)", t.localizedName and "|cffffffff" or "|cffaaaaaa", self:TrackDisplayName(t), t.min, t.max, t.steps)
    end
    if #lines == 0 then lines[1] = "|cffff5555No track data|r" end
    if self.db.trackOverride then lines[#lines + 1] = "|cffff9900(manual override active)|r" end
    panel.trackText:SetText(table.concat(lines, "\n"))
end

-------------------------------------------------------------------------------
-- Entry in the game's Settings > AddOns list
-------------------------------------------------------------------------------
ns:On("DB_READY", function()
    if not Settings then return end
    local f = CreateFrame("Frame")
    f.name = "Slot Filler"
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Slot Filler")
    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(500)
    desc:SetJustifyH("LEFT")
    desc:SetText("Shows which Mythic+ dungeons drop gear you can use, docked to the Dungeons & Raids window. Settings live in the window's Settings tab.\n\nCommands: /sf, /sf key <n>, /sf rescan, /sf status")
    local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    open:SetText("Open Slot Filler")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        ns:OpenOptions()
    end)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, f, f.name)
    if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end)
