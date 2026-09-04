-- Slot Filler: the widgets the window is built from. Buttons, tabs, a
-- dropdown menu, column headers, list panels and the pooled rows the tabs
-- fill. Everything is painted through Style.lua.
local _, ns = ...
local Style = ns.Style

local UI = {}
ns.UI = UI

-- Layout constants
UI.WIDTH = 390
UI.FREE_HEIGHT = 520
UI.PAD = 8            -- content inset from the window edge
UI.TITLE_H = 25       -- title band height
UI.TOOLBAR_H = 68     -- spec/key row, weights row and the info line, shared by the list tabs
UI.TAB_H, UI.TAB_W = 22, 70
UI.STRIP_H = 24       -- filter strip above a list's column header
UI.SECTION_H = 22     -- raid name above its bosses
UI.ROW_H = 28         -- dungeon / slot row
UI.ITEM_H = 20        -- drop row under an open row
UI.GUTTER = 12        -- scrollbar gutter right of a list
UI.COL_DROPS, UI.COL_WANTED = 56, 68
UI.IO_HEADER_H = 52   -- IO tab: rating/target row and runs/max key row
UI.COL_BEST, UI.COL_RUN, UI.COL_GAIN = 56, 44, 52
UI.COL_POOL, UI.COL_CHANCE, UI.COL_EGAIN, UI.COL_TARGET = 50, 46, 48, 44   -- Voidcore tab
UI.LADDER_ROWS = 5    -- key ladder under an open IO row
local RUNS_TAB_W = 22

local ROW_H, ITEM_H = UI.ROW_H, UI.ITEM_H
local ARROW_ATLAS = "Azerite-PointingArrow"
local STAR_ATLAS, STAR_FILE

local NONE, STAT, ILVL, TRACK, WANT = ns.UPGRADE_NONE, ns.UPGRADE_STAT, ns.UPGRADE_ILVL, ns.UPGRADE_TRACK, ns.UPGRADE_WANT
local HEX = ns.UPGRADE_HEX

-- Row pools, one per tab (the test harness reads them too).
UI.Pools = { dungeonRows = {}, dungeonItems = {}, raidRows = {}, raidItems = {}, raidHeaders = {},
    gearRows = {}, gearItems = {}, ioRows = {}, ioLadder = {}, rollRows = {}, rollItems = {} }

-- Which rows are open; nil = none.
ns.uiExpandedMapID = nil
ns.uiExpandedEncounterID = nil
ns.uiExpandedSlotID = nil
ns.uiExpandedRatingMapID = nil
ns.uiExpandedRollKey = nil      -- a Voidcore tab source listing its pool
ns.uiExpandedTokenID = nil      -- a tier token listing its piece(s)

-------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------
-- A tier token shown as the token, its piece(s) listed beneath on a click:
-- always for a token traded for any slot, by setting for the others.
function UI.TokenNested(eval)
    if not (eval and eval.pieces and eval.token) then return false end
    return #eval.pieces > 1 or ns.db.nestTokens ~= false
end

function UI.QualityHex(item)
    local q = item.link and item.link:match("|c(%x%x%x%x%x%x%x%x)")
    return q and ("|c" .. q) or "|cffffffff"
end

function UI.Tip(widget, anchor, title, ...)
    local lines = { ... }
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:AddLine(title)
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A single-line FontString with the given justification.
function UI.Line(parent, size, justify, r, g, b, a)
    local fs = Style.Text(parent, size, r, g, b, a)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Flat block button with a text label.
function UI.TextButton(parent, text, w, h, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 22)
    b.Text = Style.Text(b, size or 11)
    b.Text:SetPoint("CENTER", 0, 0)
    b.Text:SetText(text)
    Style.Button(b)
    return b
end

-- Title-bar glyph button (no block, like the close X).
function UI.GlyphButton(parent, atlas, size, file)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetPoint("CENTER", 0, 0)
    b.Icon:SetSize(size - 6, size - 6)
    if atlas then b.Icon:SetAtlas(atlas) else b.Icon:SetTexture(file) end
    b.Icon:SetVertexColor(1, 1, 1, 0.75)
    b:HookScript("OnEnter", function(self) self.Icon:SetVertexColor(1, 1, 1, 1) end)
    b:HookScript("OnLeave", function(self) self.Icon:SetVertexColor(1, 1, 1, 0.75) end)
    return b
end

function UI.Check(parent, size)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(size or 22, size or 22)
    Style.Checkbox(cb)
    return cb
end

-- Text input with the house look.
function UI.EditBox(parent, h)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetHeight(h or 20)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Style.EditBox(eb)
    return eb
end

function UI.StarTexture(parent, size)
    STAR_ATLAS = STAR_ATLAS or Style.FindAtlas({ "auctionhouse-icon-favorite", "PetJournal-FavoritesIcon" }) or false
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetSize(size, size)
    if STAR_ATLAS then t:SetAtlas(STAR_ATLAS) else t:SetTexture("Interface\\Common\\FavoritesIcon") end
    return t
end

-- Wanted star in the accent colour; the Voidcore star in purple.
function UI.SetStar(tex, on, voidcore)
    if on then
        local r, g, b = Style.Accent()
        if voidcore then r, g, b = unpack(ns.VC_COLOR) end
        tex:SetDesaturated(false)
        tex:SetVertexColor(r, g, b, 1)
    else
        tex:SetDesaturated(true)
        tex:SetVertexColor(1, 1, 1, 0.3)
    end
end

-- A chevron: the dropdown's, or a row's (rotated to point right when closed).
local function Arrow(parent, w, h, alpha)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetAtlas(ARROW_ATLAS)
    t:SetSize(w, h)
    t:SetVertexColor(1, 1, 1, alpha or 0.6)
    return t
end

-------------------------------------------------------------------------------
-- Dropdown: a block button showing the current choice; clicking it opens a
-- flat menu underneath. entries() returns { { text, checked, onClick }, ... }.
-- One menu frame serves every dropdown; it closes on a click anywhere else.
-------------------------------------------------------------------------------
local menu
local MENU_ROW_H = 20

function UI.CloseMenu()
    if menu and menu:IsShown() then menu:Hide() end
end

function UI.IsMenuShown()
    return (menu and menu:IsShown()) and true or false
end

local function MenuRow(i)
    local row = menu.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, menu)
    row:SetHeight(MENU_ROW_H)
    row:SetPoint("TOPLEFT", 1, -(1 + (i - 1) * MENU_ROW_H))
    row:SetPoint("TOPRIGHT", -1, -(1 + (i - 1) * MENU_ROW_H))
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.1)
    row.Mark = row:CreateTexture(nil, "ARTWORK")
    row.Mark:SetSize(6, 6)
    row.Mark:SetPoint("LEFT", 8, 0)
    row.Text = UI.Line(row, 11)
    row.Text:SetPoint("LEFT", 20, 0)
    row.Text:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnClick", function(self)
        UI.CloseMenu()
        if self.entry.onClick then self.entry.onClick() end
    end)
    menu.rows[i] = row
    return row
end

local function OpenMenu(owner, entries)
    if not menu then
        menu = CreateFrame("Frame", nil, UI.Frame or UIParent)
        menu:SetFrameStrata("HIGH")
        menu:EnableMouse(true)
        menu:Hide()
        menu.rows = {}
        Style.Panel(menu)
        menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
        menu:SetScript("OnEvent", function(self)
            if self:IsShown() and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
        end)
        menu:SetScript("OnHide", function(self) self.owner = nil end)
    end
    if menu:IsShown() and menu.owner == owner then UI.CloseMenu(); return end
    menu.owner = owner
    local r, g, b = Style.Accent()
    for i, entry in ipairs(entries) do
        local row = MenuRow(i)
        row.entry = entry
        row.Text:SetText(entry.text or "")
        row.Text:SetAlpha(entry.checked and 1 or 0.8)
        row.Mark:SetColorTexture(r, g, b, 1)
        row.Mark:SetShown(entry.checked and true or false)
        row:Show()
    end
    for i = #entries + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -1)
    menu:SetSize(math.max(owner:GetWidth() or 0, 120), #entries * MENU_ROW_H + 2)
    menu:Show()
end

-- w = nil leaves the width to the caller's anchors.
function UI.Dropdown(parent, w, h, entries)
    local b = CreateFrame("Button", nil, parent)
    if w then b:SetWidth(w) end
    b:SetHeight(h or 22)
    b.Arrow = Arrow(b, 12, 9, 0.7)
    b.Arrow:SetPoint("RIGHT", -6, 0)
    b.Text = UI.Line(b, 11)
    b.Text:SetPoint("LEFT", 6, 0)
    b.Text:SetPoint("RIGHT", b.Arrow, "LEFT", -4, 0)
    Style.Button(b, { "Arrow" })
    b.entries = entries
    b:SetScript("OnClick", function(self) OpenMenu(self, self.entries()) end)
    b:HookScript("OnHide", function(self) if menu and menu.owner == self then UI.CloseMenu() end end)
    return b
end

-- Weight profile picker (toolbar and Settings): the profiles saved for the
-- evaluated spec on this character, plus "None".
local function StatProfileEntries()
    local active = ns:GetActiveStatProfile()
    local entries = {}
    for i, scale in ipairs(ns:GetStatProfiles()) do
        entries[#entries + 1] = { text = tostring(scale.name), checked = active == i, onClick = function() ns:SetActiveStatProfile(i) end }
    end
    entries[#entries + 1] = { text = "None |cff888888(rank stats from gear)|r", checked = active == nil, onClick = function() ns:SetActiveStatProfile(nil) end }
    return entries
end

function UI.RefreshStatProfileButton(b)
    local _, scale = ns:GetActiveStatProfile()
    local changed = scale and #ns:StatProfileGearDiff(scale) or 0
    b.Text:SetText("|cffaaaaaaWeights:|r " .. (scale and scale.name or "|cff888888none|r") .. (changed > 0 and "  |cffff9900(gear changed)|r" or ""))
end

local function StatProfileTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Stat weights")
    local _, scale = ns:GetActiveStatProfile()
    if scale then
        GameTooltip:AddLine(tostring(scale.name), 1, 1, 1)
        GameTooltip:AddLine(ns:StatWeightsText(scale), 0.8, 0.8, 0.8, true)
        if scale.pawnName and scale.pawnName ~= scale.name then
            GameTooltip:AddLine("Pawn scale: " .. tostring(scale.pawnName), 0.6, 0.6, 0.6, true)
        end
        local set = ns:StatProfileSet(scale)
        if set then GameTooltip:AddLine("Follows the " .. set .. " equipment set: switched to when you wear it.", 0.6, 0.6, 0.6, true) end
        local diff = ns:StatProfileGearDiff(scale)
        if #diff > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("|cffff9900Gear changed since these weights were made|r (%d slot%s):", #diff, #diff == 1 and "" or "s"), 1, 1, 1, true)
            for i, d in ipairs(diff) do
                if i > 6 then GameTooltip:AddLine("  ...", 0.7, 0.7, 0.7); break end
                local slot = ns.SLOT_BY_ID[d.slotID]
                GameTooltip:AddLine(string.format("  %s: %s -> %s", slot and (slot.name or slot.key) or "?",
                    d.from and (d.from.name or ("item " .. tostring(d.from.itemID))) or "empty",
                    d.to and ns.ItemName(d.to) or "empty"), 0.8, 0.8, 0.8, true)
            end
            if scale.amrSetup then
                GameTooltip:AddLine("This is the gear of the " .. scale.amrSetup .. " setup from Ask Mr. Robot; wear that set, or re-sim and paste the new Pawn string.", 0.8, 0.8, 0.8, true)
            else
                GameTooltip:AddLine("Weights shift with the gear they were simmed for: re-run Ask Mr. Robot and paste the new Pawn string in Settings.", 0.8, 0.8, 0.8, true)
            end
        elseif scale.gear then
            GameTooltip:AddLine(scale.amrSetup and ("|cff888888Made for the " .. scale.amrSetup .. " setup's gear, which you wear now.|r") or "|cff888888Made for the gear you wear now.|r", 1, 1, 1, true)
        end
    else
        GameTooltip:AddLine("No profile in use: stats are ranked by how much of each your equipped gear carries.", 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to switch between the weight profiles saved for this spec. Every Pawn string imported in Settings becomes one, so you can keep a Raid and a Mythic+ profile and swap here.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

function UI.StatProfileDropdown(parent, w, h)
    local b = UI.Dropdown(parent, w, h, StatProfileEntries)
    b:HookScript("OnEnter", StatProfileTooltip)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    UI.RefreshStatProfileButton(b)
    return b
end

-------------------------------------------------------------------------------
-- Tabs and headers
-------------------------------------------------------------------------------
local function NewTab(parent, w, h, text, tabID)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(w, h)
    tab.Text = Style.Text(tab, 11)
    tab.Text:SetPoint("CENTER", 0, 0)
    tab.Text:SetText(text)
    tab.tabID = tabID
    return tab
end

-- A row of small tabs. defs = { { id, text, tip }, ... }; onSelect(id).
function UI.TabStrip(parent, defs, w, onSelect)
    local tabs = CreateFrame("Frame", nil, parent)
    tabs:SetSize(#defs * w + (#defs - 1), 20)
    tabs.Tabs = {}
    local prev
    for _, def in ipairs(defs) do
        local tab = NewTab(tabs, w, 20, def[2], def[1])
        if prev then tab:SetPoint("LEFT", prev, "RIGHT", 1, 0) else tab:SetPoint("LEFT", 0, 0) end
        tab:SetScript("OnClick", function(self)
            Style.SelectTab(tabs, self.tabID)
            onSelect(self.tabID)
        end)
        Style.Tab(tab)
        if def[3] then UI.Tip(tab, "ANCHOR_TOP", def[2], def[3]) end
        tabs.Tabs[def[1]] = tab
        prev = tab
    end
    return tabs
end

-- Plan picker for the IO tab: one tab per plan, labelled by its run count.
-- SetPlans(plans, selected) relabels the tabs and shows one per plan.
function UI.RunsStrip(parent, maxTabs, onSelect)
    local tabs = CreateFrame("Frame", nil, parent)
    tabs:SetSize(RUNS_TAB_W, 20)
    tabs.Tabs = {}
    local prev
    for i = 1, maxTabs do
        local tab = NewTab(tabs, RUNS_TAB_W, 20, "", i)
        if prev then tab:SetPoint("LEFT", prev, "RIGHT", 1, 0) else tab:SetPoint("LEFT", 0, 0) end
        tab:SetScript("OnClick", function(self)
            if not self.plan then return end
            Style.SelectTab(tabs, self.tabID)
            onSelect(self.plan)
        end)
        tab:SetScript("OnEnter", function(self)
            local p = self.plan
            if not p then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if p.partial then
                GameTooltip:AddLine("Out of reach")
                GameTooltip:AddLine(string.format("Every dungeon at +%d reaches %d.", p.maxLevel, ns:Round(p.reach or 0)), 0.8, 0.8, 0.8)
            else
                GameTooltip:AddLine(p.fastest and "Fastest" or p.easiest and "Easiest" or string.format("Plan %d of %d", p.index or 1, p.of or 1))
                GameTooltip:AddLine(string.format("%d run%s, keys up to +%d: +%d, rating %d.", p.count, p.count == 1 and "" or "s", p.maxLevel,
                    ns:Round(p.total), ns:Round((ns:OverallRating() or 0) + p.total)), 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
        Style.Tab(tab)
        tabs.Tabs[i] = tab
        prev = tab
    end
    function tabs:SetPlans(plans, selected)
        local n = math.min(#plans, maxTabs)
        for i, tab in ipairs(self.Tabs) do
            local p = plans[i]
            tab.plan = p
            if p and i <= n then
                tab.tabID = p.count
                tab.Text:SetText(p.partial and "Max" or tostring(p.count))
                tab:Show()
            else
                tab.tabID = -i
                tab:Hide()
            end
        end
        self:SetWidth(math.max(1, n * RUNS_TAB_W + math.max(0, n - 1)))
        local id = selected and selected.count or nil
        if self.selectedTabID ~= id then Style.SelectTab(self, id) end
    end
    return tabs
end

-- Column header tabs above a list: a full-width first tab plus fixed-width
-- columns. defs = { { id, text, width|nil, tip }, ... }; onSelect(id) sets the sort.
function UI.ColumnHeader(page, defs, onSelect, top)
    local colHead = CreateFrame("Frame", nil, page)
    colHead:SetPoint("TOPLEFT", 0, -(top or 0))
    colHead:SetPoint("TOPRIGHT", -UI.GUTTER, -(top or 0))
    colHead:SetHeight(20)
    local prev
    for i = #defs, 1, -1 do
        local def = defs[i]
        local tab = NewTab(colHead, def[3] or 1, 20, def[2], def[1])
        if not def[3] then tab:SetPoint("LEFT", 0, 0) end
        if prev then tab:SetPoint("RIGHT", prev, "LEFT", -1, 0) else tab:SetPoint("RIGHT", 0, 0) end
        tab:SetScript("OnClick", function()
            onSelect(def[1])
            Style.SelectTab(colHead, def[1])
            ns:Fire("SETTINGS_CHANGED")
        end)
        Style.Tab(tab)
        if def[4] then UI.Tip(tab, "ANCHOR_TOP", def[2], def[4]) end
        prev = tab
    end
    return colHead
end

-- A filter strip along the top of a page (label on the left).
function UI.Strip(page, label)
    local strip = CreateFrame("Frame", nil, page)
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", -UI.GUTTER, 0)
    strip:SetHeight(20)
    if label then
        strip.Label = Style.Text(strip, 11, 1, 1, 1, 0.53)
        strip.Label:SetPoint("LEFT", 4, 0)
        strip.Label:SetText(label)
    end
    return strip
end

-- Inset list panel with a scroll frame under a column header; returns list, content.
function UI.ListPanel(page, colHead, bottom)
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", colHead, "BOTTOMLEFT", 0, -3)
    list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, bottom)
    Style.Panel(list, { inset = true })
    local scroll, _, content = Style.ScrollFrame(list, UI.WIDTH - 2 * UI.PAD - UI.GUTTER - 4)
    scroll:SetPoint("TOPLEFT", 2, -2)
    scroll:SetPoint("BOTTOMRIGHT", -UI.GUTTER, 2)
    return list, content
end

-- Status line and scan progress bar along the bottom of a list page.
function UI.StatusLine(page)
    page.Status = UI.Line(page, 10, "LEFT", 1, 1, 1, 0.53)
    page.Status:SetPoint("BOTTOMLEFT", 2, 2)
    page.Status:SetPoint("BOTTOMRIGHT", -2, 2)
    local progress = CreateFrame("StatusBar", nil, page)
    progress:SetPoint("BOTTOMLEFT", 0, 16)
    progress:SetPoint("BOTTOMRIGHT", 0, 16)
    progress:SetHeight(2)
    progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    progress:SetMinMaxValues(0, 1)
    progress:SetValue(0)
    progress:Hide()
    Style.BarFill(progress)
    page.Progress = progress
end

-------------------------------------------------------------------------------
-- Rows
-------------------------------------------------------------------------------
-- Right-aligned, centred columns from the right edge inward:
-- defs = { { "Gain", COL_GAIN }, { "Run", COL_RUN }, ... }. Returns the leftmost.
local function Columns(row, defs, size, inset)
    local prev
    for _, def in ipairs(defs) do
        local fs = UI.Line(row, size, "CENTER")
        fs:SetWidth(def[2])
        if prev then fs:SetPoint("RIGHT", prev, "LEFT", -1, 0) else fs:SetPoint("RIGHT", -inset, 0) end
        row[def[1]] = fs
        prev = fs
    end
    return prev
end

local function Clickable(row, onClick, onRightClick, onEnter)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if onRightClick then onRightClick(self) end
        else
            onClick(self)
        end
    end)
    row.tipFn = onEnter
    row:SetScript("OnEnter", function(self) ns.hoveredTip = self; onEnter(self) end)
    row:SetScript("OnLeave", function() ns.hoveredTip = nil; GameTooltip:Hide() end)
end

-- A list row: icon, chevron, name and right-aligned columns (see Columns);
-- `rightInset` is the gap the first column leaves at the right edge.
function UI.NewRow(content, defs, onClick, onRightClick, onEnter, rightInset)
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)
    row.Bg = row:CreateTexture(nil, "BACKGROUND")
    row.Bg:SetAllPoints()
    row.Bg:SetColorTexture(1, 1, 1, 0)
    row.Hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.Hover:SetAllPoints()
    row.Hover:SetColorTexture(1, 1, 1, 0.06)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(ROW_H - 6, ROW_H - 6)
    row.Icon:SetPoint("LEFT", 4, 0)
    Style.SquareIcon(row.Icon, row)
    row.Border = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.Border:SetPoint("TOPLEFT", row.Icon, "TOPLEFT", -1, 1)
    row.Border:SetPoint("BOTTOMRIGHT", row.Icon, "BOTTOMRIGHT", 1, -1)
    row.Border:SetColorTexture(0, 0, 0, 1)
    row.Arrow = Arrow(row, 10, 7)
    row.Arrow:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
    local leftmost = Columns(row, defs, 12, rightInset or 2)
    row.Name = UI.Line(row, 12)
    row.Name:SetPoint("LEFT", row.Arrow, "RIGHT", 6, 0)
    row.Name:SetPoint("RIGHT", leftmost, "LEFT", -4, 0)
    Clickable(row, onClick, onRightClick, onEnter)
    return row
end

-- Dungeon, boss or slot row: Drops and Wanted columns, a star for wanted
-- items and a purple one when a Voidcore target drops there.
function UI.NewTopRow(content, onClick, onRightClick, onEnter)
    local row = UI.NewRow(content, { { "Count", UI.COL_DROPS } }, onClick, onRightClick, onEnter, UI.COL_WANTED + 1)
    row.Wanted = UI.Line(row, 12)
    row.Wanted:SetPoint("RIGHT", -14, 0)
    row.Wanted:SetWidth(22)
    row.WantIcon = UI.StarTexture(row, 12)
    row.WantIcon:SetPoint("RIGHT", row.Wanted, "LEFT", -3, 0)
    row.VCIcon = UI.StarTexture(row, 11)
    row.VCIcon:SetPoint("RIGHT", -1, 0)
    UI.SetStar(row.VCIcon, true, true)
    row.VCIcon:Hide()
    return row
end

-- Key ladder row under an open IO row: level, score and gain.
function UI.NewLadderRow(content)
    local it = CreateFrame("Frame", nil, content)
    it:SetHeight(ITEM_H)
    it.Bg = it:CreateTexture(nil, "BACKGROUND")
    it.Bg:SetAllPoints()
    it.Bg:SetColorTexture(1, 1, 1, 0)
    local leftmost = Columns(it, { { "Gain", UI.COL_GAIN }, { "Score", UI.COL_RUN } }, 11, 2)
    it.Level = UI.Line(it, 11)
    it.Level:SetPoint("LEFT", ROW_H + 6, 0)
    it.Level:SetPoint("RIGHT", leftmost, "LEFT", -4, 0)
    return it
end

-- Raid name above its bosses when the season has more than one raid.
function UI.NewSectionRow(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetHeight(UI.SECTION_H)
    f.Text = UI.Line(f, 11, "LEFT", 1, 1, 1, 0.6)
    f.Text:SetPoint("LEFT", 6, 0)
    f.Text:SetPoint("RIGHT", -6, 0)
    f.Line = f:CreateTexture(nil, "ARTWORK")
    f.Line:SetHeight(1)
    f.Line:SetPoint("BOTTOMLEFT", 4, 2)
    f.Line:SetPoint("BOTTOMRIGHT", -4, 2)
    f.Line:SetColorTexture(1, 1, 1, 0.08)
    return f
end

-- A star button on a drop row. onClick(itemID); tip(on) returns title, text.
local function StarButton(it, size, voidcore, onClick, tip)
    local b = CreateFrame("Button", nil, it)
    b:SetSize(18, 18)
    b.Icon = UI.StarTexture(b, size)
    b.Icon:SetPoint("CENTER", 0, 0)
    b:SetScript("OnClick", function(self)
        local eval = self:GetParent().eval
        if eval then onClick(eval.item.itemID) end
    end)
    b:SetScript("OnEnter", function(self)
        local eval = self:GetParent().eval
        local on = false
        if eval and voidcore then on = ns:IsVoidcoreTarget(eval.item.itemID)
        elseif eval then on = ns:GetItemState(eval.item.itemID) == "want" end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local title, text = tip(on)
        GameTooltip:AddLine(title)
        GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Drop row under an open dungeon, boss, slot or Voidcore source. `wide`
-- widens the Where column for a source name instead of a slot.
function UI.NewItemRow(content, wide)
    local it = CreateFrame("Button", nil, content)
    it:SetHeight(ITEM_H)
    it.Hover = it:CreateTexture(nil, "HIGHLIGHT")
    it.Hover:SetAllPoints()
    it.Hover:SetColorTexture(1, 1, 1, 0.06)
    it.Icon = it:CreateTexture(nil, "ARTWORK")
    it.Icon:SetSize(ITEM_H - 4, ITEM_H - 4)
    it.Icon:SetPoint("LEFT", ROW_H + 6, 0)
    Style.SquareIcon(it.Icon, it)
    -- a tier token opens into its piece(s)
    it.Arrow = Arrow(it, 8, 6)
    it.Arrow:SetPoint("RIGHT", it.Icon, "LEFT", -4, 0)
    it.Arrow:Hide()
    it.Star = StarButton(it, 14, false, function(id)
        ns:SetItemState(id, ns:GetItemState(id) ~= "want" and "want" or nil)
    end, function(on)
        return on and "On your wanted list" or "Add to wanted list",
            on and "Click to remove it." or "Wanted items count for their dungeon or boss. They leave the list by themselves once you have the item."
    end)
    it.Star:SetPoint("RIGHT", -4, 0)
    it.VC = StarButton(it, 14, true, function(id)
        ns:SetVoidcoreTarget(id, not ns:IsVoidcoreTarget(id))
    end, function(on)
        return on and (ns.VC_HEX .. "Voidcore target|r") or "Voidcore target",
            on and "Click to unmark it." or "Click: this is what you would spend a Nebulous Voidcore on."
    end)
    it.VC:SetPoint("RIGHT", it.Star, "LEFT", -1, 0)
    it.Gain = UI.Line(it, 10, "RIGHT")
    it.Gain:SetPoint("RIGHT", it.VC, "LEFT", -4, 0)
    it.Gain:SetWidth(56)
    it.Stats = UI.Line(it, 10, "RIGHT")
    it.Stats:SetPoint("RIGHT", it.Gain, "LEFT", -4, 0)
    it.Stats:SetWidth(46)
    it.Where = UI.Line(it, 10, "RIGHT", 1, 1, 1, 0.55)
    it.Where:SetPoint("RIGHT", it.Stats, "LEFT", -4, 0)
    it.Where:SetWidth(wide and 92 or 36)
    it.Name = UI.Line(it, 11)
    it.Name:SetPoint("LEFT", it.Icon, "RIGHT", 6, 0)
    it.Name:SetPoint("RIGHT", it.Where, "LEFT", -4, 0)
    Clickable(it, function(self)
        local eval = self.eval
        if not eval then return end
        if IsModifiedClick("CHATLINK") and eval.item.link then
            ChatEdit_InsertLink(eval.item.link)
        elseif IsModifiedClick("DRESSUP") and eval.item.link then
            DressUpItemLink(eval.item.link)
        elseif UI.TokenNested(eval) then
            local id = eval.token.itemID
            ns.uiExpandedTokenID = (ns.uiExpandedTokenID ~= id) and id or nil
            ns:RefreshWindow()
        end
    end, function(self)
        local eval = self.eval
        if not eval then return end
        if self.roll and self.source then
            ns:ToggleRolled(self.source, (eval.token or eval.item).itemID)
        else
            ns:CycleItemState(eval.item.itemID)
        end
    end, function(self)
        if self.eval then ns:ShowItemTooltip(self) end
    end)
    return it
end

-- The verdict text in a drop row's Gain column.
local function GainText(verdict, eval, state)
    if state == "exclude" then return "|cffff5555excluded|r" end
    if verdict.reason == "owned" then return eval.owned and eval.owned.catalyzed and "|cff888888catalyzed|r" or "|cff888888owned|r" end
    if verdict.class == STAT then return HEX[STAT] .. "stats|r" end
    if not verdict.gain then return "" end
    if verdict.class == TRACK then return string.format("%s%+d|r|cff888888/%+d|r", HEX[TRACK], verdict.gain, verdict.potentialGain or 0) end
    if verdict.class == ILVL then return string.format("%s%+d|r", HEX[ILVL], verdict.gain) end
    if verdict.class == WANT then return string.format("%s%+d|r", verdict.gain > 0 and HEX[ILVL] or "|cff777777", verdict.gain) end
    return string.format("|cff777777%+d|r", verdict.gain)
end

-- Fills a drop row. `whereText` replaces the slot text when given.
-- `verdict` (default the eval itself) is the class/gain shown: the roll's
-- verdict on the Voidcore tab.
function UI.FillItemRow(it, eval, whereText, verdict)
    verdict = verdict or eval
    local id = eval.item.itemID
    local state, target = ns:GetItemState(id), ns:IsVoidcoreTarget(id)
    local lit = ns:CountsAsUpgrade(verdict) or state == "want" or target
    it.eval = eval
    local nested = UI.TokenNested(eval)
    local shown = nested and eval.token or eval.item
    it.Icon:SetTexture(shown.icon or 134400)
    it.Icon:SetDesaturated(not lit)
    it.Arrow:SetShown(nested)
    if nested then it.Arrow:SetRotation(ns.uiExpandedTokenID == eval.token.itemID and 0 or math.rad(90)) end
    local slot = eval.slotID and ns.SLOT_BY_ID[eval.slotID]
    it.Where:SetText(whereText or (slot and slot.short) or eval.item.slotText or "")
    it.Name:SetText(lit and (UI.QualityHex(shown) .. ns.ItemName(shown) .. "|r") or ns.ItemName(shown))
    it.Name:SetAlpha(lit and 1 or 0.45)
    it.Gain:SetText(GainText(verdict, eval, state))
    it.Stats:SetText(ns:StatText(eval.stats, eval.fit))
    UI.SetStar(it.Star.Icon, state == "want")
    it.Star:Show()
    UI.SetStar(it.VC.Icon, target, true)
    it.VC:SetShown(not eval.item.noRoll)
end

function UI.FillNoteRow(it, text)
    it.eval = nil
    it.Arrow:Hide()
    it.Icon:SetTexture(nil)
    it.Where:SetText("")
    it.Name:SetText("|cff888888" .. text .. "|r")
    it.Name:SetAlpha(1)
    it.Gain:SetText("")
    it.Stats:SetText("")
    it.Star:Hide()
    it.VC:Hide()
end

function UI.SetRowCounts(row, count, wanted, scanned, voidcore)
    if not scanned then
        row.Count:SetText("|cff888888...|r")
        row.Wanted:SetText("")
        row.WantIcon:Hide()
        row.VCIcon:Hide()
        return
    end
    row.Count:SetText(count)
    if wanted > 0 then
        row.Wanted:SetText(Style.AccentHex() .. wanted .. "|r")
        UI.SetStar(row.WantIcon, true)
        row.WantIcon:Show()
    else
        row.Wanted:SetText("|cff444444-|r")
        row.WantIcon:Hide()
    end
    row.VCIcon:SetShown((voidcore or 0) > 0)
end

function UI.RowBackground(row, index, expanded, highlighted)
    if highlighted then
        local r, g, b = Style.Accent()
        row.Bg:SetColorTexture(r, g, b, 0.25)
    elseif expanded then
        row.Bg:SetColorTexture(1, 1, 1, 0.06)
    elseif index % 2 == 0 then
        row.Bg:SetColorTexture(1, 1, 1, 0.03)
    else
        row.Bg:SetColorTexture(1, 1, 1, 0)
    end
end

-------------------------------------------------------------------------------
-- Layout: rows taken from pools and stacked down a content frame.
-------------------------------------------------------------------------------
local Layout = {}
Layout.__index = Layout

function UI.Layout(content)
    return setmetatable({ content = content, y = 0, used = {} }, Layout)
end

-- The next row from `pool` (made by `factory` when the pool runs short),
-- placed at the cursor, `indent` from the left; the cursor moves `height` down.
function Layout:Add(pool, factory, height, indent)
    local i = (self.used[pool] or 0) + 1
    self.used[pool] = i
    local w = pool[i]
    if not w then w = factory(); pool[i] = w end
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", self.content, "TOPLEFT", indent or 0, -self.y)
    w:SetWidth(self.content:GetWidth() - (indent or 0))
    w:Show()
    self.y = self.y + height
    return w
end

-- How many rows of `pool` are placed so far (the row's index for striping).
function Layout:Count(pool)
    return self.used[pool] or 0
end

function Layout:Gap(h)
    self.y = self.y + h
end

-- Hides the unused rows of the given pools and sizes the content.
function Layout:Finish(...)
    for _, pool in ipairs({ ... }) do
        for i = (self.used[pool] or 0) + 1, #pool do pool[i]:Hide() end
    end
    self.content:SetHeight(math.max(self.y, 1))
end

-- Tooltips show the Voidcore roll while Shift is held: redraw the hovered
-- row's tooltip when Shift changes.
ns:RegisterEvent("MODIFIER_STATE_CHANGED", function(key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
    local row = ns.hoveredTip
    if row and row.tipFn and row:IsMouseOver() then row.tipFn(row) end
end)
