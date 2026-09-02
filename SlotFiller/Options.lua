-- Slot Filler: the Settings tab + the entry in the game's Settings > AddOns list.
local _, ns = ...
local Style = ns.Style

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
        local cb = ns.UI.Check(row, 22)
        cb:SetPoint("LEFT", 4 + (indent or 0), 0)
        cb.Label = Style.Text(row, 11, 1, 1, 1, 0.85)
        cb.Label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.Label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        cb.Label:SetJustifyH("LEFT")
        cb.Label:SetWordWrap(false)
        cb.Label:SetText(label)
        cb.get = function() return ns.db[key] end
        cb.set = function(v) ns.db[key] = v end
        cb:SetScript("OnClick", function(self)
            self.set(self:GetChecked() and true or false)
            ns:Fire("SETTINGS_CHANGED")
        end)
        if tooltip then ns.UI.Tip(cb, "ANCHOR_RIGHT", label, tooltip) end
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

    Header("Dungeons")
    AddCheck("Count immediate item level upgrades",
        "Also count drops that are a higher item level than your current item even when they would not upgrade further than it (same or lower track).",
        "countIlvlUpgrades")
    AddCheck("Hide dungeons and bosses with nothing for you", "Hide dungeons and raid bosses with no upgrade drops and no wanted items.", "hideEmptyDungeons")
    AddCheck("Only list upgrades and wanted items under a dungeon",
        "Hide the other drops when a dungeon is expanded.",
        "hideNonUpgrades")

    Header("Wanted list")
    local wantedRow = Row(28)
    local wantedLabel = RowLabel(wantedRow, "Share")
    local wantedImport = ns.UI.TextButton(wantedRow, "Import", 56, 20)
    wantedImport:SetPoint("RIGHT", -6, 0)
    local wantedExport = ns.UI.TextButton(wantedRow, "Export", 56, 20)
    wantedExport:SetPoint("RIGHT", wantedImport, "LEFT", -4, 0)
    local wantedBox = CreateFrame("EditBox", nil, wantedRow, "InputBoxTemplate")
    wantedBox:SetAutoFocus(false)
    wantedBox:SetHeight(20)
    wantedBox:SetPoint("LEFT", wantedLabel, "RIGHT", 12, 0)
    wantedBox:SetPoint("RIGHT", wantedExport, "LEFT", -6, 0)
    Style.EditBox(wantedBox)
    wantedExport:SetScript("OnClick", function()
        wantedBox:SetText(ns:ExportWanted())
        wantedBox:SetFocus()
        wantedBox:HighlightText()
    end)
    local function ImportWanted()
        local n, info = ns:ImportWanted(wantedBox:GetText() or "")
        if n then
            wantedBox:SetText("")
            wantedBox:ClearFocus()
            ns:Print(string.format("Added %d item(s) to the wanted list for %s.", n, (ns:SpecName(ns:GetEvalSpecID())) or "this spec"))
        else
            ns:Print("Could not read that list:", info)
        end
        ns:RefreshOptionsPanel()
    end
    wantedImport:SetScript("OnClick", ImportWanted)
    wantedBox:SetScript("OnEnterPressed", ImportWanted)
    wantedBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ns.UI.Tip(wantedExport, "ANCHOR_RIGHT", "Export", "Puts your wanted list and Voidcore targets for this spec in the box as text you can copy and send to a friend.")
    ns.UI.Tip(wantedImport, "ANCHOR_RIGHT", "Import", "Paste a list a friend exported and press Enter. Items are added to your lists for this spec.")
    local clearRow = Row(28)
    panel.wantedCount = RowLabel(clearRow, "")
    local wantedClear = ns.UI.TextButton(clearRow, "Clear wanted list", 120, 20)
    wantedClear:SetPoint("RIGHT", -6, 0)
    wantedClear:SetScript("OnClick", function()
        for _, id in ipairs(ns:WantedItemIDs()) do ns:SetItemState(id, nil) end
        for _, id in ipairs(ns:VoidcoreItemIDs()) do ns:SetVoidcoreTarget(id, false) end
        ns:RefreshOptionsPanel()
    end)
    Hint("Star a drop to want it; the purple star marks what you would spend a Voidcore on. Both leave the list by themselves once the item turns up.", 30)

    Header("Stat weights")
    local profRow = Row(28)
    local profLabel = RowLabel(profRow, "Profile")
    local profDelete = ns.UI.TextButton(profRow, "Delete", 56, 20)
    profDelete:SetPoint("RIGHT", -6, 0)
    local profDrop = ns.UI.StatProfileDropdown(profRow, nil, 20)
    profDrop:SetPoint("LEFT", profLabel, "RIGHT", 12, 0)
    profDrop:SetPoint("RIGHT", profDelete, "LEFT", -6, 0)
    panel.profileDrop, panel.profileDelete = profDrop, profDelete
    profDelete:SetScript("OnClick", function()
        local i, scale = ns:GetActiveStatProfile()
        if i then
            ns:DeleteStatProfile(i)
            ns:Print(string.format("Deleted weight profile \"%s\" for %s.", tostring(scale.name), (ns:SpecName(ns:GetEvalSpecID())) or "this spec"))
        end
        ns:RefreshOptionsPanel()
    end)
    ns.UI.Tip(profDelete, "ANCHOR_RIGHT", "Delete profile",
        "Forget the selected profile. Stats are ranked from your gear until you pick another one.")

    local pawnRow = Row(28)
    local pawnLabel = RowLabel(pawnRow, "Pawn string")
    local pawnImport = ns.UI.TextButton(pawnRow, "Import", 56, 20)
    pawnImport:SetPoint("RIGHT", -6, 0)
    local pawnBox = CreateFrame("EditBox", nil, pawnRow, "InputBoxTemplate")
    pawnBox:SetAutoFocus(false)
    pawnBox:SetHeight(20)
    pawnBox:SetPoint("LEFT", pawnLabel, "RIGHT", 12, 0)
    pawnBox:SetPoint("RIGHT", pawnImport, "LEFT", -6, 0)
    Style.EditBox(pawnBox)
    panel.pawnBox = pawnBox
    local function ImportPawn()
        local scale, err = ns:ImportPawnString(pawnBox:GetText() or "")
        local specName = ns:SpecName(ns:GetEvalSpecID())
        if scale then
            pawnBox:SetText("")
            pawnBox:ClearFocus()
            ns:Print(string.format("Saved Pawn scale \"%s\" as weight profile \"%s\" for %s and switched to it.", scale.pawnName or "?", scale.name, specName or "this spec"))
            if scale.spec and specName and scale.spec:lower() ~= tostring(specName):lower() then
                ns:Print(string.format("Note: the scale says %s %s; it is applied to %s.", scale.class or "", scale.spec, specName))
            end
        else
            ns:Print("Could not read that Pawn string:", err)
        end
        ns:RefreshOptionsPanel()
    end
    pawnImport:SetScript("OnClick", ImportPawn)
    pawnBox:SetScript("OnEnterPressed", ImportPawn)
    pawnBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ns.UI.Tip(pawnBox, "ANCHOR_RIGHT", "Pawn string",
        "Paste a Pawn scale string for this spec (from Pawn, Raidbots or a guide) and press Enter. It is saved as a new profile named after the scale and used right away: its weights order the stats, and tooltips compare a drop's weighted value with your equipped item.")

    local nameRow = Row(28)
    local nameLabel = RowLabel(nameRow, "Name")
    local nameRename = ns.UI.TextButton(nameRow, "Rename", 56, 20)
    nameRename:SetPoint("RIGHT", -6, 0)
    local nameBox = CreateFrame("EditBox", nil, nameRow, "InputBoxTemplate")
    nameBox:SetAutoFocus(false)
    nameBox:SetHeight(20)
    nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
    nameBox:SetPoint("RIGHT", nameRename, "LEFT", -6, 0)
    Style.EditBox(nameBox)
    panel.nameBox, panel.nameRename = nameBox, nameRename
    local function RenameProfile()
        local i, scale = ns:GetActiveStatProfile()
        nameBox:ClearFocus()
        if i and ns:RenameStatProfile(i, nameBox:GetText() or "") then
            ns:Print(string.format("Renamed weight profile to \"%s\".", scale.name))
        end
        ns:RefreshOptionsPanel()
    end
    nameRename:SetScript("OnClick", RenameProfile)
    nameBox:SetScript("OnEnterPressed", RenameProfile)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ns:RefreshOptionsPanel() end)
    ns.UI.Tip(nameBox, "ANCHOR_RIGHT", "Profile name",
        "Rename the selected profile: type a name and press Enter. Short names such as Raid or M+ read best in the window.")
    Hint("Keep one profile per situation, say Raid and Mythic+, and switch with the Weights button in the window or here. Profiles belong to this character and spec.", 30)

    -- Stat priority: a Manual / Auto switch, the four stats best first, and
    -- one line under them saying how to arrange them (Manual) or where the
    -- order comes from (Auto).
    Header("Stat priority")
    local modeRow = Row(26)
    RowLabel(modeRow, "Order")
    local modeTabs = CreateFrame("Frame", nil, modeRow)
    modeTabs:SetSize(2 * 60 + 1, 20)
    modeTabs:SetPoint("RIGHT", -6, 0)
    panel.StatModeTabs = modeTabs
    local prevMode
    for _, def in ipairs({
        { "manual", "Manual", "Your own order for this spec: click the stats to arrange them." },
        { "auto", "Auto", "Follows the weight profile in use, or your equipped gear without one." },
    }) do
        local tab = CreateFrame("Button", nil, modeTabs)
        tab:SetSize(60, 20)
        if prevMode then tab:SetPoint("LEFT", prevMode, "RIGHT", 1, 0) else tab:SetPoint("LEFT", 0, 0) end
        tab.Text = Style.Text(tab, 11)
        tab.Text:SetPoint("CENTER", 0, 0)
        tab.Text:SetText(def[2])
        tab.tabID = def[1]
        tab:SetScript("OnClick", function()
            ns:SetStatMode(def[1])
            ns:RefreshOptionsPanel()
        end)
        Style.Tab(tab)
        ns.UI.Tip(tab, "ANCHOR_RIGHT", def[2], def[3])
        prevMode = tab
    end

    local prioRow = Row(26)
    RowLabel(prioRow, "Best first")
    panel.statButtons = {}
    local prevBtn
    for i = 1, #ns.STATS do
        local b = ns.UI.TextButton(prioRow, "", 40, 20, 10)
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
            ns:RefreshOptionsPanel()
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
    panel.statHint = Style.Text(hintRow, 10, 1, 1, 1, 0.53)
    panel.statHint:SetPoint("LEFT", 8, 0)
    panel.statHint:SetPoint("RIGHT", -6, 0)
    panel.statHint:SetJustifyH("LEFT")
    panel.statHint:SetWordWrap(false)

    Header("Window")
    local sideRow = Row(26)
    RowLabel(sideRow, "Dock side")
    local dockTabs = CreateFrame("Frame", nil, sideRow)
    dockTabs:SetSize(3 * 60 + 2, 20)
    dockTabs:SetPoint("RIGHT", -6, 0)
    panel.DockTabs = dockTabs
    local prev
    for _, def in ipairs({ { "left", "Left" }, { "right", "Right" }, { "free", "Free" } }) do
        local tab = CreateFrame("Button", nil, dockTabs)
        tab:SetSize(60, 20)
        if prev then tab:SetPoint("LEFT", prev, "RIGHT", 1, 0) else tab:SetPoint("LEFT", 0, 0) end
        tab.Text = Style.Text(tab, 11)
        tab.Text:SetPoint("CENTER", 0, 0)
        tab.Text:SetText(def[2])
        tab.tabID = def[1]
        tab:SetScript("OnClick", function()
            ns.db.anchorSide = def[1]
            Style.SelectTab(dockTabs, def[1])
            ns:AnchorWindow()
            ns:Fire("SETTINGS_CHANGED")
        end)
        Style.Tab(tab)
        ns.UI.Tip(tab, "ANCHOR_RIGHT", "Dock side",
            "Left or right of the Dungeons & Raids window, or free: drag the title bar to place it.")
        prev = tab
    end
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
    AddCheck("Open with the Group Finder", "Show automatically whenever the Dungeons & Raids window opens.", "autoShow")
    AddCheck("Only on the Premade Groups tab", "Only auto-show while the Premade Groups tab is active.", "onlyPremadeTab")
    local push = AddCheck("Push the Group Finder right when needed",
        "If there is no room on the left of the screen, move the Group Finder right to make space. It moves back when this window closes.",
        "pushGroupFinder")
    push.get = function() return ns.db.pushGroupFinder ~= false end

    local scaleRow = Row(26)
    RowLabel(scaleRow, "Scale")
    local plus = ns.UI.TextButton(scaleRow, "+", 22, 20, 13)
    plus:SetPoint("RIGHT", -6, 0)
    local box = CreateFrame("Frame", nil, scaleRow)
    box:SetSize(50, 20)
    box:SetPoint("RIGHT", plus, "LEFT", -1, 0)
    Style.Panel(box, { inset = true })
    local scaleText = Style.Text(box, 11)
    scaleText:SetPoint("CENTER", 0, 0)
    local minus = ns.UI.TextButton(scaleRow, "-", 22, 20, 13)
    minus:SetPoint("RIGHT", box, "LEFT", -1, 0)
    panel.scaleText = scaleText
    minus:SetScript("OnClick", function()
        ns.db.scale = math.max(0.6, (ns.db.scale or 1) - 0.05)
        ns:AnchorWindow(); ns:RefreshOptionsPanel()
    end)
    plus:SetScript("OnClick", function()
        ns.db.scale = math.min(1.5, (ns.db.scale or 1) + 0.05)
        ns:AnchorWindow(); ns:RefreshOptionsPanel()
    end)

    Header("Group Finder & keystones")
    AddCheck("Upgrade badge on group listings", "Show the number of upgrade drops next to each group in the Premade Groups search results, with a star when a wanted item drops there.", "lfgBadges")
    AddCheck("Upgrade lines in group tooltips", nil, "lfgTooltip")
    AddCheck("Upgrade lines on keystone tooltips",
        "Show the same lines on Mythic Keystone tooltips: your keystone in the bags and keystone links in chat, evaluated at that key's level.",
        "keystoneTooltip")

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
    local sReset = ns.UI.TextButton(shiftRow, "Reset", 52, 20)
    sReset:SetPoint("RIGHT", -6, 0)
    local sPlus = ns.UI.TextButton(shiftRow, "+1", 30, 20)
    sPlus:SetPoint("RIGHT", sReset, "LEFT", -6, 0)
    local sMinus = ns.UI.TextButton(shiftRow, "-1", 30, 20)
    sMinus:SetPoint("RIGHT", sPlus, "LEFT", -1, 0)
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
    y = y - 4
    Hint("Tracks are calibrated automatically from the upgrade line on your equipped items. Use the shift buttons only if the numbers look wrong for the current season.", 40)

    Header("Reset")
    local btnRow = Row(28)
    local resetOverrides = ns.UI.TextButton(btnRow, "Clear slot & item overrides", 160, 20)
    resetOverrides:SetPoint("LEFT", 6, 0)
    resetOverrides:SetScript("OnClick", function()
        wipe(ns.cdb.slotState)
        ns:ClearItemStates()
    end)
    ns.UI.Tip(resetOverrides, "ANCHOR_RIGHT", "Clear overrides", "Resets every slot to Auto and clears the wanted list and exclusions for this spec.")
    local clearCache = ns.UI.TextButton(btnRow, "Rescan loot", 90, 20)
    clearCache:SetPoint("LEFT", resetOverrides, "RIGHT", 6, 0)
    clearCache:SetScript("OnClick", function() ns:RescanLoot(true) end)
    y = y - 6

    local ver = Style.Text(c, 10, 1, 1, 1, 0.41)
    ver:SetPoint("TOPLEFT", 8, y)
    ver:SetText("Slot Filler v" .. tostring(ns.version))
    y = y - 16

    c:SetHeight(-y + 10)
    panel:SetScript("OnShow", function() ns:RefreshOptionsPanel() end)
    return panel
end

function ns:RefreshOptionsPanel()
    if not panel or not panel:IsShown() then return end
    for _, cb in ipairs(panel.controls) do cb:SetChecked(cb.get() and true or false) end
    local side = ns.db.anchorSide or "left"
    if panel.DockTabs.selectedTabID ~= side then Style.SelectTab(panel.DockTabs, side) end
    panel.followCheck:SetEnabled(side == "free")
    panel.followCheck:SetAlpha(side == "free" and 1 or 0.4)
    panel.followCheck.Label:SetAlpha(side == "free" and 1 or 0.4)
    panel.scaleText:SetText(string.format("%d%%", (ns.db.scale or 1) * 100 + 0.5))
    local n, v = #self:WantedItemIDs(), #self:VoidcoreItemIDs()
    panel.wantedCount:SetText((n + v) == 0 and "|cff888888Nothing wanted yet for this spec|r"
        or string.format("%d wanted, %s%d Voidcore|r for %s", n, ns.VC_HEX, v, (self:SpecName(self:GetEvalSpecID())) or "this spec"))
    local order, source = self:GetStatPriority()
    local mode = self:GetStatMode()
    if panel.StatModeTabs.selectedTabID ~= mode then Style.SelectTab(panel.StatModeTabs, mode) end
    for i, b in ipairs(panel.statButtons) do
        local key = (order or self.STAT_DEFAULT_ORDER)[i]
        local s = self.STAT_BY_KEY[key]
        b.Text:SetText(s and s.short or tostring(key))
        b.statName = s and s.name or nil
        b.Text:SetAlpha(mode == "manual" and 1 or 0.6)
    end
    ns.UI.RefreshStatProfileButton(panel.profileDrop)
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
        table.insert(lines, string.format("%s%s|r: %d - %d (%d steps)",
            t.localizedName and "|cffffffff" or "|cffaaaaaa", self:TrackDisplayName(t), t.min, t.max, t.steps))
    end
    if #lines == 0 then table.insert(lines, "|cffff5555No track data|r") end
    if self.db.trackOverride then table.insert(lines, "|cffff9900(manual override active)|r") end
    panel.trackText:SetText(table.concat(lines, "\n"))
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
    if ok and category then
        pcall(Settings.RegisterAddOnCategory, category)
        ns.settingsCategory = category
    end
end)
