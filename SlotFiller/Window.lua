-- Slot Filler: the main window. A shell that EllesmereUI paints when present
-- (Style.lua) holding a toolbar, the tabs' pages and the Settings page, with
-- the tab row hanging under it like the Group Finder's own. Docks to the
-- left of the Dungeons & Raids window, outside whatever else is parked on
-- its left edge, and pushes it right when the screen edge is in the way.
local _, ns = ...
local Style, UI = ns.Style, ns.UI

local WIDTH, FREE_HEIGHT, PAD, TITLE_H, TOOLBAR_H = UI.WIDTH, UI.FREE_HEIGHT, UI.PAD, UI.TITLE_H, UI.TOOLBAR_H
local frame

-------------------------------------------------------------------------------
-- Toolbar: spec selector, key stepper, weights and the info line (the loot tabs)
-------------------------------------------------------------------------------
local function BuildToolbar()
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", PAD, -(TITLE_H + 6))
    bar:SetPoint("TOPRIGHT", -PAD, -(TITLE_H + 6))
    bar:SetHeight(TOOLBAR_H)
    frame.Toolbar = bar

    local specBtn = CreateFrame("Button", nil, bar)
    specBtn:SetSize(176, 22)
    specBtn:SetPoint("TOPLEFT", 0, 0)
    specBtn.Icon = specBtn:CreateTexture(nil, "ARTWORK")
    specBtn.Icon:SetSize(16, 16)
    specBtn.Icon:SetPoint("LEFT", 4, 0)
    Style.SquareIcon(specBtn.Icon)
    specBtn.Arrow = specBtn:CreateTexture(nil, "OVERLAY")
    specBtn.Arrow:SetAtlas("Azerite-PointingArrow")
    specBtn.Arrow:SetSize(12, 9)
    specBtn.Arrow:SetPoint("RIGHT", -6, 0)
    specBtn.Arrow:SetVertexColor(1, 1, 1, 0.7)
    specBtn.Text = UI.Line(specBtn, 11)
    specBtn.Text:SetPoint("LEFT", specBtn.Icon, "RIGHT", 5, 0)
    specBtn.Text:SetPoint("RIGHT", specBtn.Arrow, "LEFT", -4, 0)
    Style.Button(specBtn, { "Icon", "Arrow" })
    specBtn:SetScript("OnClick", function() ns:CycleEvalSpec() end)
    UI.Tip(specBtn, "ANCHOR_BOTTOM", "Spec to evaluate",
        "Click to cycle: follow loot spec, or a specific spec.",
        "Loot is filtered the same way the Adventure Guide filters it. The wanted list is kept per spec.")
    bar.SpecButton = specBtn

    local keyPlus = UI.TextButton(bar, "+", 22, 22, 13)
    keyPlus:SetPoint("TOPRIGHT", 0, 0)
    keyPlus:SetScript("OnClick", function() ns:StepTargetKey(1) end)
    local keyBox = CreateFrame("Frame", nil, bar)
    keyBox:SetSize(64, 22)
    keyBox:SetPoint("RIGHT", keyPlus, "LEFT", -1, 0)
    Style.Panel(keyBox, { inset = true })
    local keyText = Style.Text(keyBox, 12)
    keyText:SetPoint("CENTER", 0, 0)
    local keyMinus = UI.TextButton(bar, "-", 22, 22, 13)
    keyMinus:SetPoint("RIGHT", keyBox, "LEFT", -1, 0)
    keyMinus:SetScript("OnClick", function() ns:StepTargetKey(-1) end)
    local keyLabel = Style.Text(bar, 11, 1, 1, 1, 0.53)
    keyLabel:SetPoint("RIGHT", keyMinus, "LEFT", -6, 0)
    keyLabel:SetText("Key")
    bar.KeyText, bar.KeyPlus, bar.KeyMinus, bar.KeyBox, bar.KeyLabel = keyText, keyPlus, keyMinus, keyBox, keyLabel
    for _, b in ipairs({ keyPlus, keyMinus }) do
        UI.Tip(b, "ANCHOR_BOTTOM", "Key level", "Drops are judged at the end-of-dungeon item level of this key.")
    end

    bar.WeightsButton = UI.StatProfileDropdown(bar, 176, 22)
    bar.WeightsButton:SetPoint("TOPLEFT", 0, -26)
    bar.Prio = UI.Line(bar, 11, "LEFT", 1, 1, 1, 0.6)
    bar.Prio:SetPoint("LEFT", bar.WeightsButton, "RIGHT", 8, 0)
    bar.Prio:SetPoint("RIGHT", bar, "RIGHT", -2, 0)

    -- Match level: judge drops as upgraded free to the slot's level
    local match = UI.Check(bar, 18)
    match:SetPoint("RIGHT", bar, "TOPRIGHT", 2, -61)
    match.Label = Style.Text(bar, 10, 1, 1, 1, 0.85)
    match.Label:SetPoint("RIGHT", match, "LEFT", -1, 0)
    match.Label:SetText("Match level")
    match:SetScript("OnClick", function(self) ns:SetMatchLevel(self:GetChecked() and true or false) end)
    UI.Tip(match, "ANCHOR_BOTTOM", "Match level",
        "Judge every drop as upgraded free to the item level you already have in that slot (rings, trinkets and one-handers: the lower of the pair).",
        "Same-level drops with better stats then count as upgrades, so same-slot drops compare by stats.")
    bar.Match = match

    bar.Info = UI.Line(bar, 10, "LEFT", 1, 1, 1, 0.6)
    bar.Info:SetPoint("LEFT", bar, "TOPLEFT", 2, -61)
    bar.Info:SetPoint("RIGHT", match.Label, "LEFT", -8, 0)
end

-- "Drops at +10: 311 Hero 3/6  ·  Voidcore: 318 Myth 1/6"
local function InfoText(ctx)
    local parts = {}
    if ctx.ilvl then
        local label = ctx.raid and ((ctx.difficultyName or "Raid") .. " drops") or string.format("Drops at +%d", ctx.key or 0)
        parts[#parts + 1] = string.format("%s: |cffffffff%d|r %s", label, ctx.ilvl, ns:TrackText(ctx.track, ctx.step))
    else
        parts[#parts + 1] = "|cffff5555Drop item level unknown|r"
    end
    local vc = ctx.voidcore
    if vc and vc.ilvl then
        parts[#parts + 1] = string.format("%sVoidcore:|r |cffffffff%d|r %s", ns.VC_HEX, vc.ilvl, ns:TrackText(vc.track, vc.step))
    end
    if ctx.source == "fallback" then parts[#parts + 1] = "|cffff9900season table|r" end
    return table.concat(parts, "  |cff555555·|r  ")
end

local function RefreshToolbar()
    local bar = frame.Toolbar
    local specID = ns:GetEvalSpecID()
    local specName, specIcon = ns:SpecName(specID)
    bar.SpecButton.Icon:SetTexture(specIcon or 134400)
    bar.SpecButton.Text:SetText(ns.cdb.evalSpecID and specName or (specName .. " |cff888888(loot spec)|r"))
    -- the key stepper is a Mythic+ thing; the Raid tab has its difficulty strip
    local raidTab = frame.page == "raid"
    for _, w in ipairs({ bar.KeyBox, bar.KeyPlus, bar.KeyMinus, bar.KeyLabel }) do w:SetShown(not raidTab) end
    bar.KeyText:SetText("+" .. ns.db.targetKey)
    bar.KeyPlus:SetEnabled(ns.db.targetKey < ns:MaxUsefulKey())
    bar.Match:SetChecked(ns.db.matchLevel and true or false)
    UI.RefreshStatProfileButton(bar.WeightsButton)
    local order, source = ns:GetStatPriority()
    bar.Prio:SetText(order and (ns:StatPriorityText(order) .. (source == "manual" and " |cff888888(manual order)|r" or "")) or "|cff888888no stat priority yet|r")
    bar.Info:SetText(InfoText(raidTab and ns:GetRaidContext(ns:GetRaidDifficulty()) or ns.dropCtx or ns:GetDropContext()))
end

-------------------------------------------------------------------------------
-- The frame
-------------------------------------------------------------------------------
local function BuildFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "SlotFillerFrame", UIParent)
    UI.Frame = frame
    frame:SetSize(WIDTH, FREE_HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(false)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    tinsert(UISpecialFrames, "SlotFillerFrame")
    Style.Shell(frame)

    -- title band (drag handle in free mode)
    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", 0, 0)
    title:SetHeight(TITLE_H)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function()
        if ns.db.anchorSide == "free" then frame:StartMoving() end
    end)
    title:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if ns.db.anchorSide == "free" then
            ns:RememberFreePosition()
            ns:AnchorWindow()
        end
    end)
    frame.TitleBar = title
    local titleText = Style.Text(title, 12)
    titleText:SetPoint("LEFT", 10, 0)
    titleText:SetText("Slot Filler")
    Style.OnLooksChanged(function() titleText:SetTextColor(Style.Accent()) end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -1, -1)
    close:SetSize(24, 24)
    close:SetScript("OnClick", function() ns:HideWindow(true) end)
    Style.CloseButton(close)

    local refreshAtlas = Style.FindAtlas({ "UI-RefreshButton", "uitools-icon-refresh" })
    local rescan = refreshAtlas and UI.GlyphButton(title, refreshAtlas, 20) or UI.TextButton(title, "Rescan", 52, 18, 10)
    rescan:SetPoint("RIGHT", close, "LEFT", -2, 0)
    rescan:SetScript("OnClick", function() ns:RescanLoot(true) end)
    UI.Tip(rescan, "ANCHOR_BOTTOM", "Rescan loot tables", "Re-reads every dungeon's loot from the Adventure Guide for the selected spec.")
    local cogAtlas = Style.FindAtlas({ "mechagon-projects", "GM-icon-settings" })
    local cog = UI.GlyphButton(title, cogAtlas, 20, "Interface\\Icons\\Trade_Engineering")
    cog:SetPoint("RIGHT", rescan, "LEFT", -2, 0)
    cog:SetScript("OnClick", function() ns:ToggleOptionsPanel() end)
    UI.Tip(cog, "ANCHOR_BOTTOM", "Settings", "Click again to come back.")
    frame.SettingsButton = cog

    BuildToolbar()

    frame.Pages = {}
    local function NewPage(key, top)
        local p = CreateFrame("Frame", nil, frame)
        p:SetPoint("TOPLEFT", PAD, -top)
        p:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        p:Hide()
        frame.Pages[key] = p
        return p
    end
    for _, tab in ipairs(UI.Tabs) do
        tab.Build(NewPage(tab.key, TITLE_H + 6 + (tab.ownHeader and 0 or TOOLBAR_H)))
    end
    ns:BuildSettingsPage(NewPage("settings", TITLE_H + 6))

    -- the tab row under the frame; Settings is the cog in the title bar
    local tabs = CreateFrame("Frame", nil, frame)
    tabs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", PAD, 1)
    tabs:SetSize(#UI.Tabs * UI.TAB_W + (#UI.Tabs - 1), UI.TAB_H)
    frame.TabRow = tabs
    for i, def in ipairs(UI.Tabs) do
        local tab = CreateFrame("Button", nil, tabs)
        tab:SetSize(UI.TAB_W, UI.TAB_H)
        tab:SetPoint("LEFT", (i - 1) * (UI.TAB_W + 1), 0)
        tab.Text = Style.Text(tab, 11)
        tab.Text:SetPoint("CENTER", 0, 0)
        tab.Text:SetText(def.label)
        tab.tabID = def.key
        tab:SetScript("OnClick", function() ns:ShowPage(def.key) end)
        Style.Tab(tab)
    end

    frame:SetScript("OnShow", function() ns:RefreshWindow() end)
    frame:SetScript("OnHide", function()
        -- following the Group Finder: keep the screen position current for
        -- the next time the window opens on its own
        if ns.db.anchorSide == "free" and ns.db.freeFollow then ns:RememberFreePosition() end
        ns:RestoreGroupFinderOffset()
    end)
    return frame
end

-------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------
function ns:ShowPage(key)
    BuildFrame()
    if not frame.Pages[key] then key = "dungeons" end
    for k, p in pairs(frame.Pages) do p:SetShown(k == key) end
    UI.CloseMenu()
    -- the IO tab has its own header; the toolbar is a loot thing
    frame.Toolbar:SetShown(key ~= "settings" and key ~= "io")
    if key ~= "settings" then frame.lastPage = key end
    frame.page = key
    Style.SelectTab(frame.TabRow, key)
    -- one request per visit, so the rating data is fresh; never from a refresh
    if key == "io" then self:RequestRatingData() end
    if key == "voidcore" then self:RetryEmptyVoidcorePools() end
    self:RefreshWindow()
end

function ns:CurrentPage()
    return frame and frame.page or "dungeons"
end

-- The cog: Settings, or back to the tab it came from.
function ns:ToggleOptionsPanel()
    self:ShowPage(self:CurrentPage() == "settings" and (frame and frame.lastPage or "dungeons") or "settings")
end

function ns:OpenOptions()
    self:ShowWindow(true)
    self:ShowPage("settings")
end

function ns:RefreshWindow()
    if not frame or not frame:IsShown() then return end
    local page = frame.page or "dungeons"
    if page == "settings" then
        self:RefreshSettings()
        return
    end
    for _, tab in ipairs(UI.Tabs) do
        if tab.key == page then
            if not tab.ownHeader then
                self.slotSummary = self:SlotSummary()
                RefreshToolbar()
            end
            tab.Refresh(frame.Pages[page])
        end
    end
end

-------------------------------------------------------------------------------
-- Docking on the left. The Group Finder usually opens at the left edge of
-- the screen, leaving no room: it is pushed right (UIPanel "xoffset" first,
-- a direct move as fallback) and restored when the window closes.
-------------------------------------------------------------------------------
local push = { offset = nil, moved = nil }

local function PVEToUIParent(v)
    return v * PVEFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

function ns:RestoreGroupFinderOffset()
    if not PVEFrame or InCombatLockdown() then return end
    if push.offset ~= nil then pcall(SetUIPanelAttribute, PVEFrame, "xoffset", push.offset) end
    if push.moved and PVEFrame:IsShown() then
        PVEFrame:ClearAllPoints()
        PVEFrame:SetPoint(push.moved.point, UIParent, push.moved.relPoint, push.moved.x, push.moved.y)
    end
    push.offset, push.moved = nil, nil
end

-- How far (in UIParent units) the window sticks out past the left screen edge.
local function Overhang()
    local left = frame:GetLeft()
    if not left then return 0 end
    local px = left * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if px >= 0 then return 0 end
    return math.ceil(-px) + 4
end

-- Other windows parked on the Group Finder's left edge. EllesmereUI docks the
-- character sheet there whenever both are open; the window docks outside
-- whichever visible neighbour reaches furthest left, so nothing lands on it.
local NEIGHBOURS = { "CharacterFrame", "RaiderIO_ProfileTooltip" }

local function FindLeftNeighbour()
    local best = PVEFrame
    local ps = PVEFrame:GetEffectiveScale() or 1
    local pl, pt, pb = PVEFrame:GetLeft(), PVEFrame:GetTop(), PVEFrame:GetBottom()
    if not (pl and pt and pb) then return best end
    local bestLeft, top, bottom = pl * ps, pt * ps, pb * ps
    for _, name in ipairs(NEIGHBOURS) do
        local f = _G[name]
        if f and f ~= frame and f:IsVisible() then
            local l, t, b = f:GetLeft(), f:GetTop(), f:GetBottom()
            local s = f:GetEffectiveScale() or 1
            if l and t and b and t * s > bottom and b * s < top and l * s < bestLeft then best, bestLeft = f, l * s end
        end
    end
    return best
end

local function LeftNeighbour()
    local ok, f = pcall(FindLeftNeighbour)
    return (ok and f) or PVEFrame
end

local function DockLeft()
    local neighbour = LeftNeighbour()
    frame.leftNeighbour, frame.dockedTo = neighbour, neighbour
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", neighbour, "TOPLEFT", -2, 0)
    -- A neighbour parked at the screen edge leaves no room: dock on the
    -- Group Finder itself and let the push below make space. (With
    -- EllesmereUI the character sheet follows the Group Finder, so the next
    -- watch tick re-docks outside it.)
    if neighbour ~= PVEFrame and Overhang() > 0 then
        frame.dockedTo = PVEFrame
        frame:ClearAllPoints()
        frame:SetPoint("TOPRIGHT", PVEFrame, "TOPLEFT", -2, 0)
    end
end

local function PushGroupFinder()
    if InCombatLockdown() or not ns.db.pushGroupFinder then return end
    local needed = Overhang()
    if needed <= 0 then return end
    -- 1) UIPanel layout offset: survives the panel manager re-laying out the frame
    local ok, current = pcall(GetUIPanelAttribute, PVEFrame, "xoffset")
    current = (ok and tonumber(current)) or 0
    if push.offset == nil then push.offset = current end
    pcall(SetUIPanelAttribute, PVEFrame, "xoffset", current + needed)
    pcall(UIParent_ManageFramePositions)
    -- 2) verify once the layout has settled; move the frame directly if needed
    C_Timer.After(0.05, function()
        if not frame:IsShown() or not PVEFrame:IsShown() or InCombatLockdown() or ns.db.anchorSide ~= "left" then return end
        DockLeft()
        local still = Overhang()
        if still > 0 then
            if not push.moved then
                local point, _, relPoint, x, y = PVEFrame:GetPoint(1)
                push.moved = { point = point or "TOPLEFT", relPoint = relPoint or "TOPLEFT", x = x or 0, y = y or 0 }
            end
            local left = PVEToUIParent(PVEFrame:GetLeft() or 0)
            local top = PVEToUIParent(PVEFrame:GetTop() or 0) - UIParent:GetHeight()
            PVEFrame:ClearAllPoints()
            PVEFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left + still, top)
            DockLeft()
        end
    end)
end

-- Free mode: remembers where the window sits, on the screen and, while the
-- Group Finder is open, relative to it ("Move with Dungeons & Raids").
-- Offsets are in the window's own scale, as SetPoint takes them.
function ns:RememberFreePosition()
    if not frame then return end
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return end
    local fs = frame:GetEffectiveScale()
    local uiTop = (UIParent:GetTop() or 0) * UIParent:GetEffectiveScale() / fs
    self.db.freePos = { point = "TOPLEFT", relPoint = "TOPLEFT", x = left, y = top - uiTop }
    if PVEFrame and PVEFrame:IsShown() and PVEFrame:GetLeft() then
        local ps = PVEFrame:GetEffectiveScale()
        self.db.freeOffset = { x = left - PVEFrame:GetLeft() * ps / fs, y = top - PVEFrame:GetTop() * ps / fs }
    end
end

function ns:AnchorWindow()
    if not frame then return end
    local side = self.db.anchorSide
    local docked = PVEFrame and PVEFrame:IsShown() and side ~= "free"
    frame:SetScale(self.db.scale)
    frame:ClearAllPoints()
    frame.dockedTo, frame.leftNeighbour = nil, nil
    if docked then
        frame:SetHeight(PVEFrame:GetHeight() * PVEFrame:GetEffectiveScale() / frame:GetEffectiveScale())
        if side == "right" then
            self:RestoreGroupFinderOffset()
            frame:SetPoint("TOPLEFT", PVEFrame, "TOPRIGHT", 2, 0)
        else
            DockLeft()
            PushGroupFinder()
        end
        return
    end
    self:RestoreGroupFinderOffset()
    frame:SetHeight(FREE_HEIGHT)
    -- anchored to the Group Finder, the window moves whenever it does
    local follow = self.db.freeFollow and PVEFrame and PVEFrame:IsShown()
    local off = follow and self.db.freeOffset
    local pos = self.db.freePos
    if off then
        frame:SetPoint("TOPLEFT", PVEFrame, "TOPLEFT", off.x, off.y)
    elseif pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
    end
    if follow and not off then
        -- first time next to the Group Finder since the option went on: the
        -- offset is wherever the window is now
        self:RememberFreePosition()
        off = self.db.freeOffset
        if off then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", PVEFrame, "TOPLEFT", off.x, off.y)
        end
    end
end

-- While docked on the left, keep checking that nothing has moved onto the
-- window: the UI panel manager re-lays the Group Finder out when another
-- panel opens, and the character sheet may arrive at its left edge.
local function OnUpdateWatch(self, elapsed)
    self.watchElapsed = (self.watchElapsed or 0) + elapsed
    if self.watchElapsed < 0.5 then return end
    self.watchElapsed = 0
    if PVEFrame and PVEFrame:IsShown() and ns.db.anchorSide == "left" and not InCombatLockdown() then
        if LeftNeighbour() ~= frame.leftNeighbour then
            ns:AnchorWindow()
        elseif Overhang() > 0 then
            PushGroupFinder()
        end
    end
end

-------------------------------------------------------------------------------
-- Show and hide
-------------------------------------------------------------------------------
function ns:ShowWindow(manual)
    BuildFrame()
    if manual then self.standalone = not (PVEFrame and PVEFrame:IsShown()) end
    self:RequestSeasonData()
    self:AnchorWindow()
    frame:SetScript("OnUpdate", OnUpdateWatch)
    if not frame.page then self:ShowPage("dungeons") end
    frame:Show()
    if not self.gearScanned then
        self:ScanGear()
    elseif self.db.matchLevel and self:ScanWatermarks() then
        self:Fire("GEAR_UPDATED")
    end
    self:EnsureLoot(false)
    if not self.results then self:Evaluate() end
    self:RefreshWindow()
end

function ns:HideWindow(manual)
    if manual then self.standalone = false end
    if frame then frame:Hide() end
end

function ns:ToggleWindow()
    if frame and frame:IsShown() then self:HideWindow(true) else self:ShowWindow(true) end
end

function ns:IsWindowShown()
    return frame and frame:IsShown()
end

function ns:ShouldAutoShow()
    if not self.db.autoShow or not (PVEFrame and PVEFrame:IsShown()) then return false end
    if self.db.onlyPremadeTab then return LFGListFrame and LFGListFrame:IsShown() end
    return true
end

local function UpdateAutoVisibility()
    if not ns.db or ns.userClosedThisSession then return end
    if ns:ShouldAutoShow() then
        if not ns:IsWindowShown() then ns:ShowWindow(false) else ns:AnchorWindow() end
    elseif ns:IsWindowShown() and not ns.standalone then
        ns:HideWindow(false)
    end
end

local function SoonUpdateAutoVisibility()
    C_Timer.After(0, UpdateAutoVisibility)
end

local function ReanchorSoon()
    C_Timer.After(0, function()
        if ns:IsWindowShown() and PVEFrame and PVEFrame:IsShown() and ns.db.anchorSide == "left" then ns:AnchorWindow() end
    end)
end

-- Group Finder hooks
ns:On("LOGIN", function()
    if PVEFrame then
        PVEFrame:HookScript("OnShow", function()
            ns.userClosedThisSession = nil
            SoonUpdateAutoVisibility()
        end)
        PVEFrame:HookScript("OnHide", function()
            if ns:IsWindowShown() and not ns.standalone then ns:HideWindow(false) end
            ns.userClosedThisSession = nil
        end)
    end
    if LFGListFrame then
        LFGListFrame:HookScript("OnShow", SoonUpdateAutoVisibility)
        LFGListFrame:HookScript("OnHide", SoonUpdateAutoVisibility)
    end
    if PVEFrame_ShowFrame then hooksecurefunc("PVEFrame_ShowFrame", SoonUpdateAutoVisibility) end
    if CharacterFrame then
        CharacterFrame:HookScript("OnShow", ReanchorSoon)
        CharacterFrame:HookScript("OnHide", ReanchorSoon)
    end
end)

-- closing with the X while docked: stay closed until the Group Finder is reopened
ns:On("DB_READY", function()
    BuildFrame()
    frame:HookScript("OnHide", function()
        if PVEFrame and PVEFrame:IsShown() and not ns.standalone then ns.userClosedThisSession = true end
    end)
end)

for _, message in ipairs({ "RESULTS_UPDATED", "SETTINGS_CHANGED", "RATING_UPDATED", "SPEC_CHANGED", "GEAR_UPDATED" }) do
    ns:On(message, function() ns:RefreshWindow() end)
end
ns:On("VOIDCORE_POOLS_UPDATED", function() if frame and frame.page == "voidcore" then ns:RefreshWindow() end end)
ns:On("SCAN_PROGRESS", function(index, total, name)
    ns.scanProgress = index and { index = index, total = total, name = name } or nil
    ns:RefreshWindow()
end)
Style.OnLooksChanged(function() ns:RefreshWindow() end)

-- The dungeon a hovered Group Finder listing is for lights up in the lists.
function ns:SetHighlightDungeon(mapID)
    if self.highlightMapID == mapID then return end
    self.highlightMapID = mapID
    self:RefreshWindow()
end
