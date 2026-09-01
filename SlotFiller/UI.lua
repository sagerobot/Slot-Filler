-- Slot Filler: main window (docks to the left of the Dungeons & Raids window).
local _, ns = ...

local WIDTH = 340
local FREE_HEIGHT = 520
local PAD = 6
local ROW_H = 26
local ITEM_H = 18
local SLOT_ICON = 22

local frame
local rowPool, itemPool = {}, {}
local slotButtons = {}
ns.uiExpanded = {}

local NONE, ILVL, TRACK, WANT = ns.UPGRADE_NONE, ns.UPGRADE_ILVL, ns.UPGRADE_TRACK, ns.UPGRADE_WANT

local function Color(class)
    local c = ns.UPGRADE_COLOR[class] or ns.UPGRADE_COLOR[0]
    return c[1], c[2], c[3]
end

local function Hex(class)
    local r, g, b = Color(class)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function Styled(f)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.96)
    f:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)
end

local function SmallButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 60, 18)
    b:SetText(text)
    local fs = b:GetFontString()
    if fs then fs:SetFontObject("GameFontNormalSmall") end
    return b
end

local function TrackText(track, step)
    if not track then return "" end
    if step then
        return string.format("%s %d/%d", ns:TrackDisplayName(track), step, track.steps)
    end
    return ns:TrackDisplayName(track)
end

-------------------------------------------------------------------------------
-- Equipped item description for tooltips
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

-------------------------------------------------------------------------------
-- Frame construction
-------------------------------------------------------------------------------
local function BuildFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "SlotFillerFrame", UIParent, "BackdropTemplate")
    Styled(frame)
    frame:SetSize(WIDTH, FREE_HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(false)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    tinsert(UISpecialFrames, "SlotFillerFrame")

    -- title bar
    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT", 4, -4)
    title:SetPoint("TOPRIGHT", -4, -4)
    title:SetHeight(20)
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

    local titleText = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", 6, 0)
    titleText:SetText("|cff4fc3f7Slot Filler|r")
    frame.TitleText = titleText

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 1, 1)
    close:SetSize(24, 24)
    close:SetScript("OnClick", function() ns:HideWindow(true) end)

    local gear = SmallButton(frame, "Options", 54)
    gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
    gear:SetScript("OnClick", function() ns:ToggleOptionsPanel() end)
    frame.OptionsButton = gear

    local rescan = SmallButton(frame, "Rescan", 52)
    rescan:SetPoint("RIGHT", gear, "LEFT", -2, 0)
    rescan:SetScript("OnClick", function() ns:RescanLoot(true) end)
    rescan:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Rescan loot tables")
        GameTooltip:AddLine("Re-reads every dungeon's loot from the Adventure Guide for the selected spec.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    rescan:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.RescanButton = rescan

    -- header: spec + key selector
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", PAD, -26)
    header:SetPoint("TOPRIGHT", -PAD, -26)
    header:SetHeight(22)
    frame.Header = header

    local specBtn = CreateFrame("Button", nil, header)
    specBtn:SetSize(150, 20)
    specBtn:SetPoint("LEFT", 0, 0)
    specBtn.Icon = specBtn:CreateTexture(nil, "ARTWORK")
    specBtn.Icon:SetSize(16, 16)
    specBtn.Icon:SetPoint("LEFT", 0, 0)
    specBtn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    specBtn.Text = specBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    specBtn.Text:SetPoint("LEFT", specBtn.Icon, "RIGHT", 4, 0)
    specBtn.Text:SetPoint("RIGHT", 0, 0)
    specBtn.Text:SetJustifyH("LEFT")
    specBtn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    specBtn:SetScript("OnClick", function() ns:CycleEvalSpec() end)
    specBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Spec to evaluate")
        GameTooltip:AddLine("Click to cycle: follow loot spec, or a specific spec.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Loot is filtered the same way the Adventure Guide filters it.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    specBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.SpecButton = specBtn

    local keyPlus = SmallButton(header, "+", 20)
    keyPlus:SetPoint("RIGHT", 0, 0)
    keyPlus:SetScript("OnClick", function() ns:StepTargetKey(1) end)
    local keyText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keyText:SetPoint("RIGHT", keyPlus, "LEFT", -3, 0)
    keyText:SetWidth(56)
    keyText:SetJustifyH("CENTER")
    local keyMinus = SmallButton(header, "-", 20)
    keyMinus:SetPoint("RIGHT", keyText, "LEFT", -3, 0)
    keyMinus:SetScript("OnClick", function() ns:StepTargetKey(-1) end)
    local keyLabel = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    keyLabel:SetPoint("RIGHT", keyMinus, "LEFT", -4, 0)
    keyLabel:SetText("Key")
    frame.KeyText = keyText
    frame.KeyPlus, frame.KeyMinus = keyPlus, keyMinus
    for _, b in ipairs({ keyPlus, keyMinus }) do
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("Key level")
            GameTooltip:AddLine("Drops are evaluated at the end-of-dungeon item level of this key. Past the last key that still raises it, the selector switches to the Voidcore roll (vault item level).", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- slot strip (2 rows x 8) + summary text on the right
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    strip:SetSize(8 * SLOT_ICON + 7 * 2, 2 * SLOT_ICON + 2)
    frame.Strip = strip
    for i, s in ipairs(ns.SLOTS) do
        local b = CreateFrame("Button", nil, strip)
        b:SetSize(SLOT_ICON, SLOT_ICON)
        local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
        b:SetPoint("TOPLEFT", col * (SLOT_ICON + 2), -row * (SLOT_ICON + 2))
        b.Border = b:CreateTexture(nil, "BACKGROUND")
        b.Border:SetPoint("TOPLEFT", -1, 1)
        b.Border:SetPoint("BOTTOMRIGHT", 1, -1)
        b.Border:SetColorTexture(0.3, 0.3, 0.3, 1)
        b.Icon = b:CreateTexture(nil, "ARTWORK")
        b.Icon:SetAllPoints()
        b.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.Overlay = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.Overlay:SetPoint("CENTER")
        b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.Count:SetPoint("BOTTOMRIGHT", 1, 0)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.slotID = s.id
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                ns.cdb.slotState[self.slotID] = nil
                ns:Fire("SETTINGS_CHANGED")
            else
                ns:CycleSlotState(self.slotID)
            end
        end)
        b:SetScript("OnEnter", function(self) ns:ShowSlotTooltip(self) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        slotButtons[s.id] = b
    end

    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", strip, "TOPRIGHT", 8, 0)
    summary:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    summary:SetJustifyH("LEFT")
    summary:SetJustifyV("TOP")
    summary:SetHeight(strip:GetHeight())
    frame.Summary = summary

    -- sort row
    local sortRow = CreateFrame("Frame", nil, frame)
    sortRow:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -4)
    sortRow:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    sortRow:SetHeight(18)
    local sortLabel = sortRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sortLabel:SetPoint("LEFT", 0, 0)
    sortLabel:SetText("Sort:")
    frame.SortButtons = {}
    local prev = sortLabel
    for _, def in ipairs({ { "upgrades", "Drops" }, { "voidcore", "Voidcore" }, { "slots", "Slots" }, { "name", "Name" } }) do
        local b = CreateFrame("Button", nil, sortRow)
        b:SetHeight(16)
        b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.Text:SetPoint("LEFT", 0, 0)
        b.Text:SetText(def[2])
        b:SetWidth(b.Text:GetStringWidth() + 6)
        b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        b.mode = def[1]
        b:SetScript("OnClick", function(self)
            ns.db.sortMode = self.mode
            ns:Fire("SETTINGS_CHANGED")
        end)
        frame.SortButtons[def[1]] = b
        prev = b
    end
    local hideEmpty = CreateFrame("CheckButton", nil, sortRow, "UICheckButtonTemplate")
    hideEmpty:SetSize(20, 20)
    hideEmpty:SetPoint("RIGHT", 0, 0)
    hideEmpty.Label = hideEmpty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideEmpty.Label:SetPoint("RIGHT", hideEmpty, "LEFT", -2, 0)
    hideEmpty.Label:SetText("Hide empty")
    hideEmpty:SetScript("OnClick", function(self)
        ns.db.hideEmptyDungeons = self:GetChecked() and true or false
        ns:RefreshWindow()
    end)
    frame.HideEmpty = hideEmpty

    -- footer
    local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", PAD, 6)
    footer:SetPoint("BOTTOMRIGHT", -PAD, 6)
    footer:SetJustifyH("LEFT")
    footer:SetHeight(12)
    frame.Footer = footer

    -- column headers
    local colHead = CreateFrame("Frame", nil, frame)
    colHead:SetPoint("TOPLEFT", sortRow, "BOTTOMLEFT", 0, -2)
    colHead:SetPoint("RIGHT", frame, "RIGHT", -26, 0)
    colHead:SetHeight(12)
    local h1 = colHead:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h1:SetPoint("LEFT", 2, 0)
    h1:SetText("Dungeon")
    local h3 = colHead:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h3:SetPoint("RIGHT", -4, 0)
    h3:SetWidth(46)
    h3:SetJustifyH("RIGHT")
    h3:SetText(ns.VC_HEX .. "Voidcore|r")
    local h2 = colHead:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h2:SetPoint("RIGHT", h3, "LEFT", -6, 0)
    h2:SetJustifyH("RIGHT")
    h2:SetText("Drops")
    colHead:SetScript("OnEnter", nil)
    frame.ColHead = colHead

    -- scroll list
    local scroll = CreateFrame("ScrollFrame", "SlotFillerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", colHead, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 20)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 40, 10)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w)
        content:SetWidth(w)
    end)
    frame.Scroll = scroll
    frame.Content = content

    frame:SetScript("OnShow", function() ns:RefreshWindow() end)
    frame:SetScript("OnHide", function()
        ns:RestoreGroupFinderOffset()
        if ns.optionsPanel then ns.optionsPanel:Hide() end
    end)
    return frame
end

-------------------------------------------------------------------------------
-- Row pools
-------------------------------------------------------------------------------
local function AcquireRow(index)
    local row = rowPool[index]
    if row then row:Show(); return row end
    row = CreateFrame("Button", nil, frame.Content)
    row:SetHeight(ROW_H)
    row.Bg = row:CreateTexture(nil, "BACKGROUND")
    row.Bg:SetAllPoints()
    row.Bg:SetColorTexture(1, 1, 1, 0.05)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(ROW_H - 4, ROW_H - 4)
    row.Icon:SetPoint("LEFT", 2, 0)
    row.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    row.Arrow = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.Arrow:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
    row.Arrow:SetWidth(10)
    row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.Name:SetPoint("LEFT", row.Arrow, "RIGHT", 2, 0)
    row.Name:SetJustifyH("LEFT")
    row.Chance = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Chance:SetPoint("RIGHT", -4, 0)
    row.Chance:SetWidth(46)
    row.Chance:SetJustifyH("RIGHT")
    row.Count = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.Count:SetPoint("RIGHT", row.Chance, "LEFT", -6, 0)
    row.Count:SetJustifyH("RIGHT")
    row.Name:SetPoint("RIGHT", row.Count, "LEFT", -4, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
        local id = self.mapID
        ns.uiExpanded[id] = not ns:IsExpanded(id)
        ns:RefreshWindow()
    end)
    row:SetScript("OnEnter", function(self) ns:ShowDungeonTooltip(self) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rowPool[index] = row
    return row
end

local function AcquireItem(index)
    local it = itemPool[index]
    if it then it:Show(); return it end
    it = CreateFrame("Button", nil, frame.Content)
    it:SetHeight(ITEM_H)
    it.Icon = it:CreateTexture(nil, "ARTWORK")
    it.Icon:SetSize(ITEM_H - 2, ITEM_H - 2)
    it.Icon:SetPoint("LEFT", ROW_H + 6, 0)
    it.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    it.Slot = it:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    it.Slot:SetPoint("LEFT", it.Icon, "RIGHT", 4, 0)
    it.Slot:SetWidth(36)
    it.Slot:SetJustifyH("LEFT")
    it.Gain = it:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    it.Gain:SetPoint("RIGHT", -4, 0)
    it.Gain:SetWidth(52)
    it.Gain:SetJustifyH("RIGHT")
    it.Name = it:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    it.Name:SetPoint("LEFT", it.Slot, "RIGHT", 2, 0)
    it.Name:SetPoint("RIGHT", it.Gain, "LEFT", -4, 0)
    it.Name:SetJustifyH("LEFT")
    it.Name:SetWordWrap(false)
    it:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    it:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    it:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ns:CycleItemState(self.eval.item.itemID)
        elseif IsModifiedClick("CHATLINK") and self.eval.item.link then
            ChatEdit_InsertLink(self.eval.item.link)
        elseif IsModifiedClick("DRESSUP") and self.eval.item.link then
            DressUpItemLink(self.eval.item.link)
        end
    end)
    it:SetScript("OnEnter", function(self) ns:ShowItemTooltip(self) end)
    it:SetScript("OnLeave", function() GameTooltip:Hide() end)
    itemPool[index] = it
    return it
end

function ns:IsExpanded(mapID)
    local v = self.uiExpanded[mapID]
    if v == nil then return not self.db.collapsed end
    return v
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
        if summary.count > 0 then
            GameTooltip:AddLine(string.format("%s%d upgrade drop(s) available|r", Hex(summary.best), summary.count))
            for mapID, n in pairs(summary.dungeons) do
                local d = self.dungeonByMapID[mapID]
                if d then GameTooltip:AddLine(string.format("  %s: %d", d.name, n), 0.8, 0.8, 0.8) end
            end
        else
            GameTooltip:AddLine("No upgrade drops at this key level", 0.6, 0.6, 0.6)
        end
        if summary.vcCount > 0 then
            GameTooltip:AddLine(string.format("%s%d item(s) would upgrade this slot from a Voidcore roll|r", ns.VC_HEX, summary.vcCount))
        end
    end
    local state = self:GetSlotState(btn.slotID)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("State: " .. (state == "want" and "|cff66bbffWant|r (every drop counts)"
        or state == "skip" and "|cffff5555Skip|r (never counts)" or "Auto"), 1, 1, 1)
    GameTooltip:AddLine("Left-click: cycle Auto / Want / Skip.  Right-click: reset.", 0.6, 0.6, 0.6)
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
        GameTooltip:AddLine(" ")
        if ctx and ctx.ilvl then
            GameTooltip:AddLine(string.format("End of dungeon (+%d): %d %s", ctx.key, ctx.ilvl, TrackText(ctx.track, ctx.step)), 1, 0.82, 0)
        end
        GameTooltip:AddDoubleLine("  Upgrade drops", string.format("%s%d|r", Hex(r.upgrades > 0 and TRACK or NONE), r.upgrades), 0.9, 0.9, 0.9)
        GameTooltip:AddDoubleLine("  Slots covered", tostring(r.slotCount), 0.9, 0.9, 0.9, 1, 1, 1)
        GameTooltip:AddDoubleLine("  Chance per drop", string.format("%d%%", r.chance * 100 + 0.5), 0.9, 0.9, 0.9, 1, 1, 1)
        GameTooltip:AddLine(" ")
        local vc = ctx and ctx.voidcore
        if vc and vc.ilvl then
            GameTooltip:AddLine(string.format("%sNebulous Voidcore roll|r: %d %s", ns.VC_HEX, vc.ilvl, TrackText(vc.track, vc.step)), 1, 1, 1)
            GameTooltip:AddDoubleLine("  Upgrade items", string.format("%s%d|r", ns.VC_HEX, r.vcUpgrades), 0.9, 0.9, 0.9)
            GameTooltip:AddDoubleLine("  Chance the roll is an upgrade", string.format("%s%d%%|r", ns.VC_HEX, r.vcChance * 100 + 0.5), 0.9, 0.9, 0.9)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("A Voidcore gives one extra random item for your loot spec from this dungeon at the Great Vault item level of the key. Spend it where this chance is highest. Right-click items you already received from a Voidcore to exclude them.", 0.6, 0.6, 0.6, true)
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
    GameTooltip:AddLine("Right-click: " .. (state == "exclude" and "excluded -> want" or state == "want" and "wanted -> normal" or "normal -> exclude"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function ns:CycleItemState(itemID)
    local cur = self:GetItemState(itemID)
    local nextState = (cur == nil and "exclude") or (cur == "exclude" and "want") or nil
    self:SetItemState(itemID, nextState)
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
local function SetSlotButton(b, summary)
    local slotID = b.slotID
    local g = ns.gear[slotID]
    local icon = GetInventoryItemTexture("player", slotID)
    if icon then
        b.Icon:SetTexture(icon)
        b.Icon:SetDesaturated(false)
    else
        b.Icon:SetTexture(ns.SLOT_EMPTY_TEXTURE[slotID] or 134400)
        b.Icon:SetDesaturated(true)
    end
    local state = ns:GetSlotState(slotID)
    local s = summary and summary[slotID]
    b.Overlay:SetText("")
    b.Count:SetText("")
    if state == "skip" then
        b.Border:SetColorTexture(0.8, 0.2, 0.2, 1)
        b.Overlay:SetText("|cffff4444X|r")
        b.Icon:SetDesaturated(true)
    elseif state == "want" then
        b.Border:SetColorTexture(0.35, 0.7, 1, 1)
        if s and s.count > 0 then b.Count:SetText(s.count) end
    elseif s and s.count > 0 then
        local r, gg, bb = Color(s.best)
        b.Border:SetColorTexture(r, gg, bb, 1)
        b.Count:SetText(s.count)
    else
        b.Border:SetColorTexture(0.3, 0.3, 0.3, 1)
    end
    -- items at their fully upgraded max with no upgrade: dim slightly
    if g and not g.empty and (not s or s.count == 0) and state == "auto" then
        b.Icon:SetVertexColor(0.6, 0.6, 0.6)
    else
        b.Icon:SetVertexColor(1, 1, 1)
    end
end

local function DungeonIcon(d)
    if d.texture then return d.texture end
    return 134400
end

function ns:RefreshWindow()
    if not frame or not frame:IsShown() then return end
    local db = self.db
    -- header
    local specID = self:GetEvalSpecID()
    local specName, specIcon = self:SpecName(specID)
    frame.SpecButton.Icon:SetTexture(specIcon or 134400)
    frame.SpecButton.Text:SetText((self.cdb.evalSpecID and specName or (specName .. " (loot spec)")))
    frame.KeyText:SetText(self:TargetLabel())
    if frame.KeyPlus then frame.KeyPlus:SetEnabled(not db.voidcoreMode) end

    -- summary
    local ctx = self.dropCtx or self:GetDropContext()
    local lines = {}
    if ctx.isVoidcore then
        if ctx.ilvl then
            table.insert(lines, string.format("%sVoidcore roll (+%d):|r |cffffffff%d|r %s%s", ns.VC_HEX, ctx.key, ctx.ilvl, TrackText(ctx.track, ctx.step),
                (ctx.potential and ctx.potential > ctx.ilvl) and string.format(" |cff888888(to %d)|r", ctx.potential) or ""))
        else
            table.insert(lines, "|cffff5555Voidcore item level unknown|r")
        end
    else
        if ctx.ilvl then
            table.insert(lines, string.format("+%d drop: |cffffffff%d|r %s%s", ctx.key, ctx.ilvl, TrackText(ctx.track, ctx.step),
                (ctx.potential and ctx.potential > ctx.ilvl) and string.format(" |cff888888(to %d)|r", ctx.potential) or ""))
        else
            table.insert(lines, "|cffff5555Drop item level unknown|r")
        end
        local vc = ctx.voidcore
        if vc and vc.ilvl then
            table.insert(lines, string.format("%sVoidcore:|r |cffffffff%d|r %s%s", ns.VC_HEX, vc.ilvl, TrackText(vc.track, vc.step),
                (vc.potential and vc.potential > vc.ilvl) and string.format(" |cff888888(to %d)|r", vc.potential) or ""))
        end
    end
    if ctx.source == "fallback" then table.insert(lines, "|cffff9900(levels from season table)|r") end
    self.slotSummary = self:SlotSummary()
    local slotsWith = 0
    for _, s in pairs(self.slotSummary) do if s.count > 0 then slotsWith = slotsWith + 1 end end
    table.insert(lines, string.format("Slots with upgrades: |cffffffff%d|r / %d", slotsWith, #self.SLOTS))
    frame.Summary:SetText(table.concat(lines, "\n"))

    for _, b in pairs(slotButtons) do SetSlotButton(b, self.slotSummary) end

    for mode, b in pairs(frame.SortButtons) do
        if mode == (db.sortMode or "upgrades") then
            b.Text:SetTextColor(1, 0.82, 0)
        else
            b.Text:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    frame.HideEmpty:SetChecked(db.hideEmptyDungeons)

    -- list
    local y = 0
    local rowIndex, itemIndex = 0, 0
    local content = frame.Content
    local width = content:GetWidth()
    local results = self.results or {}
    for _, r in ipairs(results) do
        local show = not (db.hideEmptyDungeons and r.scanned and r.upgrades == 0)
        if show then
            rowIndex = rowIndex + 1
            local row = AcquireRow(rowIndex)
            row.result = r
            row.mapID = r.dungeon.challengeMapID
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:SetWidth(width)
            row.Icon:SetTexture(DungeonIcon(r.dungeon))
            row.Name:SetText(r.dungeon.name)
            local expanded = self:IsExpanded(row.mapID)
            row.Arrow:SetText(expanded and "-" or "+")
            if r.scanned then
                row.Count:SetText(string.format("%s%d|r", Hex(r.upgrades > 0 and (r.trackUpgrades > 0 and TRACK or ILVL) or NONE), r.upgrades))
                if self.dropCtx and self.dropCtx.voidcore then
                    row.Chance:SetText(string.format("%s%d%%|r", r.vcUpgrades > 0 and ns.VC_HEX or "|cff666666", r.vcChance * 100 + 0.5))
                else
                    row.Chance:SetText("")
                end
            else
                row.Count:SetText("|cff888888...|r")
                row.Chance:SetText("")
            end
            if self.highlightMapID == row.mapID then
                row.Bg:SetColorTexture(0.3, 0.6, 1, 0.25)
            else
                row.Bg:SetColorTexture(1, 1, 1, 0.05)
            end
            y = y + ROW_H + 1
            if expanded and r.scanned then
                for _, eval in ipairs(r.items) do
                    local counts = self:CountsAsUpgrade(eval)
                    local vcCounts = self:CountsAsUpgrade(eval, "voidcore")
                    if counts or vcCounts or not db.hideNonUpgrades then
                        itemIndex = itemIndex + 1
                        local it = AcquireItem(itemIndex)
                        it.eval = eval
                        it:ClearAllPoints()
                        it:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                        it:SetWidth(width)
                        it.Icon:SetTexture(eval.item.icon or 134400)
                        local slot = eval.slotID and self.SLOT_BY_ID[eval.slotID]
                        it.Slot:SetText(slot and (self.SLOT_SHORT[slot.id] or slot.key) or (eval.item.slotText or ""))
                        local name = eval.item.link and eval.item.link:match("%[(.-)%]") or eval.item.name or ("item " .. eval.item.itemID)
                        local qualityColor = eval.item.link and eval.item.link:match("|c(%x%x%x%x%x%x%x%x)")
                        if counts or vcCounts then
                            it.Name:SetText((qualityColor and ("|c" .. qualityColor) or "|cffffffff") .. name .. "|r")
                            it.Name:SetAlpha(1)
                        else
                            it.Name:SetText(name)
                            it.Name:SetAlpha(0.45)
                        end
                        local state = self:GetItemState(eval.item.itemID)
                        local vcTag = (vcCounts and not counts) and (ns.VC_HEX .. "VC|r ") or (vcCounts and (ns.VC_HEX .. "*|r") or "")
                        if state == "exclude" then
                            it.Gain:SetText("|cffff5555excluded|r")
                        elseif eval.class == WANT then
                            it.Gain:SetText(Hex(WANT) .. "want|r")
                        elseif eval.class == TRACK and eval.gain then
                            it.Gain:SetText(string.format("%s%s%+d|r|cff888888/%+d|r", vcTag, Hex(TRACK), eval.gain, eval.potentialGain or 0))
                        elseif eval.class == ILVL and eval.gain then
                            it.Gain:SetText(string.format("%s%s%+d|r", vcTag, Hex(ILVL), eval.gain))
                        elseif vcCounts and eval.voidcore then
                            it.Gain:SetText(string.format("%s%+d|r", ns.VC_HEX, eval.voidcore.potentialGain or eval.voidcore.gain or 0) .. " " .. vcTag)
                        elseif eval.gain then
                            it.Gain:SetText(string.format("|cff777777%+d|r", eval.gain))
                        else
                            it.Gain:SetText("")
                        end
                        it.Icon:SetDesaturated(not (counts or vcCounts))
                        y = y + ITEM_H
                    end
                end
                y = y + 3
            end
        end
    end
    for i = rowIndex + 1, #rowPool do rowPool[i]:Hide() end
    for i = itemIndex + 1, #itemPool do itemPool[i]:Hide() end
    content:SetHeight(math.max(y, 1))

    -- footer
    local status
    if self.scanProgress then
        status = string.format("Scanning loot %d/%d: %s", self.scanProgress.index, self.scanProgress.total, self.scanProgress.name or "")
    elseif not self.dungeonsBuilt then
        status = "Waiting for season data..."
    elseif self.loot and self.loot.time then
        local age = time() - self.loot.time
        local ageText = age < 3600 and string.format("%dm", age / 60) or age < 86400 and string.format("%dh", age / 3600) or string.format("%dd", age / 86400)
        status = string.format("Loot tables from the Adventure Guide, scanned %s ago.", ageText)
    else
        status = "Loot tables not scanned yet."
    end
    if self.trackOffsetApplied and self.trackOffsetApplied ~= 0 then
        status = status .. string.format("  Tracks calibrated %+d.", self.trackOffsetApplied)
    end
    frame.Footer:SetText(status)
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

local function DockLeft()
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", PVEFrame, "TOPLEFT", -2, 0)
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

-- While docked on the left, keep checking that the Group Finder has not been
-- moved back over us by the UI panel manager (opening another panel does that).
local function OnUpdateWatch(self, elapsed)
    self.watchElapsed = (self.watchElapsed or 0) + elapsed
    if self.watchElapsed < 0.5 then return end
    self.watchElapsed = 0
    if PVEFrame and PVEFrame:IsShown() and (ns.db.anchorSide or "left") == "left" and not InCombatLockdown() then
        if Overhang() > 0 then PushGroupFinder() end
    end
end

function ns:ShowWindow(manual)
    BuildFrame()
    if manual then self.standalone = not (PVEFrame and PVEFrame:IsShown()) end
    self:RequestSeasonData()
    self:AnchorWindow()
    frame:SetScript("OnUpdate", OnUpdateWatch)
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
