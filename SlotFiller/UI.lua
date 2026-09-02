-- Slot Filler: main window. Three tabs (Dungeons, Gear, Settings) in a shell
-- that EllesmereUI paints when present (see Style.lua). Docks to the left of
-- the Dungeons & Raids window, tabs hanging under the frame like its own.
--
-- Dungeons: dungeon rows that open into the drops they hold.
-- Gear:     slot rows that open into every drop for that slot, from all
--           dungeons, ordered by stat compatibility, so same-slot drops can
--           be compared and starred.
local _, ns = ...
local Style = ns.Style

local WIDTH = 390
local FREE_HEIGHT = 520
local PAD = 8            -- content inset from the window edge
local TITLE_H = 25       -- EllesmereUI title band height
local TOOLBAR_H = 44     -- spec/key controls + info line, shared by the list tabs
local TAB_H, TAB_W = 22, 96
local ROW_H = 28         -- dungeon / slot row
local ITEM_H = 20        -- drop row under an expanded row
local GUTTER = 12        -- scrollbar gutter right of a list
local COL_DROPS, COL_WANTED = 56, 68

local frame
local dungeonRows, dungeonItems = {}, {}
local gearRows, gearItems = {}, {}
ns.uiExpandedMapID = nil
ns.uiExpandedSlotID = nil

local NONE, ILVL, TRACK, WANT = ns.UPGRADE_NONE, ns.UPGRADE_ILVL, ns.UPGRADE_TRACK, ns.UPGRADE_WANT
local ARROW_ATLAS = "Azerite-PointingArrow"
local STAR_ATLAS, STAR_FILE

local function Color(class)
    local c = ns.UPGRADE_COLOR[class] or ns.UPGRADE_COLOR[0]
    return c[1], c[2], c[3]
end

local function Hex(class)
    local r, g, b = Color(class)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function TrackText(track, step)
    if not track then return "" end
    if step then
        return string.format("%s %d/%d", ns:TrackDisplayName(track), step, track.steps)
    end
    return ns:TrackDisplayName(track)
end

local function ItemName(item)
    return item.link and item.link:match("%[(.-)%]") or item.name or ("item " .. tostring(item.itemID))
end

local function QualityHex(item)
    local q = item.link and item.link:match("|c(%x%x%x%x%x%x%x%x)")
    return q and ("|c" .. q) or "|cffffffff"
end

-------------------------------------------------------------------------------
-- Equipped item description
-------------------------------------------------------------------------------
local function EquippedDesc(g)
    if not g or g.empty then return "empty slot" end
    local s = string.format("%d", g.ilvl or 0)
    if g.track and g.cur then
        s = s .. string.format("  %s %d/%d", ns:TrackDisplayName(g.track), g.cur, g.max or g.track.steps)
        if g.potential and g.potential > (g.ilvl or 0) then
            s = s .. string.format("  (up to %d)", g.potential)
        end
    elseif g.cur and g.max then
        s = s .. string.format("  %s %d/%d", g.trackName or "?", g.cur, g.max)
    end
    return s
end

local function EquippedShort(g)
    if not g or g.empty then return "|cffff5555empty|r" end
    local s = string.format("|cffffffff%d|r", g.ilvl or 0)
    if g.track and g.cur then
        s = s .. string.format(" |cffaaaaaa%s %d/%d|r", ns:TrackDisplayName(g.track), g.cur, g.max or g.track.steps)
    elseif g.cur and g.max then
        s = s .. string.format(" |cffaaaaaa%s %d/%d|r", g.trackName or "?", g.cur, g.max)
    end
    return s
end

-------------------------------------------------------------------------------
-- Widget helpers
-------------------------------------------------------------------------------
local function Tip(widget, anchor, title, ...)
    local lines = { ... }
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:AddLine(title)
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Flat block button with a text label.
local function TextButton(parent, text, w, h, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 22)
    b.Text = Style.Text(b, size or 11)
    b.Text:SetPoint("CENTER", 0, 0)
    b.Text:SetText(text)
    Style.Button(b)
    return b
end

-- Title-bar glyph button (no block, like the close X).
local function GlyphButton(parent, atlas, size, file)
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

local function Check(parent, size)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(size or 22, size or 22)
    Style.Checkbox(cb)
    return cb
end

local function StarTexture(parent, size)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetSize(size, size)
    if STAR_ATLAS then t:SetAtlas(STAR_ATLAS) else t:SetTexture(STAR_FILE) end
    return t
end

local function SetStar(tex, on)
    if on then
        local r, g, b = Style.Accent()
        tex:SetDesaturated(false)
        tex:SetVertexColor(r, g, b, 1)
    else
        tex:SetDesaturated(true)
        tex:SetVertexColor(1, 1, 1, 0.3)
    end
end

ns.UI = { TextButton = TextButton, Check = Check, Tip = Tip }

-- Column header tabs shared by both list tabs: a full-width first tab plus
-- fixed Drops and Wanted columns. defs = { { id, text, width|nil }, ... }
local function ColumnHeader(page, defs, onSelect)
    local colHead = CreateFrame("Frame", nil, page)
    colHead:SetPoint("TOPLEFT", 0, 0)
    colHead:SetPoint("TOPRIGHT", -GUTTER, 0)
    colHead:SetHeight(20)
    local prev
    for i = #defs, 1, -1 do
        local def = defs[i]
        local tab = CreateFrame("Button", nil, colHead)
        tab:SetHeight(20)
        if def[3] then tab:SetWidth(def[3]) end
        tab.Text = Style.Text(tab, 11)
        tab.Text:SetPoint("CENTER", 0, 0)
        tab.Text:SetText(def[2])
        tab.tabID = def[1]
        tab:SetScript("OnClick", function()
            onSelect(def[1])
            Style.SelectTab(colHead, def[1])
            ns:Fire("SETTINGS_CHANGED")
        end)
        Style.Tab(tab)
        if prev then
            tab:SetPoint("RIGHT", prev, "LEFT", -1, 0)
        else
            tab:SetPoint("RIGHT", 0, 0)
        end
        if not def[3] then tab:SetPoint("LEFT", 0, 0) end
        if def[4] then Tip(tab, "ANCHOR_TOP", def[2], def[4]) end
        prev = tab
    end
    return colHead
end

-- Inset list panel with a scroll frame; returns list, content.
local function ListPanel(page, colHead, bottom)
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", colHead, "BOTTOMLEFT", 0, -3)
    list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, bottom)
    Style.Panel(list, { inset = true })
    local scroll, _, content = Style.ScrollFrame(list, WIDTH - 2 * PAD - GUTTER - 4)
    scroll:SetPoint("TOPLEFT", 2, -2)
    scroll:SetPoint("BOTTOMRIGHT", -GUTTER, 2)
    return list, content
end

-------------------------------------------------------------------------------
-- Toolbar: spec selector, key stepper and the info line (Dungeons and Gear)
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
    specBtn.Arrow:SetAtlas(ARROW_ATLAS)
    specBtn.Arrow:SetSize(12, 9)
    specBtn.Arrow:SetPoint("RIGHT", -6, 0)
    specBtn.Arrow:SetVertexColor(1, 1, 1, 0.7)
    specBtn.Text = Style.Text(specBtn, 11)
    specBtn.Text:SetPoint("LEFT", specBtn.Icon, "RIGHT", 5, 0)
    specBtn.Text:SetPoint("RIGHT", specBtn.Arrow, "LEFT", -4, 0)
    specBtn.Text:SetJustifyH("LEFT")
    specBtn.Text:SetWordWrap(false)
    Style.Button(specBtn, { "Icon", "Arrow" })
    specBtn:SetScript("OnClick", function() ns:CycleEvalSpec() end)
    Tip(specBtn, "ANCHOR_BOTTOM", "Spec to evaluate",
        "Click to cycle: follow loot spec, or a specific spec.",
        "Loot is filtered the same way the Adventure Guide filters it. The wanted list is kept per spec.")
    bar.SpecButton = specBtn

    local keyPlus = TextButton(bar, "+", 22, 22, 13)
    keyPlus:SetPoint("TOPRIGHT", 0, 0)
    keyPlus:SetScript("OnClick", function() ns:StepTargetKey(1) end)
    local keyBox = CreateFrame("Frame", nil, bar)
    keyBox:SetSize(64, 22)
    keyBox:SetPoint("RIGHT", keyPlus, "LEFT", -1, 0)
    Style.Panel(keyBox, { inset = true })
    local keyText = Style.Text(keyBox, 12)
    keyText:SetPoint("CENTER", 0, 0)
    local keyMinus = TextButton(bar, "-", 22, 22, 13)
    keyMinus:SetPoint("RIGHT", keyBox, "LEFT", -1, 0)
    keyMinus:SetScript("OnClick", function() ns:StepTargetKey(-1) end)
    local keyLabel = Style.Text(bar, 11, 1, 1, 1, 0.53)
    keyLabel:SetPoint("RIGHT", keyMinus, "LEFT", -6, 0)
    keyLabel:SetText("Key")
    bar.KeyText, bar.KeyPlus, bar.KeyMinus = keyText, keyPlus, keyMinus
    for _, b in ipairs({ keyPlus, keyMinus }) do
        Tip(b, "ANCHOR_BOTTOM", "Key level",
            "Drops are judged at the end-of-dungeon item level of this key. One step past the last key that still raises it, the selector becomes Voidcore and judges the bonus roll (vault item level) instead.")
    end

    local info = Style.Text(bar, 10, 1, 1, 1, 0.6)
    info:SetPoint("TOPLEFT", 2, -28)
    info:SetPoint("TOPRIGHT", -2, -28)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(false)
    bar.Info = info
end

-------------------------------------------------------------------------------
-- Dungeons page
-------------------------------------------------------------------------------
local function BuildDungeonsPage(page)
    local colHead = ColumnHeader(page, {
        { "name", "Dungeon", nil, "Click to sort by name. Click a dungeon to see its drops." },
        { "upgrades", "Drops", COL_DROPS, "Spec-usable items that would upgrade a slot as an end-of-dungeon drop at the selected key. Click to sort." },
        { "wanted", "Wanted", COL_WANTED, "Items from your wanted list that drop in this dungeon. Spend Voidcores where this is highest. Click to sort." },
    }, function(mode) ns.db.sortMode = mode end)
    page.ColHead = colHead
    page.List, page.Content = ListPanel(page, colHead, 18)

    local status = Style.Text(page, 10, 1, 1, 1, 0.53)
    status:SetPoint("BOTTOMLEFT", 2, 2)
    status:SetPoint("BOTTOMRIGHT", -2, 2)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    page.Status = status
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
-- Gear page
-------------------------------------------------------------------------------
local function BuildGearPage(page)
    local colHead = ColumnHeader(page, {
        { "slot", "Slot", nil, "Click a slot to compare every drop for it across dungeons. Click here to sort by slot." },
        { "upgrades", "Drops", COL_DROPS, "Upgrade drops available for the slot at the selected key. Click to sort." },
        { "wanted", "Wanted", COL_WANTED, "Wanted items for the slot. Click to sort." },
    }, function(mode) ns.db.gearSort = mode end)
    page.ColHead = colHead
    page.List, page.Content = ListPanel(page, colHead, 18)

    local hint = Style.Text(page, 10, 1, 1, 1, 0.53)
    hint:SetPoint("BOTTOMLEFT", 2, 2)
    hint:SetPoint("BOTTOMRIGHT", -2, 2)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    hint:SetText("Drops are ordered by how well their stats fit you. Star the one you want. Right-click a slot: Auto / Want / Skip.")
    page.Hint = hint
end

-------------------------------------------------------------------------------
-- Frame construction
-------------------------------------------------------------------------------
local function BuildFrame()
    if frame then return frame end
    STAR_ATLAS = Style.FindAtlas({ "auctionhouse-icon-favorite", "PetJournal-FavoritesIcon" })
    STAR_FILE = "Interface\\Common\\FavoritesIcon"

    frame = CreateFrame("Frame", "SlotFillerFrame", UIParent)
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
            local point, _, relPoint, x, y = frame:GetPoint(1)
            ns.db.freePos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)
    frame.TitleBar = title

    local titleText = Style.Text(title, 12)
    titleText:SetPoint("LEFT", 10, 0)
    titleText:SetText("Slot Filler")
    frame.TitleText = titleText
    Style.OnLooksChanged(function()
        local r, g, b = Style.Accent()
        titleText:SetTextColor(r, g, b)
    end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -1, -1)
    close:SetSize(24, 24)
    close:SetScript("OnClick", function() ns:HideWindow(true) end)
    Style.CloseButton(close)
    frame.CloseButton = close

    local refreshAtlas = Style.FindAtlas({ "UI-RefreshButton", "uitools-icon-refresh" })
    local rescan
    if refreshAtlas then
        rescan = GlyphButton(title, refreshAtlas, 20)
    else
        rescan = TextButton(title, "Rescan", 52, 18, 10)
    end
    rescan:SetPoint("RIGHT", close, "LEFT", -2, 0)
    rescan:SetScript("OnClick", function() ns:RescanLoot(true) end)
    Tip(rescan, "ANCHOR_BOTTOM", "Rescan loot tables",
        "Re-reads every dungeon's loot from the Adventure Guide for the selected spec.")
    frame.RescanButton = rescan

    BuildToolbar()

    -- pages
    frame.Pages = {}
    local function NewPage(key, top)
        local p = CreateFrame("Frame", nil, frame)
        p:SetPoint("TOPLEFT", PAD, -top)
        p:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        p:Hide()
        frame.Pages[key] = p
        return p
    end
    local listTop = TITLE_H + 6 + TOOLBAR_H
    BuildDungeonsPage(NewPage("dungeons", listTop))
    BuildGearPage(NewPage("gear", listTop))
    ns:BuildSettingsPage(NewPage("settings", TITLE_H + 6))

    -- tab row hanging under the frame, like the Group Finder's own tabs
    local tabs = CreateFrame("Frame", nil, frame)
    tabs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", PAD, 1)
    tabs:SetSize(3 * TAB_W + 2, TAB_H)
    frame.TabRow = tabs
    for i, def in ipairs({ { "dungeons", "Dungeons" }, { "gear", "Gear" }, { "settings", "Settings" } }) do
        local tab = CreateFrame("Button", nil, tabs)
        tab:SetSize(TAB_W, TAB_H)
        tab:SetPoint("LEFT", (i - 1) * (TAB_W + 1), 0)
        tab.Text = Style.Text(tab, 11)
        tab.Text:SetPoint("CENTER", 0, 0)
        tab.Text:SetText(def[2])
        tab.tabID = def[1]
        tab:SetScript("OnClick", function() ns:ShowPage(def[1]) end)
        Style.Tab(tab)
    end

    frame:SetScript("OnShow", function() ns:RefreshWindow() end)
    frame:SetScript("OnHide", function() ns:RestoreGroupFinderOffset() end)
    return frame
end

function ns:ShowPage(key)
    BuildFrame()
    if not frame.Pages[key] then key = "dungeons" end
    for k, p in pairs(frame.Pages) do
        if k == key then p:Show() else p:Hide() end
    end
    if key == "settings" then frame.Toolbar:Hide() else frame.Toolbar:Show() end
    frame.page = key
    Style.SelectTab(frame.TabRow, key)
    self:RefreshWindow()
end

function ns:CurrentPage()
    return frame and frame.page or "dungeons"
end

-- kept for the Settings > AddOns button and the slash command
function ns:ToggleOptionsPanel()
    self:ShowPage(self:CurrentPage() == "settings" and "dungeons" or "settings")
end

function ns:OpenOptions()
    self:ShowWindow(true)
    self:ShowPage("settings")
end

-------------------------------------------------------------------------------
-- Row pools
-------------------------------------------------------------------------------
-- Top-level row (a dungeon or a slot): icon, chevron, name, Drops and Wanted
-- columns. onClick toggles expansion; onRightClick is optional.
local function NewTopRow(content, onClick, onRightClick, onEnter)
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
    row.Arrow = row:CreateTexture(nil, "ARTWORK")
    row.Arrow:SetAtlas(ARROW_ATLAS)
    row.Arrow:SetSize(10, 7)
    row.Arrow:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
    row.Arrow:SetVertexColor(1, 1, 1, 0.6)
    row.Wanted = Style.Text(row, 12)
    row.Wanted:SetPoint("RIGHT", -14, 0)
    row.Wanted:SetWidth(22)
    row.Wanted:SetJustifyH("LEFT")
    row.WantIcon = StarTexture(row, 12)
    row.WantIcon:SetPoint("RIGHT", row.Wanted, "LEFT", -3, 0)
    row.Count = Style.Text(row, 12)
    row.Count:SetPoint("RIGHT", -COL_WANTED - 1, 0)
    row.Count:SetWidth(COL_DROPS)
    row.Count:SetJustifyH("CENTER")
    row.Name = Style.Text(row, 12)
    row.Name:SetPoint("LEFT", row.Arrow, "RIGHT", 6, 0)
    row.Name:SetPoint("RIGHT", row.Count, "LEFT", -4, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if onRightClick then onRightClick(self) end
        else
            onClick(self)
        end
    end)
    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function SetRowCounts(row, count, wanted, scanned, accent)
    if not scanned then
        row.Count:SetText("|cff888888...|r")
        row.Wanted:SetText("")
        row.WantIcon:Hide()
        return
    end
    row.Count:SetText(count)
    if wanted > 0 then
        row.Wanted:SetText(accent .. wanted .. "|r")
        SetStar(row.WantIcon, true)
        row.WantIcon:Show()
    else
        row.Wanted:SetText("|cff444444-|r")
        row.WantIcon:Hide()
    end
end

local function RowBackground(row, index, expanded, highlighted)
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

-- Drop row under an expanded dungeon or slot. `where` = true shows the
-- dungeon the item drops from instead of its slot.
local function NewItemRow(content, where)
    local it = CreateFrame("Button", nil, content)
    it:SetHeight(ITEM_H)
    it.Hover = it:CreateTexture(nil, "HIGHLIGHT")
    it.Hover:SetAllPoints()
    it.Hover:SetColorTexture(1, 1, 1, 0.06)
    it.Icon = it:CreateTexture(nil, "ARTWORK")
    it.Icon:SetSize(ITEM_H - 4, ITEM_H - 4)
    it.Icon:SetPoint("LEFT", ROW_H + 6, 0)
    Style.SquareIcon(it.Icon, it)
    it.Star = CreateFrame("Button", nil, it)
    it.Star:SetSize(18, 18)
    it.Star:SetPoint("RIGHT", -4, 0)
    it.Star.Icon = StarTexture(it.Star, 14)
    it.Star.Icon:SetPoint("CENTER", 0, 0)
    it.Star:SetScript("OnClick", function(self)
        local parent = self:GetParent()
        local id = parent.eval and parent.eval.item.itemID
        if not id then return end
        ns:SetItemState(id, ns:GetItemState(id) == "want" and nil or "want")
    end)
    it.Star:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local wanted = parent.eval and ns:GetItemState(parent.eval.item.itemID) == "want"
        GameTooltip:AddLine(wanted and "On your wanted list" or "Add to wanted list")
        GameTooltip:AddLine(wanted and "Click to remove it." or "Wanted items count for their dungeon and drive the Voidcore advice. They leave the list by themselves once you have the item.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    it.Star:SetScript("OnLeave", function() GameTooltip:Hide() end)
    it.Gain = Style.Text(it, 10)
    it.Gain:SetPoint("RIGHT", it.Star, "LEFT", -4, 0)
    it.Gain:SetWidth(56)
    it.Gain:SetJustifyH("RIGHT")
    it.Stats = Style.Text(it, 10)
    it.Stats:SetPoint("RIGHT", it.Gain, "LEFT", -4, 0)
    it.Stats:SetWidth(46)
    it.Stats:SetJustifyH("RIGHT")
    it.Where = Style.Text(it, 10, 1, 1, 1, 0.55)
    it.Where:SetPoint("RIGHT", it.Stats, "LEFT", -4, 0)
    it.Where:SetWidth(where and 92 or 36)
    it.Where:SetJustifyH("RIGHT")
    it.Where:SetWordWrap(false)
    it.Name = Style.Text(it, 11)
    it.Name:SetPoint("LEFT", it.Icon, "RIGHT", 6, 0)
    it.Name:SetPoint("RIGHT", it.Where, "LEFT", -4, 0)
    it.Name:SetJustifyH("LEFT")
    it.Name:SetWordWrap(false)
    it:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    it:SetScript("OnClick", function(self, button)
        if not self.eval then return end
        if button == "RightButton" then
            ns:CycleItemState(self.eval.item.itemID)
        elseif IsModifiedClick("CHATLINK") and self.eval.item.link then
            ChatEdit_InsertLink(self.eval.item.link)
        elseif IsModifiedClick("DRESSUP") and self.eval.item.link then
            DressUpItemLink(self.eval.item.link)
        end
    end)
    it:SetScript("OnEnter", function(self) if self.eval then ns:ShowItemTooltip(self) end end)
    it:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return it
end

local function Acquire(pool, index, factory)
    local w = pool[index]
    if w then w:Show(); return w end
    w = factory()
    pool[index] = w
    return w
end

-- Fill a drop row. `whereText` replaces the slot text when given.
local function FillItemRow(it, eval, whereText)
    local self = ns
    local db = self.db
    local counts = self:CountsAsUpgrade(eval)
    local vcCounts = self:CountsAsUpgrade(eval, "voidcore")
    local state = self:GetItemState(eval.item.itemID)
    it.eval = eval
    it.Icon:SetTexture(eval.item.icon or 134400)
    if whereText then
        it.Where:SetText(whereText)
    else
        local slot = eval.slotID and self.SLOT_BY_ID[eval.slotID]
        it.Where:SetText(slot and (self.SLOT_SHORT[slot.id] or slot.key) or (eval.item.slotText or ""))
    end
    local name = ItemName(eval.item)
    if counts or vcCounts or state == "want" then
        it.Name:SetText(QualityHex(eval.item) .. name .. "|r")
        it.Name:SetAlpha(1)
    else
        it.Name:SetText(name)
        it.Name:SetAlpha(0.45)
    end
    local vcTag = (vcCounts and not counts) and (ns.VC_HEX .. "VC|r ") or ""
    if state == "exclude" then
        it.Gain:SetText("|cffff5555excluded|r")
    elseif eval.class == TRACK and eval.gain then
        it.Gain:SetText(string.format("%s%s%+d|r|cff888888/%+d|r", vcTag, Hex(TRACK), eval.gain, eval.potentialGain or 0))
    elseif eval.class == ILVL and eval.gain then
        it.Gain:SetText(string.format("%s%s%+d|r", vcTag, Hex(ILVL), eval.gain))
    elseif eval.class == WANT and eval.gain then
        it.Gain:SetText(string.format("%s%+d|r", eval.gain > 0 and Hex(ILVL) or "|cff777777", eval.gain))
    elseif vcCounts and eval.voidcore then
        it.Gain:SetText(string.format("%s%+d|r %s", ns.VC_HEX, eval.voidcore.potentialGain or eval.voidcore.gain or 0, vcTag))
    elseif eval.gain then
        it.Gain:SetText(string.format("|cff777777%+d|r", eval.gain))
    else
        it.Gain:SetText("")
    end
    it.Icon:SetDesaturated(not (counts or vcCounts or state == "want"))
    it.Stats:SetText(self:StatText(eval.stats, eval.fit))
    SetStar(it.Star.Icon, state == "want")
    it.Star:Show()
end

local function FillNoteRow(it, text)
    it.eval = nil
    it.Icon:SetTexture(nil)
    it.Where:SetText("")
    it.Name:SetText("|cff888888" .. text .. "|r")
    it.Name:SetAlpha(1)
    it.Gain:SetText("")
    it.Stats:SetText("")
    it.Star:Hide()
end

-------------------------------------------------------------------------------
-- Tooltips
-------------------------------------------------------------------------------
function ns:ShowSlotTooltip(btn)
    local slot = self.SLOT_BY_ID[btn.slotID]
    local g = self.gear[btn.slotID]
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:AddLine(slot.name or slot.key)
    if g and not g.empty and g.link then
        GameTooltip:AddLine(g.link)
        GameTooltip:AddLine(EquippedDesc(g), 0.9, 0.9, 0.9)
    else
        GameTooltip:AddLine("Nothing equipped", 0.7, 0.7, 0.7)
    end
    local summary = self.slotSummary and self.slotSummary[btn.slotID]
    if summary then
        if #summary.wanted > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(Style.AccentHex() .. "Wanted|r")
            for _, w in ipairs(summary.wanted) do
                GameTooltip:AddLine(string.format("  %s  |cff888888%s|r", w.eval.item.link or ItemName(w.eval.item), w.dungeon.name), 1, 1, 1)
            end
        end
        GameTooltip:AddLine(" ")
        if summary.count > 0 then
            GameTooltip:AddLine(string.format("%s%d upgrade drop(s) at the selected key|r", Hex(summary.best), summary.count))
            for mapID, n in pairs(summary.dungeons) do
                local d = self.dungeonByMapID[mapID]
                if d then GameTooltip:AddLine(string.format("  %s: %d", d.name, n), 0.8, 0.8, 0.8) end
            end
        else
            GameTooltip:AddLine("No upgrade drops at the selected key", 0.6, 0.6, 0.6)
        end
    end
    local state = self:GetSlotState(btn.slotID)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Slot: " .. (state == "want" and "|cff66bbffWant|r (every drop counts)"
        or state == "skip" and "|cffff5555Skip|r (never counts)" or "Auto"), 1, 1, 1)
    GameTooltip:AddLine("Click: compare its drops.  Right-click: cycle Auto / Want / Skip.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function ns:ShowDungeonTooltip(row)
    local r = row.result
    if not r then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(r.dungeon.name)
    if not r.scanned then
        GameTooltip:AddLine("Loot table not scanned yet.", 0.7, 0.7, 0.7)
    else
        local ctx = self.dropCtx
        GameTooltip:AddDoubleLine("Usable items for your spec", tostring(r.total), 0.9, 0.9, 0.9, 1, 1, 1)
        if ctx and ctx.ilvl then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("End of dungeon (+%d): %d %s", ctx.key, ctx.ilvl, TrackText(ctx.track, ctx.step)), 1, 0.82, 0)
            GameTooltip:AddDoubleLine("  Upgrade drops", string.format("%s%d|r", Hex(r.upgrades > 0 and TRACK or NONE), r.upgrades), 0.9, 0.9, 0.9)
            GameTooltip:AddDoubleLine("  Slots covered", tostring(r.slotCount), 0.9, 0.9, 0.9, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        if r.wanted > 0 then
            GameTooltip:AddLine(Style.AccentHex() .. "Wanted items here|r")
            for _, eval in ipairs(r.wantedItems) do
                GameTooltip:AddLine("  " .. (eval.item.link or ItemName(eval.item)), 1, 1, 1)
            end
            local vc = ctx and ctx.voidcore
            GameTooltip:AddLine(string.format("A Nebulous Voidcore here is one extra roll on these%s.",
                vc and vc.ilvl and string.format(" at %d %s", vc.ilvl, TrackText(vc.track, vc.step)) or ""), 0.6, 0.6, 0.6, true)
        else
            GameTooltip:AddLine("Nothing from your wanted list drops here.", 0.6, 0.6, 0.6)
            GameTooltip:AddLine("Click the dungeon and star the drops you are after.", 0.6, 0.6, 0.6, true)
        end
    end
    GameTooltip:Show()
end

function ns:ShowItemTooltip(btn)
    local eval = btn.eval
    if not eval then return end
    local item = eval.item
    local ctx = self.dropCtx
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    local link, kind = self:LinkForContext(item, ctx or {})
    if link then
        GameTooltip:SetHyperlink(link)
    else
        GameTooltip:SetItemByID(item.itemID)
    end
    GameTooltip:AddLine(" ")
    if btn.dungeonName then
        GameTooltip:AddLine("Drops in " .. btn.dungeonName, 0.9, 0.9, 0.9)
    end
    if ctx and ctx.ilvl then
        if kind == "exact" then
            GameTooltip:AddLine(ctx.isVoidcore and (ns.VC_HEX .. "Shown as a Voidcore roll from a +" .. ctx.key .. "|r")
                or string.format("|cff888888Shown as it drops from a +%d|r", ctx.key))
        else
            GameTooltip:AddLine("|cff888888Base item shown; the drop's own level is listed below|r")
        end
    end
    if eval.slotID then
        local slot = self.SLOT_BY_ID[eval.slotID]
        local g = eval.equipped
        GameTooltip:AddLine(string.format("Would replace (%s): %s", slot.name or slot.key, EquippedDesc(g)), 0.9, 0.9, 0.9, true)
    end
    if eval.stats then
        GameTooltip:AddLine(string.format("Stats: %s%s", self:StatText(eval.stats, eval.fit, true),
            eval.fit and string.format("  |cff888888%d%% match|r", eval.fit * 100 + 0.5) or ""), 1, 1, 1, true)
        if eval.equippedStats then
            GameTooltip:AddLine(string.format("Equipped: %s%s", self:StatText(eval.equippedStats, eval.equippedFit, true),
                eval.equippedFit and string.format("  |cff888888%d%% match|r", eval.equippedFit * 100 + 0.5) or ""), 0.9, 0.9, 0.9, true)
        end
    end
    local function ValueLine(label, r)
        if not r or not r.value then return end
        local s = string.format("%s: |cffffffff%d|r", label, r.value + 0.5)
        if r.valueGain then
            s = s .. string.format(" (%s%+d|r vs equipped)", r.valueGain >= 0 and "|cff33dd33" or "|cffff5555", r.valueGain + (r.valueGain >= 0 and 0.5 or -0.5))
        end
        GameTooltip:AddLine(s, 1, 1, 1, true)
    end
    if eval.value then
        local scale = ctx and ctx.statWeights
        ValueLine(string.format("Weighted value (%s)", scale and scale.name or "Pawn"), eval)
        if eval.voidcore and eval.voidcore.value and not (ctx and ctx.isVoidcore) then
            ValueLine(ns.VC_HEX .. "Voidcore roll value|r", eval.voidcore)
        end
    end
    local function Verdict(r)
        local label = ns.UPGRADE_LABEL[r.class]
        local extra = r.reason and (" - " .. r.reason) or ""
        local s = Hex(r.class) .. label .. "|r" .. extra
        if r.gain and r.class ~= NONE then
            s = s .. string.format("  (%+d now, %+d fully upgraded)", r.gain, r.potentialGain or 0)
        end
        return s
    end
    if ctx and ctx.ilvl then
        if ctx.isVoidcore then
            GameTooltip:AddLine(string.format("%sVoidcore roll|r (+%d): |cffffffff%d|r %s%s", ns.VC_HEX, ctx.key, ctx.ilvl,
                TrackText(ctx.track, ctx.step),
                (ctx.potential and ctx.potential > ctx.ilvl) and string.format(" (up to %d)", ctx.potential) or ""), 1, 1, 1, true)
        else
            GameTooltip:AddLine(string.format("End of dungeon +%d: |cffffffff%d|r %s%s", ctx.key, ctx.ilvl,
                TrackText(ctx.track, ctx.step),
                (ctx.potential and ctx.potential > ctx.ilvl) and string.format(" (up to %d)", ctx.potential) or ""), 1, 0.82, 0, true)
        end
        GameTooltip:AddLine("  " .. Verdict(eval), 1, 1, 1, true)
    else
        GameTooltip:AddLine("  " .. Verdict(eval), 1, 1, 1, true)
    end
    local vc = ctx and ctx.voidcore
    if vc and vc.ilvl and eval.voidcore and not ctx.isVoidcore then
        GameTooltip:AddLine(string.format("%sVoidcore roll|r: |cffffffff%d|r %s%s", ns.VC_HEX, vc.ilvl,
            TrackText(vc.track, vc.step),
            (vc.potential and vc.potential > vc.ilvl) and string.format(" (up to %d)", vc.potential) or ""), 1, 1, 1, true)
        GameTooltip:AddLine("  " .. Verdict(eval.voidcore), 1, 1, 1, true)
    end
    local state = self:GetItemState(item.itemID)
    GameTooltip:AddLine(" ")
    if state == "want" then
        GameTooltip:AddLine(Style.AccentHex() .. "On your wanted list|r  |cff888888(click the star to remove)|r")
    elseif state == "exclude" then
        GameTooltip:AddLine("|cffff5555Excluded|r  |cff888888(right-click to include again)|r")
    else
        GameTooltip:AddLine("|cff888888Star: add to wanted list.  Right-click: exclude (e.g. already rolled it with a Voidcore).|r", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

function ns:CycleItemState(itemID)
    local cur = self:GetItemState(itemID)
    self:SetItemState(itemID, cur == "exclude" and nil or "exclude")
end

-------------------------------------------------------------------------------
-- Spec cycling
-------------------------------------------------------------------------------
function ns:CycleEvalSpec()
    local specs = self:GetPlayerSpecs()
    local cur = self.cdb.evalSpecID
    local nextID
    if cur == nil then
        nextID = specs[1] and specs[1].id
    else
        for i, s in ipairs(specs) do
            if s.id == cur then
                nextID = specs[i + 1] and specs[i + 1].id or nil
                break
            end
        end
    end
    self.cdb.evalSpecID = nextID
    self.loot = nil
    self:EnsureLoot(false)
    self:Fire("SETTINGS_CHANGED")
    self:RefreshWindow()
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------
local function DungeonIcon(d)
    if d.texture then return d.texture end
    return 134400
end

local function StatusText()
    local self = ns
    local status
    if self.scanProgress then
        status = string.format("Scanning %d/%d: %s", self.scanProgress.index, self.scanProgress.total, self.scanProgress.name or "")
    elseif not self.dungeonsBuilt then
        status = "Waiting for season data..."
    elseif self.loot and self.loot.time then
        local age = time() - self.loot.time
        local ageText = age < 3600 and string.format("%dm", age / 60) or age < 86400 and string.format("%dh", age / 3600) or string.format("%dd", age / 86400)
        status = string.format("Loot tables scanned %s ago", ageText)
    else
        status = "Loot tables not scanned yet"
    end
    if self.trackOffsetApplied and self.trackOffsetApplied ~= 0 then
        status = status .. string.format("  |cffaaaaaa(tracks %+d)|r", self.trackOffsetApplied)
    end
    return status
end

local function InfoText(ctx)
    local parts = {}
    if ctx.isVoidcore then
        if ctx.ilvl then
            parts[#parts + 1] = string.format("%sVoidcore roll (+%d):|r %d %s", ns.VC_HEX, ctx.key, ctx.ilvl, TrackText(ctx.track, ctx.step))
        else
            parts[#parts + 1] = "|cffff5555Voidcore item level unknown|r"
        end
    else
        if ctx.ilvl then
            parts[#parts + 1] = string.format("Drops at +%d: |cffffffff%d|r %s", ctx.key, ctx.ilvl, TrackText(ctx.track, ctx.step))
        else
            parts[#parts + 1] = "|cffff5555Drop item level unknown|r"
        end
        local vc = ctx.voidcore
        if vc and vc.ilvl then
            parts[#parts + 1] = string.format("%sVoidcore:|r |cffffffff%d|r %s", ns.VC_HEX, vc.ilvl, TrackText(vc.track, vc.step))
        end
    end
    if ctx.source == "fallback" then parts[#parts + 1] = "|cffff9900season table|r" end
    return table.concat(parts, "  |cff555555·|r  ")
end

local function RefreshToolbar()
    local self = ns
    local bar = frame.Toolbar
    local specID = self:GetEvalSpecID()
    local specName, specIcon = self:SpecName(specID)
    bar.SpecButton.Icon:SetTexture(specIcon or 134400)
    bar.SpecButton.Text:SetText(self.cdb.evalSpecID and specName or (specName .. " |cff888888(loot spec)|r"))
    bar.KeyText:SetText(self:TargetLabel())
    bar.KeyPlus:SetEnabled(not self.db.voidcoreMode)
    local ctx = self.dropCtx or self:GetDropContext()
    bar.Info:SetText(InfoText(ctx))
end

local function RefreshDungeons(page)
    local self = ns
    local db = self.db
    local sortMode = db.sortMode or "upgrades"
    if sortMode ~= "wanted" and sortMode ~= "name" then sortMode = "upgrades" end
    if page.ColHead.selectedTabID ~= sortMode then Style.SelectTab(page.ColHead, sortMode) end

    local y = 0
    local rowIndex, itemIndex = 0, 0
    local content = page.Content
    local width = content:GetWidth()
    local accent = Style.AccentHex()
    for _, r in ipairs(self.results or {}) do
        local show = not (db.hideEmptyDungeons and r.scanned and r.upgrades == 0 and r.wanted == 0)
        if show then
            rowIndex = rowIndex + 1
            local row = Acquire(dungeonRows, rowIndex, function()
                return NewTopRow(content, function(self2)
                    ns.uiExpandedMapID = (ns.uiExpandedMapID ~= self2.mapID) and self2.mapID or nil
                    ns:RefreshWindow()
                end, nil, function(self2) ns:ShowDungeonTooltip(self2) end)
            end)
            row.result = r
            row.mapID = r.dungeon.challengeMapID
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:SetWidth(width)
            row.Icon:SetTexture(DungeonIcon(r.dungeon))
            row.Icon:SetDesaturated(false)
            row.Border:SetColorTexture(0, 0, 0, 1)
            row.Name:SetText(r.dungeon.name)
            local expanded = self.uiExpandedMapID == row.mapID
            row.Arrow:SetRotation(expanded and 0 or math.rad(90))
            SetRowCounts(row, string.format("%s%d|r", Hex(r.upgrades > 0 and (r.trackUpgrades > 0 and TRACK or ILVL) or NONE), r.upgrades),
                r.wanted, r.scanned, accent)
            RowBackground(row, rowIndex, expanded, self.highlightMapID == row.mapID)
            y = y + ROW_H + 1
            if expanded and r.scanned then
                local shown = 0
                for _, eval in ipairs(r.items) do
                    local state = self:GetItemState(eval.item.itemID)
                    if self:CountsAsUpgrade(eval) or self:CountsAsUpgrade(eval, "voidcore") or state == "want" or not db.hideNonUpgrades then
                        shown = shown + 1
                        itemIndex = itemIndex + 1
                        local it = Acquire(dungeonItems, itemIndex, function() return NewItemRow(content, false) end)
                        it:ClearAllPoints()
                        it:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                        it:SetWidth(width)
                        it.dungeonName = nil
                        FillItemRow(it, eval)
                        y = y + ITEM_H
                    end
                end
                if shown == 0 then
                    itemIndex = itemIndex + 1
                    local it = Acquire(dungeonItems, itemIndex, function() return NewItemRow(content, false) end)
                    it:ClearAllPoints()
                    it:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                    it:SetWidth(width)
                    FillNoteRow(it, "No upgrades here at this key.")
                    y = y + ITEM_H
                end
                y = y + 4
            end
        end
    end
    for i = rowIndex + 1, #dungeonRows do dungeonRows[i]:Hide() end
    for i = itemIndex + 1, #dungeonItems do dungeonItems[i]:Hide() end
    content:SetHeight(math.max(y, 1))

    page.Status:SetText(StatusText())
    if self.scanProgress and self.scanProgress.total and self.scanProgress.total > 0 then
        page.Progress:SetValue(self.scanProgress.index / self.scanProgress.total)
        page.Progress:Show()
    else
        page.Progress:Hide()
    end
end

-- Drops for one slot from every dungeon, best stat fit first. Excluded items
-- go last; ties fall back to gain, then name.
local function CompareDrops(a, b)
    local ea, eb = a.eval, b.eval
    local xa, xb = ns:GetItemState(ea.item.itemID) == "exclude", ns:GetItemState(eb.item.itemID) == "exclude"
    if xa ~= xb then return not xa end
    if ea.value and eb.value and ea.value ~= eb.value then return ea.value > eb.value end
    local fa, fb = ea.fit or 0.5, eb.fit or 0.5
    if fa ~= fb then return fa > fb end
    local ga, gb = ea.potentialGain or 0, eb.potentialGain or 0
    if ga ~= gb then return ga > gb end
    return ItemName(ea.item) < ItemName(eb.item)
end

-- [slotID] = { { eval, dungeon }, ... } sorted
local function DropsBySlot()
    local buckets = {}
    for _, r in ipairs(ns.results or {}) do
        if r.scanned then
            for _, eval in ipairs(r.items) do
                if eval.slotID then
                    buckets[eval.slotID] = buckets[eval.slotID] or {}
                    table.insert(buckets[eval.slotID], { eval = eval, dungeon = r.dungeon })
                end
            end
        end
    end
    for _, list in pairs(buckets) do table.sort(list, CompareDrops) end
    return buckets
end

-- Twin slots (rings, trinkets, hands): a drop is compared against the weaker
-- one, so the other twin may list nothing.
local TWIN = { [11] = 12, [12] = 11, [13] = 14, [14] = 13, [16] = 17, [17] = 16 }

local function RefreshGear(page)
    local self = ns
    local db = self.db
    local sortMode = db.gearSort or "slot"
    if sortMode ~= "upgrades" and sortMode ~= "wanted" then sortMode = "slot" end
    if page.ColHead.selectedTabID ~= sortMode then Style.SelectTab(page.ColHead, sortMode) end

    local summary = self.slotSummary or {}
    local buckets = DropsBySlot()
    local order = {}
    for i, s in ipairs(self.SLOTS) do order[i] = s end
    if sortMode ~= "slot" then
        local index = {}
        for i, s in ipairs(self.SLOTS) do index[s.id] = i end
        table.sort(order, function(a, b)
            local ea, eb = summary[a.id] or {}, summary[b.id] or {}
            local va = sortMode == "wanted" and #(ea.wanted or {}) or (ea.count or 0)
            local vb = sortMode == "wanted" and #(eb.wanted or {}) or (eb.count or 0)
            if va ~= vb then return va > vb end
            return index[a.id] < index[b.id]
        end)
    end

    local y = 0
    local rowIndex, itemIndex = 0, 0
    local content = page.Content
    local width = content:GetWidth()
    local accent = Style.AccentHex()
    local scanned = self.loot ~= nil
    for _, s in ipairs(order) do
        rowIndex = rowIndex + 1
        local row = Acquire(gearRows, rowIndex, function()
            return NewTopRow(content, function(self2)
                ns.uiExpandedSlotID = (ns.uiExpandedSlotID ~= self2.slotID) and self2.slotID or nil
                ns:RefreshWindow()
            end, function(self2)
                ns:CycleSlotState(self2.slotID)
            end, function(self2) ns:ShowSlotTooltip(self2) end)
        end)
        row.slotID = s.id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetWidth(width)
        local g = self.gear[s.id]
        local icon = GetInventoryItemTexture("player", s.id)
        if icon then
            row.Icon:SetTexture(icon)
            row.Icon:SetDesaturated(false)
        else
            row.Icon:SetTexture(self.SLOT_EMPTY_TEXTURE[s.id] or 134400)
            row.Icon:SetDesaturated(true)
        end
        local state = self:GetSlotState(s.id)
        local e = summary[s.id] or { count = 0, wanted = {}, best = NONE }
        if state == "skip" then
            row.Border:SetColorTexture(0.8, 0.2, 0.2, 1)
        elseif state == "want" then
            row.Border:SetColorTexture(0.35, 0.7, 1, 1)
        elseif e.count > 0 then
            local r, gg, bb = Color(e.best)
            row.Border:SetColorTexture(r, gg, bb, 1)
        else
            row.Border:SetColorTexture(0, 0, 0, 1)
        end
        local label = s.name or s.key
        if state == "skip" then label = "|cffff5555" .. label .. "|r  |cff888888skip|r"
        elseif state == "want" then label = "|cff66bbff" .. label .. "|r  |cff888888want all|r" end
        row.Name:SetText(label .. "  " .. EquippedShort(g))
        local expanded = self.uiExpandedSlotID == s.id
        row.Arrow:SetRotation(expanded and 0 or math.rad(90))
        SetRowCounts(row, string.format("%s%d|r", Hex(e.count > 0 and e.best or NONE), e.count), #e.wanted, scanned, accent)
        RowBackground(row, rowIndex, expanded, false)
        y = y + ROW_H + 1
        if expanded then
            local list = buckets[s.id] or {}
            local shown = 0
            for _, entry in ipairs(list) do
                local eval = entry.eval
                local st = self:GetItemState(eval.item.itemID)
                if self:CountsAsUpgrade(eval) or self:CountsAsUpgrade(eval, "voidcore") or st == "want" or not db.hideNonUpgrades then
                    shown = shown + 1
                    itemIndex = itemIndex + 1
                    local it = Acquire(gearItems, itemIndex, function() return NewItemRow(content, true) end)
                    it:ClearAllPoints()
                    it:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                    it:SetWidth(width)
                    it.dungeonName = entry.dungeon.name
                    FillItemRow(it, eval, entry.dungeon.name)
                    y = y + ITEM_H
                end
            end
            if shown == 0 then
                itemIndex = itemIndex + 1
                local it = Acquire(gearItems, itemIndex, function() return NewItemRow(content, true) end)
                it:ClearAllPoints()
                it:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                it:SetWidth(width)
                local twin = TWIN[s.id]
                local twinHas = twin and buckets[twin] and #buckets[twin] > 0
                if not scanned then
                    FillNoteRow(it, "Loot tables not scanned yet.")
                elseif twinHas then
                    local ts = self.SLOT_BY_ID[twin]
                    FillNoteRow(it, string.format("Drops for this slot are compared against your weaker %s; see that row.", ts and (ts.name or ts.key) or "slot"))
                elseif state == "skip" then
                    FillNoteRow(it, "Slot skipped.")
                else
                    FillNoteRow(it, "No drops for this slot in this season's dungeons.")
                end
                y = y + ITEM_H
            end
            y = y + 4
        end
    end
    for i = rowIndex + 1, #gearRows do gearRows[i]:Hide() end
    for i = itemIndex + 1, #gearItems do gearItems[i]:Hide() end
    content:SetHeight(math.max(y, 1))
end

function ns:RefreshWindow()
    if not frame or not frame:IsShown() then return end
    self.slotSummary = self:SlotSummary()
    local page = frame.page or "dungeons"
    if page == "settings" then
        self:RefreshOptionsPanel()
        return
    end
    RefreshToolbar()
    if page == "dungeons" then
        RefreshDungeons(frame.Pages.dungeons)
    else
        RefreshGear(frame.Pages.gear)
    end
end

-------------------------------------------------------------------------------
-- Show / hide / anchoring
-------------------------------------------------------------------------------
-- When docked on the left there is usually no room: the Group Finder opens at
-- the left edge of the screen. We push it right (UIPanel "xoffset" first, a
-- direct move as fallback) and restore it when our window closes.
local push = { offset = nil, moved = nil }

local function PVEToUIParent(v)
    return v * PVEFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

function ns:RestoreGroupFinderOffset()
    if not PVEFrame or InCombatLockdown() then return end
    if push.offset ~= nil and SetUIPanelAttribute then
        pcall(SetUIPanelAttribute, PVEFrame, "xoffset", push.offset)
    end
    if push.moved and PVEFrame:IsShown() then
        PVEFrame:ClearAllPoints()
        PVEFrame:SetPoint(push.moved.point, UIParent, push.moved.relPoint, push.moved.x, push.moved.y)
    end
    push.offset, push.moved = nil, nil
end

-- How far (in UIParent units) our window sticks out past the left screen edge.
local function Overhang()
    local left = frame:GetLeft()
    if not left then return 0 end
    local px = left * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if px >= 0 then return 0 end
    return math.ceil(-px) + 4
end

-- Other windows parked on the Group Finder's left edge. EllesmereUI docks the
-- character sheet there whenever both are open; we dock outside whichever
-- visible neighbour reaches furthest left, so nothing lands on top of us.
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
            if l and t and b then
                local s = f:GetEffectiveScale() or 1
                if t * s > bottom and b * s < top and l * s < bestLeft then
                    best, bestLeft = f, l * s
                end
            end
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
    frame.leftNeighbour = neighbour
    frame.dockedTo = neighbour
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", neighbour, "TOPLEFT", -2, 0)
    -- A neighbour parked at the screen edge leaves us no room: dock on the
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
    if InCombatLockdown() or ns.db.pushGroupFinder == false then return end
    local needed = Overhang()
    if needed <= 0 then return end
    -- 1) UIPanel layout offset: survives the panel manager re-laying out the frame
    if SetUIPanelAttribute and GetUIPanelAttribute then
        local ok, current = pcall(GetUIPanelAttribute, PVEFrame, "xoffset")
        current = (ok and tonumber(current)) or 0
        if push.offset == nil then push.offset = current end
        pcall(SetUIPanelAttribute, PVEFrame, "xoffset", current + needed)
        if UIParent_ManageFramePositions then pcall(UIParent_ManageFramePositions) end
    end
    -- 2) verify once the layout has settled; move the frame directly if needed
    C_Timer.After(0.05, function()
        if not frame:IsShown() or not PVEFrame:IsShown() or InCombatLockdown() then return end
        if (ns.db.anchorSide or "left") ~= "left" then return end
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

function ns:AnchorWindow()
    if not frame then return end
    local side = self.db.anchorSide or "left"
    local docked = PVEFrame and PVEFrame:IsShown() and side ~= "free"
    frame:SetScale(self.db.scale or 1)
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
    else
        self:RestoreGroupFinderOffset()
        frame:SetHeight(FREE_HEIGHT)
        local pos = self.db.freePos
        if pos and pos.point then
            frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
        end
    end
end

-- While docked on the left, keep checking that nothing has moved onto us: the
-- UI panel manager re-lays the Group Finder out when another panel opens, and
-- the character sheet may arrive at its left edge.
local function OnUpdateWatch(self, elapsed)
    self.watchElapsed = (self.watchElapsed or 0) + elapsed
    if self.watchElapsed < 0.5 then return end
    self.watchElapsed = 0
    if PVEFrame and PVEFrame:IsShown() and (ns.db.anchorSide or "left") == "left" and not InCombatLockdown() then
        if LeftNeighbour() ~= frame.leftNeighbour then
            ns:AnchorWindow()
        elseif Overhang() > 0 then
            PushGroupFinder()
        end
    end
end

function ns:ShowWindow(manual)
    BuildFrame()
    if manual then self.standalone = not (PVEFrame and PVEFrame:IsShown()) end
    self:RequestSeasonData()
    self:AnchorWindow()
    frame:SetScript("OnUpdate", OnUpdateWatch)
    if not frame.page then self:ShowPage("dungeons") end
    frame:Show()
    if not self.gearScanned then self:ScanGear() end
    self:EnsureLoot(false)
    if not self.results then self:Evaluate() end
    self:RefreshWindow()
end

function ns:HideWindow(manual)
    if manual then self.standalone = false end
    if frame then frame:Hide() end
end

function ns:ToggleWindow()
    if frame and frame:IsShown() then
        self:HideWindow(true)
    else
        self:ShowWindow(true)
    end
end

function ns:IsWindowShown()
    return frame and frame:IsShown()
end

function ns:ShouldAutoShow()
    if not self.db.autoShow then return false end
    if not (PVEFrame and PVEFrame:IsShown()) then return false end
    if self.db.onlyPremadeTab then
        return LFGListFrame and LFGListFrame:IsShown()
    end
    return true
end

local function UpdateAutoVisibility()
    if not ns.db then return end
    if ns.userClosedThisSession then return end
    if ns:ShouldAutoShow() then
        if not ns:IsWindowShown() then ns:ShowWindow(false) else ns:AnchorWindow() end
    elseif ns:IsWindowShown() and not ns.standalone then
        ns:HideWindow(false)
    end
end
ns.UpdateAutoVisibility = UpdateAutoVisibility

local function ReanchorSoon()
    C_Timer.After(0, function()
        if ns:IsWindowShown() and PVEFrame and PVEFrame:IsShown() and (ns.db.anchorSide or "left") == "left" then
            ns:AnchorWindow()
        end
    end)
end

-- hooks into the Group Finder
ns:On("LOGIN", function()
    if PVEFrame then
        PVEFrame:HookScript("OnShow", function()
            ns.userClosedThisSession = nil
            C_Timer.After(0, UpdateAutoVisibility)
        end)
        PVEFrame:HookScript("OnHide", function()
            if ns:IsWindowShown() and not ns.standalone then ns:HideWindow(false) end
            ns.userClosedThisSession = nil
        end)
    end
    if LFGListFrame then
        LFGListFrame:HookScript("OnShow", function() C_Timer.After(0, UpdateAutoVisibility) end)
        LFGListFrame:HookScript("OnHide", function() C_Timer.After(0, UpdateAutoVisibility) end)
    end
    if PVEFrame_ShowFrame then
        hooksecurefunc("PVEFrame_ShowFrame", function() C_Timer.After(0, UpdateAutoVisibility) end)
    end
    if CharacterFrame then
        CharacterFrame:HookScript("OnShow", ReanchorSoon)
        CharacterFrame:HookScript("OnHide", ReanchorSoon)
    end
end)

-- closing with the X while docked: stay closed until the Group Finder is reopened
ns:On("DB_READY", function()
    BuildFrame()
    frame:HookScript("OnHide", function()
        if PVEFrame and PVEFrame:IsShown() and not ns.standalone then
            ns.userClosedThisSession = true
        end
    end)
end)

ns:On("RESULTS_UPDATED", function() ns:RefreshWindow() end)
ns:On("SCAN_PROGRESS", function(index, total, name)
    if index then
        ns.scanProgress = { index = index, total = total, name = name }
    else
        ns.scanProgress = nil
    end
    ns:RefreshWindow()
end)
ns:On("SETTINGS_CHANGED", function() ns:RefreshWindow() end)
ns:On("SPEC_CHANGED", function() ns:RefreshWindow() end)
ns:On("GEAR_UPDATED", function() ns:RefreshWindow() end)
Style.OnLooksChanged(function() ns:RefreshWindow() end)

function ns:SetHighlightDungeon(mapID)
    if self.highlightMapID == mapID then return end
    self.highlightMapID = mapID
    self:RefreshWindow()
end

-------------------------------------------------------------------------------
-- /sf status
-------------------------------------------------------------------------------
function ns:PrintStatus()
    self:Print("Status")
    print("  Season id:", tostring(self:GetSeasonID()), " dungeons:", #self.dungeons)
    local ctx = self:GetDropContext()
    print(string.format("  Target key +%d -> ilvl %s (%s) %s", ctx.key, tostring(ctx.ilvl), ctx.source, TrackText(ctx.track, ctx.step)))
    print("  Tracks:")
    for _, t in ipairs(self.tracks) do
        print(string.format("    %s (%s): %d-%d, %d steps", t.key, t.localizedName or "?", t.min, t.max, t.steps))
    end
    print("  Spec:", self:SpecName(self:GetEvalSpecID()), self.cdb.evalSpecID and "(manual)" or "(loot spec)")
    print("  Style:", Style.mode or "undecided", Style.IsSkinned() and "(EllesmereUI skin)" or "")
    print("  Wanted:", table.concat(self:WantedItemIDs(), ", "))
    if self.loot then
        local n = 0
        for _ in pairs(self.loot.dungeons or {}) do n = n + 1 end
        print("  Loot cache:", n, "dungeons, scanned", date("%Y-%m-%d %H:%M", self.loot.time or 0))
    else
        print("  Loot cache: none")
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
        if g and not g.empty then
            print(string.format("    %-9s %s", s.key, EquippedDesc(g)))
        end
    end
end
