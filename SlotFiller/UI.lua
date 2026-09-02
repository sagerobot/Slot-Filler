-- Slot Filler: main window. Four tabs (Dungeons, Raid, Gear, Settings) in a
-- shell that EllesmereUI paints when present (see Style.lua). Docks to the
-- left of the Dungeons & Raids window, tabs hanging under the frame like its
-- own.
--
-- Dungeons: dungeon rows that open into the drops they hold.
-- Raid:     boss rows, judged at the difficulty picked on the tab's strip.
-- Gear:     slot rows that open into every drop for that slot, from
--           dungeons, raids or both, ordered by stat compatibility, so
--           same-slot drops can be compared and starred.
local _, ns = ...
local Style = ns.Style

local WIDTH = 390
local FREE_HEIGHT = 520
local PAD = 8            -- content inset from the window edge
local TITLE_H = 25       -- EllesmereUI title band height
local TOOLBAR_H = 68     -- spec/key row, weights row and the info line, shared by the list tabs
local TAB_H, TAB_W = 22, 88
local STRIP_H = 24       -- filter strip above a list's column header
local SECTION_H = 22     -- raid name above its bosses
local ROW_H = 28         -- dungeon / slot row
local ITEM_H = 20        -- drop row under an expanded row
local GUTTER = 12        -- scrollbar gutter right of a list
local COL_DROPS, COL_WANTED = 56, 68

local frame
local dungeonRows, dungeonItems = {}, {}
local raidRows, raidItems, raidHeaders = {}, {}, {}
local gearRows, gearItems = {}, {}
ns.uiExpandedMapID = nil
ns.uiExpandedEncounterID = nil
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

-- Wanted star in the accent colour; the Voidcore star in purple.
local function SetStar(tex, on, voidcore)
    if on then
        local r, g, b = Style.Accent()
        if voidcore then r, g, b = 0.78, 0.55, 1 end
        tex:SetDesaturated(false)
        tex:SetVertexColor(r, g, b, 1)
    else
        tex:SetDesaturated(true)
        tex:SetVertexColor(1, 1, 1, 0.3)
    end
end

-------------------------------------------------------------------------------
-- Dropdown: a block button showing the current choice; clicking it opens a
-- flat menu underneath. entries() returns { { text, checked, onClick }, ... }.
-- One menu frame serves every dropdown; it closes on a click anywhere else.
-------------------------------------------------------------------------------
local menu
local MENU_ROW_H = 20

local function CloseMenu()
    if menu and menu:IsShown() then menu:Hide() end
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
    row.Text = Style.Text(row, 11)
    row.Text:SetPoint("LEFT", 20, 0)
    row.Text:SetPoint("RIGHT", -8, 0)
    row.Text:SetJustifyH("LEFT")
    row.Text:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        CloseMenu()
        if self.entry and self.entry.onClick then self.entry.onClick() end
    end)
    menu.rows[i] = row
    return row
end

local function OpenMenu(owner, entries)
    if not menu then
        menu = CreateFrame("Frame", nil, frame or UIParent)
        menu:SetFrameStrata("HIGH")
        menu:EnableMouse(true)
        menu:Hide()
        menu.rows = {}
        Style.Panel(menu)
        menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
        menu:SetScript("OnEvent", function(self)
            if self:IsShown() and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
                self:Hide()
            end
        end)
        menu:SetScript("OnHide", function(self) self.owner = nil end)
    end
    if menu:IsShown() and menu.owner == owner then CloseMenu(); return end
    menu.owner = owner
    local r, g, b = Style.Accent()
    local n = #entries
    for i, entry in ipairs(entries) do
        local row = MenuRow(i)
        row.entry = entry
        row.Text:SetText(entry.text or "")
        row.Text:SetAlpha(entry.checked and 1 or 0.8)
        row.Mark:SetColorTexture(r, g, b, 1)
        row.Mark:SetShown(entry.checked and true or false)
        row:Show()
    end
    for i = n + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -1)
    menu:SetSize(math.max(owner:GetWidth() or 0, 120), n * MENU_ROW_H + 2)
    menu:Show()
end

-- w = nil leaves the width to the caller's anchors.
local function Dropdown(parent, w, h, entries)
    local b = CreateFrame("Button", nil, parent)
    if w then b:SetWidth(w) end
    b:SetHeight(h or 22)
    b.Arrow = b:CreateTexture(nil, "OVERLAY")
    b.Arrow:SetAtlas(ARROW_ATLAS)
    b.Arrow:SetSize(12, 9)
    b.Arrow:SetPoint("RIGHT", -6, 0)
    b.Arrow:SetVertexColor(1, 1, 1, 0.7)
    b.Text = Style.Text(b, 11)
    b.Text:SetPoint("LEFT", 6, 0)
    b.Text:SetPoint("RIGHT", b.Arrow, "LEFT", -4, 0)
    b.Text:SetJustifyH("LEFT")
    b.Text:SetWordWrap(false)
    Style.Button(b, { "Arrow" })
    b.entries = entries
    b:SetScript("OnClick", function(self) OpenMenu(self, self.entries()) end)
    b:HookScript("OnHide", function(self) if menu and menu.owner == self then CloseMenu() end end)
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

local function RefreshStatProfileButton(b)
    local name = ns:StatProfileName()
    b.Text:SetText("|cffaaaaaaWeights:|r " .. (name or "|cff888888none|r"))
end

local function StatProfileDropdown(parent, w, h)
    local b = Dropdown(parent, w, h, StatProfileEntries)
    b:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Stat weights")
        local _, scale = ns:GetActiveStatProfile()
        if scale then
            GameTooltip:AddLine(tostring(scale.name), 1, 1, 1)
            GameTooltip:AddLine(ns:StatWeightsText(scale), 0.8, 0.8, 0.8, true)
            if scale.pawnName and scale.pawnName ~= scale.name then
                GameTooltip:AddLine("Pawn scale: " .. tostring(scale.pawnName), 0.6, 0.6, 0.6, true)
            end
        else
            GameTooltip:AddLine("No profile in use: stats are ranked by how much of each your equipped gear carries.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to switch between the weight profiles saved for this spec. Every Pawn string imported in Settings becomes one, so you can keep a Raid and a Mythic+ profile and swap here.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    RefreshStatProfileButton(b)
    return b
end

ns.UI = { TextButton = TextButton, Check = Check, Tip = Tip, Dropdown = Dropdown, CloseMenu = CloseMenu,
    StatProfileDropdown = StatProfileDropdown, RefreshStatProfileButton = RefreshStatProfileButton,
    IsMenuShown = function() return (menu and menu:IsShown()) and true or false end,
    -- row pools, for the test harness
    Pools = { dungeonItems = dungeonItems, raidItems = raidItems, gearItems = gearItems } }

-- Tooltips show the Voidcore roll while Shift is held: redraw the hovered
-- row's tooltip when Shift changes.
ns:RegisterEvent("MODIFIER_STATE_CHANGED", function(key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
    local row = ns.hoveredTip
    if row and row.tipFn and row:IsMouseOver() then row.tipFn(row) end
end)

-- Column header tabs shared by both list tabs: a full-width first tab plus
-- fixed Drops and Wanted columns. defs = { { id, text, width|nil }, ... }
local function ColumnHeader(page, defs, onSelect, top)
    local colHead = CreateFrame("Frame", nil, page)
    colHead:SetPoint("TOPLEFT", 0, -(top or 0))
    colHead:SetPoint("TOPRIGHT", -GUTTER, -(top or 0))
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
    bar.KeyText, bar.KeyPlus, bar.KeyMinus, bar.KeyBox, bar.KeyLabel = keyText, keyPlus, keyMinus, keyBox, keyLabel
    for _, b in ipairs({ keyPlus, keyMinus }) do
        Tip(b, "ANCHOR_BOTTOM", "Key level",
            "Drops are judged at the end-of-dungeon item level of this key.")
    end

    local weights = StatProfileDropdown(bar, 176, 22)
    weights:SetPoint("TOPLEFT", 0, -26)
    bar.WeightsButton = weights
    local prio = Style.Text(bar, 11, 1, 1, 1, 0.6)
    prio:SetPoint("LEFT", weights, "RIGHT", 8, 0)
    prio:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    prio:SetJustifyH("LEFT")
    prio:SetWordWrap(false)
    bar.Prio = prio

    local info = Style.Text(bar, 10, 1, 1, 1, 0.6)
    info:SetPoint("TOPLEFT", 2, -54)
    info:SetPoint("TOPRIGHT", -2, -54)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(false)
    bar.Info = info
end

-- A row of small tabs, like the switches in Settings. defs = { { id, text, tip }, ... }
local function TabStrip(parent, defs, w, onSelect)
    local tabs = CreateFrame("Frame", nil, parent)
    tabs:SetSize(#defs * w + (#defs - 1), 20)
    local prev
    for _, def in ipairs(defs) do
        local tab = CreateFrame("Button", nil, tabs)
        tab:SetSize(w, 20)
        if prev then tab:SetPoint("LEFT", prev, "RIGHT", 1, 0) else tab:SetPoint("LEFT", 0, 0) end
        tab.Text = Style.Text(tab, 11)
        tab.Text:SetPoint("CENTER", 0, 0)
        tab.Text:SetText(def[2])
        tab.tabID = def[1]
        tab:SetScript("OnClick", function()
            Style.SelectTab(tabs, def[1])
            onSelect(def[1])
        end)
        Style.Tab(tab)
        if def[3] then Tip(tab, "ANCHOR_TOP", def[2], def[3]) end
        prev = tab
    end
    return tabs
end

-- Status line and scan progress bar along the bottom of a list page.
local function StatusLine(page)
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
-- Dungeons page
-------------------------------------------------------------------------------
local function BuildDungeonsPage(page)
    local colHead = ColumnHeader(page, {
        { "name", "Dungeon", nil, "Click to sort by name. Click a dungeon to see its drops." },
        { "upgrades", "Drops", COL_DROPS, "Spec-usable items that would upgrade a slot as an end-of-dungeon drop at the selected key. Click to sort." },
        { "wanted", "Wanted", COL_WANTED, "Items from your wanted list that drop in this dungeon; a purple star means a Voidcore target drops here. Click to sort." },
    }, function(mode) ns.db.sortMode = mode end)
    page.ColHead = colHead
    page.List, page.Content = ListPanel(page, colHead, 18)
    StatusLine(page)
end

-------------------------------------------------------------------------------
-- Raid page: a difficulty strip, then boss rows
-------------------------------------------------------------------------------
local function BuildRaidPage(page)
    local strip = CreateFrame("Frame", nil, page)
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", -GUTTER, 0)
    strip:SetHeight(20)
    local label = Style.Text(strip, 11, 1, 1, 1, 0.53)
    label:SetPoint("LEFT", 4, 0)
    label:SetText("Difficulty")
    local defs = {}
    for _, d in ipairs(ns.RAID_DIFFS) do
        defs[#defs + 1] = { d.key, d.name, "Bosses are judged at this difficulty." }
    end
    strip.Tabs = TabStrip(strip, defs, 60, function(key) ns:SetRaidDifficulty(key) end)
    strip.Tabs:SetPoint("RIGHT", 0, 0)
    page.Strip = strip

    local colHead = ColumnHeader(page, {
        { "boss", "Boss", nil, "Click a boss to see its drops. Click here to sort by kill order." },
        { "upgrades", "Drops", COL_DROPS, "Spec-usable items that would upgrade a slot as a drop at the selected difficulty. Click to sort." },
        { "wanted", "Wanted", COL_WANTED, "Items from your wanted list this boss drops; a purple star means a Voidcore target. Click to sort." },
    }, function(mode) ns.db.raidSort = mode end, STRIP_H)
    page.ColHead = colHead
    page.List, page.Content = ListPanel(page, colHead, 18)
    StatusLine(page)
end

-------------------------------------------------------------------------------
-- Gear page: a source strip (M+ / both / raid), then slot rows
-------------------------------------------------------------------------------
local function BuildGearPage(page)
    local strip = CreateFrame("Frame", nil, page)
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", -GUTTER, 0)
    strip:SetHeight(20)
    local label = Style.Text(strip, 11, 1, 1, 1, 0.53)
    label:SetPoint("LEFT", 4, 0)
    label:SetText("Drops from")
    strip.Tabs = TabStrip(strip, {
        { "mplus", "M+", "Dungeon drops at the selected key." },
        { "both", "Both", "Dungeon drops at the selected key and raid drops at the Raid tab's difficulty." },
        { "raid", "Raid", "Raid drops at the Raid tab's difficulty." },
    }, 50, function(key) ns.db.gearSource = key; ns:RefreshWindow() end)
    strip.Tabs:SetPoint("LEFT", label, "RIGHT", 8, 0)
    strip.Diff = Style.Text(strip, 10, 1, 1, 1, 0.53)
    strip.Diff:SetPoint("LEFT", strip.Tabs, "RIGHT", 8, 0)
    page.Strip = strip

    local colHead = ColumnHeader(page, {
        { "slot", "Slot", nil, "Click a slot to compare every drop for it. Click here to sort by slot." },
        { "upgrades", "Drops", COL_DROPS, "Upgrade drops available for the slot. Click to sort." },
        { "wanted", "Wanted", COL_WANTED, "Wanted items for the slot. Click to sort." },
    }, function(mode) ns.db.gearSort = mode end, STRIP_H)
    page.ColHead = colHead
    page.List, page.Content = ListPanel(page, colHead, 18)

    local hint = Style.Text(page, 10, 1, 1, 1, 0.53)
    hint:SetPoint("BOTTOMLEFT", 2, 2)
    hint:SetPoint("BOTTOMRIGHT", -2, 2)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    hint:SetText("Star: want it.  Purple star: Voidcore it.  Right-click a slot: Auto / Want / Skip.")
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
            ns:RememberFreePosition()
            ns:AnchorWindow()
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
    BuildRaidPage(NewPage("raid", listTop))
    BuildGearPage(NewPage("gear", listTop))
    ns:BuildSettingsPage(NewPage("settings", TITLE_H + 6))

    -- tab row hanging under the frame, like the Group Finder's own tabs
    local tabs = CreateFrame("Frame", nil, frame)
    tabs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", PAD, 1)
    tabs:SetSize(4 * TAB_W + 3, TAB_H)
    frame.TabRow = tabs
    for i, def in ipairs({ { "dungeons", "Dungeons" }, { "raid", "Raid" }, { "gear", "Gear" }, { "settings", "Settings" } }) do
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
    frame:SetScript("OnHide", function()
        -- Following the Group Finder: keep the screen position current for
        -- the next time the window opens on its own.
        if ns.db.anchorSide == "free" and ns.db.freeFollow then ns:RememberFreePosition() end
        ns:RestoreGroupFinderOffset()
    end)
    return frame
end

function ns:ShowPage(key)
    BuildFrame()
    if not frame.Pages[key] then key = "dungeons" end
    for k, p in pairs(frame.Pages) do
        if k == key then p:Show() else p:Hide() end
    end
    CloseMenu()
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
    -- a Voidcore target drops here
    row.VCIcon = StarTexture(row, 11)
    row.VCIcon:SetPoint("RIGHT", -1, 0)
    SetStar(row.VCIcon, true, true)
    row.VCIcon:Hide()
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
    row.tipFn = onEnter
    row:SetScript("OnEnter", function(self) ns.hoveredTip = self; onEnter(self) end)
    row:SetScript("OnLeave", function() ns.hoveredTip = nil; GameTooltip:Hide() end)
    return row
end

-- Raid name above its bosses when the season has more than one raid.
local function NewSectionRow(content)
    local f = CreateFrame("Frame", nil, content)
    f:SetHeight(SECTION_H)
    f.Text = Style.Text(f, 11, 1, 1, 1, 0.6)
    f.Text:SetPoint("LEFT", 6, 0)
    f.Text:SetPoint("RIGHT", -6, 0)
    f.Text:SetJustifyH("LEFT")
    f.Text:SetWordWrap(false)
    f.Line = f:CreateTexture(nil, "ARTWORK")
    f.Line:SetHeight(1)
    f.Line:SetPoint("BOTTOMLEFT", 4, 2)
    f.Line:SetPoint("BOTTOMRIGHT", -4, 2)
    f.Line:SetColorTexture(1, 1, 1, 0.08)
    return f
end

local function SetRowCounts(row, count, wanted, scanned, accent, voidcore)
    if not scanned then
        row.Count:SetText("|cff888888...|r")
        row.Wanted:SetText("")
        row.WantIcon:Hide()
        row.VCIcon:Hide()
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
    row.VCIcon:SetShown((voidcore or 0) > 0)
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
    -- wanted star
    it.Star = CreateFrame("Button", nil, it)
    it.Star:SetSize(18, 18)
    it.Star:SetPoint("RIGHT", -4, 0)
    it.Star.Icon = StarTexture(it.Star, 14)
    it.Star.Icon:SetPoint("CENTER", 0, 0)
    it.Star:SetScript("OnClick", function(self)
        local parent = self:GetParent()
        local id = parent.eval and parent.eval.item.itemID
        if not id then return end
        -- (not `x and nil or "want"`: that can never yield nil)
        if ns:GetItemState(id) == "want" then
            ns:SetItemState(id, nil)
        else
            ns:SetItemState(id, "want")
        end
    end)
    it.Star:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local wanted = parent.eval and ns:GetItemState(parent.eval.item.itemID) == "want"
        GameTooltip:AddLine(wanted and "On your wanted list" or "Add to wanted list")
        GameTooltip:AddLine(wanted and "Click to remove it." or "Wanted items count for their dungeon or boss. They leave the list by themselves once you have the item.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    it.Star:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Voidcore star: what you would spend a Nebulous Voidcore on
    it.VC = CreateFrame("Button", nil, it)
    it.VC:SetSize(18, 18)
    it.VC:SetPoint("RIGHT", it.Star, "LEFT", -1, 0)
    it.VC.Icon = StarTexture(it.VC, 14)
    it.VC.Icon:SetPoint("CENTER", 0, 0)
    it.VC:SetScript("OnClick", function(self)
        local parent = self:GetParent()
        local id = parent.eval and parent.eval.item.itemID
        if not id then return end
        ns:SetVoidcoreTarget(id, not ns:IsVoidcoreTarget(id))
    end)
    it.VC:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local on = parent.eval and ns:IsVoidcoreTarget(parent.eval.item.itemID)
        GameTooltip:AddLine(on and (ns.VC_HEX .. "Voidcore target|r") or "Voidcore target")
        GameTooltip:AddLine(on and "Click to unmark it." or "Click: this is what you would spend a Nebulous Voidcore on.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    it.VC:SetScript("OnLeave", function() GameTooltip:Hide() end)
    it.Gain = Style.Text(it, 10)
    it.Gain:SetPoint("RIGHT", it.VC, "LEFT", -4, 0)
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
    it.tipFn = function(self) if self.eval then ns:ShowItemTooltip(self) end end
    it:SetScript("OnEnter", function(self) ns.hoveredTip = self; self.tipFn(self) end)
    it:SetScript("OnLeave", function() ns.hoveredTip = nil; GameTooltip:Hide() end)
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
    local counts = self:CountsAsUpgrade(eval)
    local state = self:GetItemState(eval.item.itemID)
    local target = self:IsVoidcoreTarget(eval.item.itemID)
    local lit = counts or state == "want" or target
    it.eval = eval
    it.Icon:SetTexture(eval.item.icon or 134400)
    if whereText then
        it.Where:SetText(whereText)
    else
        local slot = eval.slotID and self.SLOT_BY_ID[eval.slotID]
        it.Where:SetText(slot and (self.SLOT_SHORT[slot.id] or slot.key) or (eval.item.slotText or ""))
    end
    local name = ItemName(eval.item)
    if lit then
        it.Name:SetText(QualityHex(eval.item) .. name .. "|r")
        it.Name:SetAlpha(1)
    else
        it.Name:SetText(name)
        it.Name:SetAlpha(0.45)
    end
    if state == "exclude" then
        it.Gain:SetText("|cffff5555excluded|r")
    elseif eval.class == TRACK and eval.gain then
        it.Gain:SetText(string.format("%s%+d|r|cff888888/%+d|r", Hex(TRACK), eval.gain, eval.potentialGain or 0))
    elseif eval.class == ILVL and eval.gain then
        it.Gain:SetText(string.format("%s%+d|r", Hex(ILVL), eval.gain))
    elseif eval.class == WANT and eval.gain then
        it.Gain:SetText(string.format("%s%+d|r", eval.gain > 0 and Hex(ILVL) or "|cff777777", eval.gain))
    elseif eval.gain then
        it.Gain:SetText(string.format("|cff777777%+d|r", eval.gain))
    else
        it.Gain:SetText("")
    end
    it.Icon:SetDesaturated(not lit)
    it.Stats:SetText(self:StatText(eval.stats, eval.fit))
    SetStar(it.Star.Icon, state == "want")
    it.Star:Show()
    SetStar(it.VC.Icon, target, true)
    it.VC:Show()
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
    it.VC:Hide()
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
                GameTooltip:AddLine(string.format("  %s  |cff888888%s|r", w.eval.item.link or ItemName(w.eval.item), w.source or "?"), 1, 1, 1)
            end
        end
        if #summary.voidcore > 0 then
            if IsShiftKeyDown and IsShiftKeyDown() then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(ns.VC_HEX .. "Voidcore targets|r")
                for _, w in ipairs(summary.voidcore) do
                    GameTooltip:AddLine(string.format("  %s  |cff888888%s|r", w.eval.item.link or ItemName(w.eval.item), w.source or "?"), 1, 1, 1)
                end
            else
                GameTooltip:AddLine("|cff888888Shift: Voidcore targets|r")
            end
        end
        GameTooltip:AddLine(" ")
        if summary.count > 0 then
            GameTooltip:AddLine(string.format("%s%d upgrade drop(s)|r", Hex(summary.best), summary.count))
            local names = {}
            for _, src in pairs(summary.sources) do names[#names + 1] = src end
            table.sort(names, function(a, b) return a.name < b.name end)
            for _, src in ipairs(names) do
                GameTooltip:AddLine(string.format("  %s: %d", src.name, src.n), 0.8, 0.8, 0.8)
            end
        else
            GameTooltip:AddLine("No upgrade drops", 0.6, 0.6, 0.6)
        end
    end
    local state = self:GetSlotState(btn.slotID)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Slot: " .. (state == "want" and "|cff66bbffWant|r (every drop counts)"
        or state == "skip" and "|cffff5555Skip|r (never counts)" or "Auto"), 1, 1, 1)
    GameTooltip:AddLine("Click: compare its drops.  Right-click: cycle Auto / Want / Skip.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- Dungeon or boss row.
function ns:ShowDungeonTooltip(row)
    local r = row.result
    if not r then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(r.sourceName or "?")
    if r.raid then GameTooltip:AddLine(r.raid.name, 0.7, 0.7, 0.7) end
    if not r.scanned then
        GameTooltip:AddLine(r.raid and "No loot listed for this difficulty." or "Loot table not scanned yet.", 0.7, 0.7, 0.7)
    else
        local ctx = r.ctx or self.dropCtx
        GameTooltip:AddDoubleLine("Usable items for your spec", tostring(r.total), 0.9, 0.9, 0.9, 1, 1, 1)
        if ctx and ctx.ilvl then
            GameTooltip:AddLine(" ")
            local label = ctx.raid and ((ctx.difficultyName or "Raid") .. " drop") or string.format("End of dungeon (+%d)", ctx.key or 0)
            GameTooltip:AddLine(string.format("%s: %d %s", label, ctx.ilvl, TrackText(ctx.track, ctx.step)), 1, 0.82, 0)
            GameTooltip:AddDoubleLine("  Upgrade drops", string.format("%s%d|r", Hex(r.upgrades > 0 and TRACK or NONE), r.upgrades), 0.9, 0.9, 0.9)
            GameTooltip:AddDoubleLine("  Slots covered", tostring(r.slotCount), 0.9, 0.9, 0.9, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        if r.wanted > 0 then
            GameTooltip:AddLine(Style.AccentHex() .. "Wanted items here|r")
            for _, eval in ipairs(r.wantedItems) do
                GameTooltip:AddLine("  " .. (eval.item.link or ItemName(eval.item)), 1, 1, 1)
            end
        else
            GameTooltip:AddLine("Nothing from your wanted list drops here.", 0.6, 0.6, 0.6)
            GameTooltip:AddLine(string.format("Click the %s and star the drops you are after.", r.raid and "boss" or "dungeon"), 0.6, 0.6, 0.6, true)
        end
        -- the Voidcore roll, on request
        if IsShiftKeyDown and IsShiftKeyDown() then
            GameTooltip:AddLine(" ")
            local vc = ctx and ctx.voidcore
            if vc and vc.ilvl then
                GameTooltip:AddLine(string.format("%sVoidcore roll here:|r %d %s", ns.VC_HEX, vc.ilvl, TrackText(vc.track, vc.step)), 1, 1, 1)
            end
            if r.voidcore > 0 then
                GameTooltip:AddLine(ns.VC_HEX .. "Voidcore targets here|r")
                for _, eval in ipairs(r.voidcoreItems) do
                    GameTooltip:AddLine("  " .. (eval.item.link or ItemName(eval.item)), 1, 1, 1)
                end
            else
                GameTooltip:AddLine("No Voidcore targets here.", 0.6, 0.6, 0.6)
            end
        else
            GameTooltip:AddLine("|cff888888Shift: Voidcore roll|r")
        end
    end
    GameTooltip:Show()
end

function ns:ShowItemTooltip(btn)
    local eval = btn.eval
    if not eval then return end
    local item = eval.item
    local ctx = btn.ctx or self.dropCtx
    local shift = IsShiftKeyDown and IsShiftKeyDown()
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
            GameTooltip:AddLine(ctx.raid and string.format("|cff888888Shown as it drops on %s|r", ctx.difficultyName or "this difficulty")
                or string.format("|cff888888Shown as it drops from a +%d|r", ctx.key or 0))
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
    local function Verdict(r)
        local label = ns.UPGRADE_LABEL[r.class]
        local extra = r.reason and (" - " .. r.reason) or ""
        local s = Hex(r.class) .. label .. "|r" .. extra
        if r.gain and r.class ~= NONE then
            s = s .. string.format("  (%+d now, %+d fully upgraded)", r.gain, r.potentialGain or 0)
        end
        return s
    end
    local scale = ctx and ctx.statWeights
    if eval.value then
        ValueLine(string.format("Weighted value (%s)", scale and scale.name or "Pawn"), eval)
    end
    if ctx and ctx.ilvl then
        local label = ctx.raid and ((ctx.difficultyName or "Raid") .. " drop") or string.format("End of dungeon +%d", ctx.key or 0)
        GameTooltip:AddLine(string.format("%s: |cffffffff%d|r %s%s", label, ctx.ilvl,
            TrackText(ctx.track, ctx.step),
            (ctx.potential and ctx.potential > ctx.ilvl) and string.format(" (up to %d)", ctx.potential) or ""), 1, 0.82, 0, true)
    end
    GameTooltip:AddLine("  " .. Verdict(eval), 1, 1, 1, true)
    -- the Voidcore roll, on request
    local vc = ctx and ctx.voidcore
    if vc and vc.ilvl and eval.voidcore then
        if shift then
            GameTooltip:AddLine(string.format("%sVoidcore roll|r: |cffffffff%d|r %s%s", ns.VC_HEX, vc.ilvl,
                TrackText(vc.track, vc.step),
                (vc.potential and vc.potential > vc.ilvl) and string.format(" (up to %d)", vc.potential) or ""), 1, 1, 1, true)
            GameTooltip:AddLine("  " .. Verdict(eval.voidcore), 1, 1, 1, true)
            if eval.voidcore.value then ValueLine("  " .. ns.VC_HEX .. "Roll value|r", eval.voidcore) end
        else
            GameTooltip:AddLine("|cff888888Shift: Voidcore roll|r")
        end
    end
    local state = self:GetItemState(item.itemID)
    local target = self:IsVoidcoreTarget(item.itemID)
    GameTooltip:AddLine(" ")
    if state == "want" then GameTooltip:AddLine(Style.AccentHex() .. "On your wanted list|r") end
    if target then GameTooltip:AddLine(ns.VC_HEX .. "Voidcore target|r") end
    if state == "exclude" then
        GameTooltip:AddLine("|cffff5555Excluded|r  |cff888888(right-click to include again)|r")
    elseif not state and not target then
        GameTooltip:AddLine("|cff888888Star: want it.  Purple star: Voidcore it.  Right-click: exclude.|r", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

function ns:CycleItemState(itemID)
    local cur = self:GetItemState(itemID)
    if cur == "exclude" then
        self:SetItemState(itemID, nil)
    else
        self:SetItemState(itemID, "exclude")
    end
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
    if ctx.ilvl then
        parts[#parts + 1] = string.format("Drops at +%d: |cffffffff%d|r %s", ctx.key or 0, ctx.ilvl, TrackText(ctx.track, ctx.step))
    else
        parts[#parts + 1] = "|cffff5555Drop item level unknown|r"
    end
    local vc = ctx.voidcore
    if vc and vc.ilvl then
        parts[#parts + 1] = string.format("%sVoidcore:|r |cffffffff%d|r %s", ns.VC_HEX, vc.ilvl, TrackText(vc.track, vc.step))
    end
    if ctx.source == "fallback" then parts[#parts + 1] = "|cffff9900season table|r" end
    return table.concat(parts, "  |cff555555·|r  ")
end

local function RaidInfoText(ctx)
    local parts = {}
    if ctx.ilvl then
        parts[#parts + 1] = string.format("%s drops: |cffffffff%d|r %s", ctx.difficultyName or "Raid", ctx.ilvl, TrackText(ctx.track, ctx.step))
    else
        parts[#parts + 1] = "|cffff5555Drop item level unknown|r"
    end
    local vc = ctx.voidcore
    if vc and vc.ilvl then
        parts[#parts + 1] = string.format("%sVoidcore:|r |cffffffff%d|r %s", ns.VC_HEX, vc.ilvl, TrackText(vc.track, vc.step))
    end
    return table.concat(parts, "  |cff555555·|r  ")
end

local function RefreshStatusLine(page)
    local self = ns
    page.Status:SetText(StatusText())
    if self.scanProgress and self.scanProgress.total and self.scanProgress.total > 0 then
        page.Progress:SetValue(self.scanProgress.index / self.scanProgress.total)
        page.Progress:Show()
    else
        page.Progress:Hide()
    end
end

local function RefreshToolbar()
    local self = ns
    local bar = frame.Toolbar
    local specID = self:GetEvalSpecID()
    local specName, specIcon = self:SpecName(specID)
    bar.SpecButton.Icon:SetTexture(specIcon or 134400)
    bar.SpecButton.Text:SetText(self.cdb.evalSpecID and specName or (specName .. " |cff888888(loot spec)|r"))
    -- the key stepper is a Mythic+ thing; the Raid tab has its difficulty strip
    local raidTab = frame.page == "raid"
    for _, w in ipairs({ bar.KeyBox, bar.KeyPlus, bar.KeyMinus, bar.KeyLabel }) do w:SetShown(not raidTab) end
    bar.KeyText:SetText(self:TargetLabel())
    bar.KeyPlus:SetEnabled((self.db.targetKey or 10) < (self:MaxUsefulKey() or 10))
    RefreshStatProfileButton(bar.WeightsButton)
    local order, source = self:GetStatPriority()
    bar.Prio:SetText(order and (self:StatPriorityText(order) .. (source == "manual" and " |cff888888(manual order)|r" or ""))
        or "|cff888888no stat priority yet|r")
    if raidTab then
        bar.Info:SetText(RaidInfoText(self:GetRaidContext(self:GetRaidDifficulty())))
    else
        local ctx = self.dropCtx or self:GetDropContext()
        bar.Info:SetText(InfoText(ctx))
    end
end

-------------------------------------------------------------------------------
-- Frozen order. Starring or excluding a drop changes where it sorts, but a
-- list that is open must not jump around under the cursor: the order of the
-- rows and of the open list is captured when a row is expanded and kept
-- until that row is collapsed, another one opens, or the sort changes.
-------------------------------------------------------------------------------
local frozen = {}

-- `key` names the expansion (page + id); nil when nothing is open.
local function Freeze(key, sort)
    if key == nil or frozen.key ~= key or frozen.sort ~= sort then
        frozen = { key = key, sort = sort }
    end
end

-- Returns `list` in the order remembered under `slot`, new entries after the
-- remembered ones; remembers the current order when there is none yet.
local function KeepOrder(slot, list, keyOf)
    local order = frozen[slot]
    if not order then
        order = {}
        for i, e in ipairs(list) do order[i] = keyOf(e) end
        frozen[slot] = order
        return list
    end
    local byKey, out, seen = {}, {}, {}
    for _, e in ipairs(list) do byKey[keyOf(e)] = e end
    for _, k in ipairs(order) do
        local e = byKey[k]
        if e and not seen[k] then out[#out + 1] = e; seen[k] = true end
    end
    for _, e in ipairs(list) do
        local k = keyOf(e)
        if not seen[k] then out[#out + 1] = e; seen[k] = true end
    end
    return out
end

local function ItemKey(eval) return eval.item.itemID end

local function RefreshDungeons(page)
    local self = ns
    local db = self.db
    local sortMode = db.sortMode or "upgrades"
    if sortMode ~= "wanted" and sortMode ~= "name" then sortMode = "upgrades" end
    if page.ColHead.selectedTabID ~= sortMode then Style.SelectTab(page.ColHead, sortMode) end

    local results = self.results or {}
    if self.uiExpandedMapID then
        Freeze("dungeons:" .. self.uiExpandedMapID, sortMode)
        results = KeepOrder("top", results, function(r) return r.dungeon.challengeMapID end)
    elseif frame.page == "dungeons" then
        Freeze(nil)
    end

    local y = 0
    local rowIndex, itemIndex = 0, 0
    local content = page.Content
    local width = content:GetWidth()
    local accent = Style.AccentHex()
    for _, r in ipairs(results) do
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
                r.wanted, r.scanned, accent, r.voidcore)
            RowBackground(row, rowIndex, expanded, self.highlightMapID == row.mapID)
            y = y + ROW_H + 1
            if expanded and r.scanned then
                local shown = 0
                for _, eval in ipairs(KeepOrder("items", r.items, ItemKey)) do
                    local state = self:GetItemState(eval.item.itemID)
                    if self:CountsAsUpgrade(eval) or state == "want" or self:IsVoidcoreTarget(eval.item.itemID) or not db.hideNonUpgrades then
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
    RefreshStatusLine(page)
end

local function RefreshRaid(page)
    local self = ns
    local db = self.db
    local sortMode = db.raidSort or "boss"
    if sortMode ~= "upgrades" and sortMode ~= "wanted" then sortMode = "boss" end
    if page.ColHead.selectedTabID ~= sortMode then Style.SelectTab(page.ColHead, sortMode) end
    local diff = self:GetRaidDifficulty()
    if page.Strip.Tabs.selectedTabID ~= diff then Style.SelectTab(page.Strip.Tabs, diff) end

    local y = 0
    local rowIndex, itemIndex, headIndex = 0, 0, 0
    local content = page.Content
    local width = content:GetWidth()
    local accent = Style.AccentHex()
    local groups = self.raidResults or {}
    if self.uiExpandedEncounterID then
        Freeze("raid:" .. self.uiExpandedEncounterID, sortMode)
    else
        Freeze(nil)
    end
    local function Note(text)
        itemIndex = itemIndex + 1
        local it = Acquire(raidItems, itemIndex, function() return NewItemRow(content, false) end)
        it:ClearAllPoints()
        it:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        it:SetWidth(width)
        FillNoteRow(it, text)
        y = y + ITEM_H
    end
    for _, group in ipairs(groups) do
        if #groups > 1 then
            headIndex = headIndex + 1
            local h = Acquire(raidHeaders, headIndex, function() return NewSectionRow(content) end)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            h:SetWidth(width)
            h.Text:SetText(group.raid.name)
            y = y + SECTION_H
        end
        local bosses = group.bosses
        if self.uiExpandedEncounterID then
            bosses = KeepOrder("top:" .. tostring(group.raid.instanceID), bosses, function(r) return r.boss.encounterID end)
        end
        for _, r in ipairs(bosses) do
            local show = not (db.hideEmptyDungeons and r.scanned and r.upgrades == 0 and r.wanted == 0)
            if show then
                rowIndex = rowIndex + 1
                local row = Acquire(raidRows, rowIndex, function()
                    return NewTopRow(content, function(self2)
                        ns.uiExpandedEncounterID = (ns.uiExpandedEncounterID ~= self2.encounterID) and self2.encounterID or nil
                        ns:RefreshWindow()
                    end, nil, function(self2) ns:ShowDungeonTooltip(self2) end)
                end)
                row.result = r
                row.encounterID = r.boss.encounterID
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                row:SetWidth(width)
                row.Icon:SetTexture(r.boss.portrait or 134400)
                row.Icon:SetDesaturated(false)
                row.Border:SetColorTexture(0, 0, 0, 1)
                row.Name:SetText(r.boss.name)
                local expanded = self.uiExpandedEncounterID == row.encounterID
                row.Arrow:SetRotation(expanded and 0 or math.rad(90))
                if r.scanned then
                    SetRowCounts(row, string.format("%s%d|r", Hex(r.upgrades > 0 and (r.trackUpgrades > 0 and TRACK or ILVL) or NONE), r.upgrades),
                        r.wanted, true, accent, r.voidcore)
                else
                    SetRowCounts(row, "|cff444444-|r", 0, true, accent, 0)
                end
                RowBackground(row, rowIndex, expanded, false)
                y = y + ROW_H + 1
                if expanded then
                    local diffName = r.ctx and r.ctx.difficultyName or "this difficulty"
                    if not r.scanned then
                        Note("No loot listed for " .. diffName .. ".")
                    else
                        local shown = 0
                        for _, eval in ipairs(KeepOrder("items", r.items, ItemKey)) do
                            local state = self:GetItemState(eval.item.itemID)
                            if self:CountsAsUpgrade(eval) or state == "want" or self:IsVoidcoreTarget(eval.item.itemID) or not db.hideNonUpgrades then
                                shown = shown + 1
                                itemIndex = itemIndex + 1
                                local it = Acquire(raidItems, itemIndex, function() return NewItemRow(content, false) end)
                                it:ClearAllPoints()
                                it:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                                it:SetWidth(width)
                                it.dungeonName = nil
                                it.ctx = r.ctx
                                FillItemRow(it, eval)
                                y = y + ITEM_H
                            end
                        end
                        if shown == 0 then Note("No upgrades here on " .. diffName .. ".") end
                    end
                    y = y + 4
                end
            end
        end
    end
    if #groups == 0 then
        Note(self.loot and "No raids found in the journal for this season." or "Loot tables not scanned yet.")
    end
    for i = rowIndex + 1, #raidRows do raidRows[i]:Hide() end
    for i = itemIndex + 1, #raidItems do raidItems[i]:Hide() end
    for i = headIndex + 1, #raidHeaders do raidHeaders[i]:Hide() end
    content:SetHeight(math.max(y, 1))
    RefreshStatusLine(page)
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

-- [slotID] = { { eval, source, ctx }, ... } sorted, from what the Gear tab lists
local function DropsBySlot()
    local buckets = {}
    for _, r in ipairs(ns:GearResults()) do
        if r.scanned then
            for _, eval in ipairs(r.items) do
                if eval.slotID then
                    buckets[eval.slotID] = buckets[eval.slotID] or {}
                    table.insert(buckets[eval.slotID], { eval = eval, source = r.sourceName, ctx = r.ctx })
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

    local strip = page.Strip
    local source = db.gearSource or "both"
    if source ~= "mplus" and source ~= "raid" then source = "both" end
    if strip.Tabs.selectedTabID ~= source then Style.SelectTab(strip.Tabs, source) end
    local def = self.RAID_DIFF_BY_KEY[self:GetRaidDifficulty()]
    strip.Diff:SetText(source ~= "mplus" and def and def.name or "")
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

    if self.uiExpandedSlotID then
        Freeze("gear:" .. self.uiExpandedSlotID, sortMode)
        order = KeepOrder("top", order, function(s) return s.id end)
    else
        Freeze(nil)
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
        local e = summary[s.id] or { count = 0, wanted = {}, voidcore = {}, best = NONE }
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
        SetRowCounts(row, string.format("%s%d|r", Hex(e.count > 0 and e.best or NONE), e.count), #e.wanted, scanned, accent, #e.voidcore)
        RowBackground(row, rowIndex, expanded, false)
        y = y + ROW_H + 1
        if expanded then
            local list = KeepOrder("items", buckets[s.id] or {}, function(entry) return entry.eval.item.itemID .. "|" .. (entry.source or "") end)
            local shown = 0
            for _, entry in ipairs(list) do
                local eval = entry.eval
                local st = self:GetItemState(eval.item.itemID)
                if self:CountsAsUpgrade(eval) or st == "want" or self:IsVoidcoreTarget(eval.item.itemID) or not db.hideNonUpgrades then
                    shown = shown + 1
                    itemIndex = itemIndex + 1
                    local it = Acquire(gearItems, itemIndex, function() return NewItemRow(content, true) end)
                    it:ClearAllPoints()
                    it:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                    it:SetWidth(width)
                    it.dungeonName = entry.source
                    it.ctx = entry.ctx
                    FillItemRow(it, eval, entry.source)
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
                    FillNoteRow(it, "No drops for this slot.")
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
    elseif page == "raid" then
        RefreshRaid(frame.Pages.raid)
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
        -- Anchored to the Group Finder, the window moves whenever it does.
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
            -- First time next to the Group Finder since the option went on:
            -- the offset is wherever the window is now.
            self:RememberFreePosition()
            off = self.db.freeOffset
            if off then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", PVEFrame, "TOPLEFT", off.x, off.y)
            end
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
    print("  Weights:", self:StatProfileName() or "none", string.format("(%d profile(s) saved for this spec on this character)", #self:GetStatProfiles()))
    print("  Style:", Style.mode or "undecided", Style.IsSkinned() and "(EllesmereUI skin)" or "")
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
