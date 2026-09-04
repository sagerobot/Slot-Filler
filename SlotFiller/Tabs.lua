-- Slot Filler: the five tabs. Each builds its page once and fills it on
-- every refresh from pooled rows.
--
-- Dungeons: dungeon rows that open into the drops they hold.
-- Raid:     boss rows, judged at the difficulty picked on the tab's strip.
-- Gear:     slot rows that open into every drop for that slot, from
--           dungeons, raids or both, ordered by stat fit, so same-slot
--           drops can be compared and starred.
-- IO:       dungeon rows with the best run and the planned key that reach a
--           target rating; rows open into a key ladder (Rating.lua).
-- Voidcore: where a Nebulous Voidcore is best spent; rows open into the pool.
local _, ns = ...
local Style, UI = ns.Style, ns.UI
local P = UI.Pools

local ROW_H, ITEM_H, STRIP_H, GUTTER = UI.ROW_H, UI.ITEM_H, UI.STRIP_H, UI.GUTTER
local NONE, ILVL, TRACK = ns.UPGRADE_NONE, ns.UPGRADE_ILVL, ns.UPGRADE_TRACK
local HEX = ns.UPGRADE_HEX

local function DungeonIcon(d)
    return d.texture or 134400
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
    if key == nil or frozen.key ~= key or frozen.sort ~= sort then frozen = { key = key, sort = sort } end
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

-------------------------------------------------------------------------------
-- Shared pieces of the drop lists
-------------------------------------------------------------------------------
-- The sort a column header shows, defaulting when the saved one is not one of the choices.
local function SelectSort(page, key, choices, default)
    local mode = ns.db[key]
    if not choices[mode] then mode = default end
    if page.ColHead.selectedTabID ~= mode then Style.SelectTab(page.ColHead, mode) end
    return mode
end

-- Whether a drop is listed under an open row (the setting hides non-upgrades).
local function ShowsDrop(eval)
    if not ns.db.hideNonUpgrades then return true end
    local id = eval.item.itemID
    return ns:CountsAsUpgrade(eval) or ns:GetItemState(id) == "want" or ns:IsVoidcoreTarget(id)
end

local function Note(L, pool, wide, text)
    UI.FillNoteRow(L:Add(pool, function() return UI.NewItemRow(L.content, wide) end, ITEM_H), text)
end

-- The drops under an open row: one row each (a nested token's pieces
-- indented under it), or a note. entries = { { eval, source, ctx }, ... }.
local function ListDrops(L, pool, wide, entries, emptyText)
    local function Factory() return UI.NewItemRow(L.content, wide) end
    local shown = 0
    for _, e in ipairs(entries) do
        if ShowsDrop(e.eval) then
            shown = shown + 1
            local it = L:Add(pool, Factory, ITEM_H)
            it.dungeonName, it.ctx = e.source, e.ctx
            UI.FillItemRow(it, e.eval, e.source)
            if UI.TokenNested(e.eval) and ns.uiExpandedTokenID == e.eval.token.itemID then
                for _, piece in ipairs(e.eval.pieces) do
                    local pit = L:Add(pool, Factory, ITEM_H, 16)
                    pit.dungeonName, pit.ctx = e.source, e.ctx
                    UI.FillItemRow(pit, piece, e.source)
                end
            end
        end
    end
    if shown == 0 then Note(L, pool, wide, emptyText) end
    L:Gap(4)
end

local function Entries(evals, ctx)
    local out = {}
    for i, eval in ipairs(evals) do out[i] = { eval = eval, ctx = ctx } end
    return out
end

-- A dungeon or boss row.
local function FillSourceRow(row, index, r, icon, expanded, highlighted)
    row.result = r
    row.Icon:SetTexture(icon)
    row.Icon:SetDesaturated(false)
    row.Border:SetColorTexture(0, 0, 0, 1)
    row.Name:SetText(r.sourceName)
    row.Arrow:SetRotation(expanded and 0 or math.rad(90))
    UI.RowBackground(row, index, expanded, highlighted)
end

local function Hidden(r)
    return ns.db.hideEmptyDungeons and r.scanned and r.upgrades == 0 and r.wanted == 0
end

-------------------------------------------------------------------------------
-- Dungeons
-------------------------------------------------------------------------------
local Dungeons = { key = "dungeons", label = "Dungeons" }

function Dungeons.Build(page)
    page.ColHead = UI.ColumnHeader(page, {
        { "name", "Dungeon", nil, "Click to sort by name. Click a dungeon to see its drops." },
        { "upgrades", "Drops", UI.COL_DROPS, "Spec-usable items that would upgrade a slot as an end-of-dungeon drop at the selected key. Click to sort." },
        { "wanted", "Wanted", UI.COL_WANTED, "Items from your wanted list that drop in this dungeon; a purple star means a Voidcore target drops here. Click to sort." },
    }, function(mode) ns.db.sortMode = mode end)
    page.List, page.Content = UI.ListPanel(page, page.ColHead, 18)
    UI.StatusLine(page)
end

function Dungeons.Refresh(page)
    local sortMode = SelectSort(page, "sortMode", { upgrades = true, wanted = true, name = true }, "upgrades")
    local results = ns.results or {}
    if ns.uiExpandedMapID then
        Freeze("dungeons:" .. ns.uiExpandedMapID, sortMode)
        results = KeepOrder("top", results, function(r) return r.dungeon.challengeMapID end)
    else
        Freeze(nil)
    end
    local L = UI.Layout(page.Content)
    for _, r in ipairs(results) do
        if not Hidden(r) then
            local row = L:Add(P.dungeonRows, function()
                return UI.NewTopRow(L.content, function(self)
                    ns.uiExpandedMapID = (ns.uiExpandedMapID ~= self.mapID) and self.mapID or nil
                    ns:RefreshWindow()
                end, nil, function(self) ns:ShowDungeonTooltip(self) end)
            end, ROW_H + 1)
            row.mapID = r.dungeon.challengeMapID
            local expanded = ns.uiExpandedMapID == row.mapID
            FillSourceRow(row, L:Count(P.dungeonRows), r, DungeonIcon(r.dungeon), expanded, ns.highlightMapID == row.mapID)
            UI.SetRowCounts(row, ns.DropsHex(r) .. r.upgrades .. "|r", r.wanted, r.scanned, r.voidcore)
            if expanded and r.scanned then
                ListDrops(L, P.dungeonItems, false, Entries(KeepOrder("items", r.items, ItemKey)), "No upgrades here at this key.")
            end
        end
    end
    L:Finish(P.dungeonRows, P.dungeonItems)
    UI.RefreshStatusLine(page)
end

-------------------------------------------------------------------------------
-- Raid: a difficulty strip, then boss rows grouped by raid
-------------------------------------------------------------------------------
local Raid = { key = "raid", label = "Raid" }

function Raid.Build(page)
    local strip = UI.Strip(page, "Difficulty")
    local defs = {}
    for _, d in ipairs(ns.RAID_DIFFS) do defs[#defs + 1] = { d.key, d.name, "Bosses are judged at this difficulty." } end
    strip.Tabs = UI.TabStrip(strip, defs, 60, function(key) ns:SetRaidDifficulty(key) end)
    strip.Tabs:SetPoint("RIGHT", 0, 0)
    page.Strip = strip
    page.ColHead = UI.ColumnHeader(page, {
        { "boss", "Boss", nil, "Click a boss to see its drops. Click here to sort by kill order." },
        { "upgrades", "Drops", UI.COL_DROPS, "Spec-usable items that would upgrade a slot as a drop at the selected difficulty. Click to sort." },
        { "wanted", "Wanted", UI.COL_WANTED, "Items from your wanted list this boss drops; a purple star means a Voidcore target. Click to sort." },
    }, function(mode) ns.db.raidSort = mode end, STRIP_H)
    page.List, page.Content = UI.ListPanel(page, page.ColHead, 18)
    UI.StatusLine(page)
end

function Raid.Refresh(page)
    local sortMode = SelectSort(page, "raidSort", { boss = true, upgrades = true, wanted = true }, "boss")
    local diff = ns:GetRaidDifficulty()
    if page.Strip.Tabs.selectedTabID ~= diff then Style.SelectTab(page.Strip.Tabs, diff) end
    local groups = ns.raidResults or {}
    if ns.uiExpandedEncounterID then Freeze("raid:" .. ns.uiExpandedEncounterID, sortMode) else Freeze(nil) end
    local L = UI.Layout(page.Content)
    for _, group in ipairs(groups) do
        if #groups > 1 then
            local h = L:Add(P.raidHeaders, function() return UI.NewSectionRow(L.content) end, UI.SECTION_H)
            h.Text:SetText(group.raid.name)
        end
        local bosses = group.bosses
        if ns.uiExpandedEncounterID then
            bosses = KeepOrder("top:" .. group.raid.instanceID, bosses, function(r) return r.boss.encounterID end)
        end
        for _, r in ipairs(bosses) do
            if not Hidden(r) then
                local row = L:Add(P.raidRows, function()
                    return UI.NewTopRow(L.content, function(self)
                        ns.uiExpandedEncounterID = (ns.uiExpandedEncounterID ~= self.encounterID) and self.encounterID or nil
                        ns:RefreshWindow()
                    end, nil, function(self) ns:ShowDungeonTooltip(self) end)
                end, ROW_H + 1)
                row.encounterID = r.boss.encounterID
                local expanded = ns.uiExpandedEncounterID == row.encounterID
                FillSourceRow(row, L:Count(P.raidRows), r, r.boss.portrait or 134400, expanded, false)
                if r.scanned then
                    UI.SetRowCounts(row, ns.DropsHex(r) .. r.upgrades .. "|r", r.wanted, true, r.voidcore)
                else
                    UI.SetRowCounts(row, "|cff444444-|r", 0, true, 0)
                end
                if expanded then
                    local diffName = r.ctx.difficultyName or "this difficulty"
                    if r.scanned then
                        ListDrops(L, P.raidItems, false, Entries(KeepOrder("items", r.items, ItemKey), r.ctx), "No upgrades here on " .. diffName .. ".")
                    else
                        Note(L, P.raidItems, false, "No loot listed for " .. diffName .. ".")
                        L:Gap(4)
                    end
                end
            end
        end
    end
    if #groups == 0 then Note(L, P.raidItems, false, ns.loot and "No raids found in the journal for this season." or "Loot tables not scanned yet.") end
    L:Finish(P.raidRows, P.raidItems, P.raidHeaders)
    UI.RefreshStatusLine(page)
end

-------------------------------------------------------------------------------
-- Gear: a source strip (M+ / both / raid), then one row per slot or pair
-------------------------------------------------------------------------------
local Gear = { key = "gear", label = "Gear" }

function Gear.Build(page)
    local strip = UI.Strip(page, "Drops from")
    strip.Tabs = UI.TabStrip(strip, {
        { "mplus", "M+", "Dungeon drops at the selected key." },
        { "both", "Both", "Dungeon drops at the selected key and raid drops at the Raid tab's difficulty." },
        { "raid", "Raid", "Raid drops at the Raid tab's difficulty." },
    }, 50, function(key) ns.db.gearSource = key; ns:RefreshWindow() end)
    strip.Tabs:SetPoint("LEFT", strip.Label, "RIGHT", 8, 0)
    strip.Diff = Style.Text(strip, 10, 1, 1, 1, 0.53)
    strip.Diff:SetPoint("LEFT", strip.Tabs, "RIGHT", 8, 0)
    page.Strip = strip
    page.ColHead = UI.ColumnHeader(page, {
        { "slot", "Slot", nil, "Click a slot to compare every drop for it. Click here to sort by slot." },
        { "upgrades", "Drops", UI.COL_DROPS, "Upgrade drops available for the slot. Click to sort." },
        { "wanted", "Wanted", UI.COL_WANTED, "Wanted items for the slot. Click to sort." },
    }, function(mode) ns.db.gearSort = mode end, STRIP_H)
    page.List, page.Content = UI.ListPanel(page, page.ColHead, 18)
    page.Hint = UI.Line(page, 10, "LEFT", 1, 1, 1, 0.53)
    page.Hint:SetPoint("BOTTOMLEFT", 2, 2)
    page.Hint:SetPoint("BOTTOMRIGHT", -2, 2)
end

-- Drops for one slot from every source, best stat fit first. Excluded items
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
    return ns.ItemName(ea.item) < ns.ItemName(eb.item)
end

-- [rowSlotID] = { { eval, source, ctx }, ... } sorted, from what the Gear tab lists.
local function DropsBySlot()
    local buckets = {}
    for _, r in ipairs(ns:GearResults()) do
        for _, top in ipairs(r.scanned and r.items or {}) do
            for _, eval in ipairs(top.pieces or { top }) do
                if eval.slotID then
                    local slot = ns.PAIR_ROW[eval.slotID] or eval.slotID
                    buckets[slot] = buckets[slot] or {}
                    table.insert(buckets[slot], { eval = eval, source = r.sourceName, ctx = r.ctx })
                end
            end
        end
    end
    for _, list in pairs(buckets) do table.sort(list, CompareDrops) end
    return buckets
end

-- Weapons: a drop is compared against the weaker hand, so the other hand
-- may list nothing.
local TWIN = { [16] = 17, [17] = 16 }

function Gear.Refresh(page)
    local setText = ns:SetProgressText()
    page.Hint:SetText((setText and (setText .. ".  ") or "") .. "Star: want it.  Purple star: Voidcore it.  Right-click a slot: Auto / Want / Skip.")
    local sortMode = SelectSort(page, "gearSort", { slot = true, upgrades = true, wanted = true }, "slot")
    local source = ns.db.gearSource
    if page.Strip.Tabs.selectedTabID ~= source then Style.SelectTab(page.Strip.Tabs, source) end
    page.Strip.Diff:SetText(source ~= "mplus" and ns.RAID_DIFF_BY_KEY[ns:GetRaidDifficulty()].name or "")

    local summary = ns.slotSummary or ns:SlotSummary()
    local buckets = DropsBySlot()
    local order, index = {}, {}
    for i, s in ipairs(ns.SLOTS) do
        index[s.id] = i
        if not ns.PAIR_ROW[s.id] then order[#order + 1] = s end
    end
    if sortMode ~= "slot" then
        table.sort(order, function(a, b)
            local ea, eb = summary[a.id], summary[b.id]
            local va = sortMode == "wanted" and #ea.wanted or ea.count
            local vb = sortMode == "wanted" and #eb.wanted or eb.count
            if va ~= vb then return va > vb end
            return index[a.id] < index[b.id]
        end)
    end
    if ns.uiExpandedSlotID then
        Freeze("gear:" .. ns.uiExpandedSlotID, sortMode)
        order = KeepOrder("top", order, function(s) return s.id end)
    else
        Freeze(nil)
    end

    local L = UI.Layout(page.Content)
    local scanned = ns.loot ~= nil
    for _, s in ipairs(order) do
        local row = L:Add(P.gearRows, function()
            return UI.NewTopRow(L.content, function(self)
                ns.uiExpandedSlotID = (ns.uiExpandedSlotID ~= self.slotID) and self.slotID or nil
                ns:RefreshWindow()
            end, function(self)
                ns:CycleSlotState(self.slotID, ns.PAIR_OF[self.slotID])
            end, function(self) ns:ShowSlotTooltip(self) end)
        end, ROW_H + 1)
        row.slotID = s.id
        local icon = GetInventoryItemTexture("player", s.id)
        row.Icon:SetTexture(icon or s.emptyTexture)
        row.Icon:SetDesaturated(not icon)
        local state = ns:GetSlotState(s.id)
        local e = summary[s.id]
        if state == "skip" then
            row.Border:SetColorTexture(0.8, 0.2, 0.2, 1)
        elseif state == "want" then
            row.Border:SetColorTexture(0.35, 0.7, 1, 1)
        elseif e.count > 0 then
            local c = ns.UPGRADE_COLOR[e.best]
            row.Border:SetColorTexture(c[1], c[2], c[3], 1)
        else
            row.Border:SetColorTexture(0, 0, 0, 1)
        end
        local label = ns.PAIR_LABEL[s.id] or s.name or s.key
        if state == "skip" then label = "|cffff5555" .. label .. "|r  |cff888888skip|r"
        elseif state == "want" then label = "|cff66bbff" .. label .. "|r  |cff888888want all|r" end
        local worn = UI.EquippedShort(ns.gear[s.id])
        if ns.PAIR_OF[s.id] then worn = worn .. "  |cff666666·|r  " .. UI.EquippedShort(ns.gear[ns.PAIR_OF[s.id]]) end
        row.Name:SetText(label .. "  " .. worn)
        local expanded = ns.uiExpandedSlotID == s.id
        row.Arrow:SetRotation(expanded and 0 or math.rad(90))
        UI.SetRowCounts(row, HEX[e.count > 0 and e.best or NONE] .. e.count .. "|r", #e.wanted, scanned, #e.voidcore)
        UI.RowBackground(row, L:Count(P.gearRows), expanded, false)
        if expanded then
            local drops = KeepOrder("items", buckets[s.id] or {}, function(entry) return entry.eval.item.itemID .. "|" .. (entry.source or "") end)
            local twin = TWIN[s.id]
            local empty
            if not scanned then
                empty = "Loot tables not scanned yet."
            elseif twin and buckets[twin] and #buckets[twin] > 0 then
                local ts = ns.SLOT_BY_ID[twin]
                empty = string.format("Drops for this slot are compared against your weaker %s; see that row.", ts.name or ts.key)
            elseif state == "skip" then
                empty = "Slot skipped."
            else
                empty = "No drops for this slot."
            end
            ListDrops(L, P.gearItems, true, drops, empty)
        end
    end
    L:Finish(P.gearRows, P.gearItems)
end

-------------------------------------------------------------------------------
-- IO: rating and target, plan picker and key cap, then dungeon rows
-------------------------------------------------------------------------------
local IO = { key = "io", label = "IO", ownHeader = true }

local function ColorHex(color)
    if type(color) == "table" and color.r then return ns.HexColor(color.r or 1, color.g or 1, color.b or 1) end
    return "|cffffffff"
end

local function ScoreHex(score)
    local ok, c = pcall(C_ChallengeMode.GetDungeonScoreRarityColor, score or 0)
    return ok and ColorHex(c) or "|cffffffff"
end

local function LevelHex(level)
    local ok, c = pcall(C_ChallengeMode.GetKeystoneLevelRarityColor, level or 0)
    return ok and ColorHex(c) or "|cffffffff"
end

local function BestText(e)
    if not e.hasRun then return "|cff444444-|r" end
    if e.timed then return string.format("%s+%d|r", LevelHex(e.level), e.level) end
    return string.format("|cff888888+%d|r", e.level)
end

local function Stepper(parent, w, h, size, onStep)
    local plus = UI.TextButton(parent, "+", w, h, size)
    plus:SetScript("OnClick", function() onStep(1) end)
    local minus = UI.TextButton(parent, "-", w, h, size)
    minus:SetScript("OnClick", function() onStep(-1) end)
    return plus, minus
end

function IO.Build(page)
    local head = CreateFrame("Frame", nil, page)
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", -GUTTER, 0)
    head:SetHeight(UI.IO_HEADER_H)
    page.Head = head

    -- row 1: rating, target milestones, custom stepper, distance to go
    head.Rating = UI.Line(head, 14)
    head.Rating:SetPoint("TOPLEFT", 4, -3)
    head.Rating:SetWidth(58)
    local defs = {}
    for _, m in ipairs(ns:RatingMilestones()) do defs[#defs + 1] = { tostring(m), tostring(m), "Plan the runs that reach this rating." } end
    defs[#defs + 1] = { "custom", "Custom", "Any target, in steps of 50." }
    head.TargetTabs = UI.TabStrip(head, defs, 44, function(id)
        if id == "custom" then ns:StepRatingTarget(1) else ns:SetRatingTarget(tonumber(id)) end
    end)
    head.TargetTabs:SetPoint("TOPLEFT", 66, 0)
    head.CustomTab = head.TargetTabs.Tabs.custom
    head.TargetPlus, head.TargetMinus = Stepper(head, 18, 20, 12, function(d) ns:StepRatingTarget(d) end)
    head.TargetPlus:SetPoint("LEFT", head.TargetTabs, "RIGHT", 22, 0)
    head.TargetMinus:SetPoint("RIGHT", head.TargetPlus, "LEFT", -1, 0)
    for _, b in ipairs({ head.TargetPlus, head.TargetMinus }) do UI.Tip(b, "ANCHOR_BOTTOM", "Target rating", "Steps of 50.") end
    head.Need = UI.Line(head, 11, "RIGHT", 1, 1, 1, 0.6)
    head.Need:SetPoint("TOPRIGHT", 0, -4)
    head.Need:SetPoint("LEFT", head.TargetPlus, "RIGHT", 4, 0)

    -- row 2: plan picker, key cap
    head.RunsLabel = Style.Text(head, 11, 1, 1, 1, 0.53)
    head.RunsLabel:SetPoint("TOPLEFT", 4, -30)
    head.RunsLabel:SetText("Runs")
    head.RunsTabs = UI.RunsStrip(head, 8, function(plan) ns:SetRatingRuns(plan.count) end)
    head.RunsTabs:SetPoint("LEFT", head.RunsLabel, "RIGHT", 8, 0)
    head.KeyPlus, head.KeyMinus = Stepper(head, 20, 20, 12, function(d) ns:StepRatingMaxKey(d) end)
    head.KeyPlus:SetPoint("TOPRIGHT", 0, -26)
    local kBox = CreateFrame("Button", nil, head)
    kBox:SetSize(34, 20)
    kBox:SetPoint("RIGHT", head.KeyPlus, "LEFT", -1, 0)
    Style.Panel(kBox, { inset = true })
    kBox:RegisterForClicks("RightButtonUp")
    kBox:SetScript("OnClick", function() ns:SetRatingMaxKey(nil) end)
    head.KeyText = Style.Text(kBox, 11)
    head.KeyText:SetPoint("CENTER", 0, 0)
    head.KeyMinus:SetPoint("RIGHT", kBox, "LEFT", -1, 0)
    local kLabel = Style.Text(head, 11, 1, 1, 1, 0.53)
    kLabel:SetPoint("RIGHT", head.KeyMinus, "LEFT", -6, 0)
    kLabel:SetText("Max key")
    for _, b in ipairs({ head.KeyPlus, head.KeyMinus, kBox }) do
        UI.Tip(b, "ANCHOR_BOTTOM", "Max key", "Plans use no key above this. Grey: automatic, your highest timed key + 2. Right-click the box: back to automatic.")
    end

    -- order strip: the planned runs by rating gained or by gear drops
    local strip = UI.Strip(page)
    strip:SetPoint("TOPLEFT", 0, -UI.IO_HEADER_H)
    strip:SetPoint("TOPRIGHT", -GUTTER, -UI.IO_HEADER_H)
    strip.Order = UI.Dropdown(strip, 150, 20, function()
        local order = ns:RatingOrder()
        return {
            { text = "Rating gained", checked = order == "rating", onClick = function() ns:SetRatingOrder("rating") end },
            { text = "Gear drops", checked = order == "gear", onClick = function() ns:SetRatingOrder("gear") end },
        }
    end)
    strip.Order:SetPoint("LEFT", 0, 0)
    UI.Tip(strip.Order, "ANCHOR_BOTTOM", "Order", "Rating gained: highest key first. Gear drops: the dungeons with the most usable drops at the planned key first.")
    strip.Note = UI.Line(strip, 10, "LEFT", 1, 1, 1, 0.53)
    strip.Note:SetPoint("LEFT", strip.Order, "RIGHT", 8, 0)
    strip.Note:SetPoint("RIGHT", 0, 0)
    page.Strip = strip

    page.ColHead = UI.ColumnHeader(page, {
        { "plan", "Dungeon", nil, "Click a dungeon for its key ladder. Right-click to avoid it. Click here to sort by the plan." },
        { "best", "Best", UI.COL_BEST, "Your best run this season: coloured when timed, grey when over time. Click to sort." },
        { "run", "Run", UI.COL_RUN, "The key to time in the selected plan." },
        { "gain", "Gain", UI.COL_GAIN, "Rating gained by timing that key. Click to sort." },
    }, function(mode) ns.db.ioSort = mode end, UI.IO_HEADER_H + STRIP_H)
    page.List, page.Content = UI.ListPanel(page, page.ColHead, 18)
    UI.StatusLine(page)
end

local function IOStatusText(info, plan)
    if not info.ready then return "Waiting for rating data..." end
    local hint = "Right-click a dungeon to avoid it."
    if info.reached then return "Target reached  ·  " .. hint end
    if info.partial and plan then
        return string.format("+%d everywhere reaches %d  ·  %s", plan.maxLevel, ns:Round(plan.reach or 0), hint)
    end
    if plan then
        return string.format("+%d to go  ·  %d run%s for +%d = %s%d|r  ·  %s", ns:Round(info.need or 0),
            plan.count, plan.count == 1 and "" or "s", ns:Round(plan.total),
            ScoreHex((info.overall or 0) + plan.total), ns:Round((info.overall or 0) + plan.total), hint)
    end
    return string.format("+%d to go  ·  %s", ns:Round(info.need or 0), hint)
end

-- Plan order: planned runs first, highest key first, then the rest by
-- score; by gear, the most usable drops first on both sides.
local function CompareEntries(sortMode, byGear)
    return function(a, b)
        if a.avoided ~= b.avoided then return b.avoided end
        if sortMode == "name" then return a.d.name < b.d.name end
        if sortMode == "best" then
            if a.e.score ~= b.e.score then return a.e.score < b.e.score end
            return a.d.name < b.d.name
        end
        if (a.run ~= nil) ~= (b.run ~= nil) then return a.run ~= nil end
        if sortMode == "gain" then
            local ga, gb = a.run and a.run.gain or a.floorGain, b.run and b.run.gain or b.floorGain
            if ga ~= gb then return ga > gb end
            return a.d.name < b.d.name
        end
        if byGear then
            local ua, ub = a.gear and a.gear.upgrades or -1, b.gear and b.gear.upgrades or -1
            if ua ~= ub then return ua > ub end
            local wa, wb = a.gear and a.gear.wanted or 0, b.gear and b.gear.wanted or 0
            if wa ~= wb then return wa > wb end
        end
        if a.run and b.run then
            if a.run.level ~= b.run.level then return a.run.level > b.run.level end
            if a.run.gain ~= b.run.gain then return a.run.gain > b.run.gain end
        elseif a.e.score ~= b.e.score then
            return a.e.score < b.e.score
        end
        return a.d.name < b.d.name
    end
end

function IO.Refresh(page)
    local head = page.Head
    local plans, info = ns:RatingPlans()
    local plan = ns:SelectedRatingPlan()
    local accent = Style.AccentHex()

    head.Rating:SetText(info.ready and (ScoreHex(info.overall) .. ns:Round(info.overall) .. "|r") or "|cff888888...|r")
    local target, _, tabID = ns:RatingTarget()
    if head.TargetTabs.selectedTabID ~= tabID then Style.SelectTab(head.TargetTabs, tabID) end
    head.CustomTab.Text:SetText(tabID == "custom" and tostring(target) or "Custom")
    head.TargetPlus:SetShown(tabID == "custom")
    head.TargetMinus:SetShown(tabID == "custom")
    head.Need:SetText(not info.ready and "" or info.reached and "|cff88ff88reached|r" or string.format("+%d to go", ns:Round(info.need)))
    head.RunsTabs:SetPlans(plans, plan)
    head.RunsLabel:SetAlpha(#plans > 0 and 1 or 0.4)
    local cap, capAuto = ns:RatingMaxKey()
    head.KeyText:SetText(string.format("%s+%d|r", capAuto and "|cff888888" or "|cffffffff", cap))

    local sortMode = SelectSort(page, "ioSort", { plan = true, best = true, gain = true, name = true }, "plan")
    local byGear = ns:RatingOrder() == "gear"
    page.Strip.Order.Text:SetText("|cffaaaaaaOrder:|r " .. (byGear and "Gear drops" or "Rating gained"))
    page.Strip.Note:SetText(byGear and "Usable drops at the planned key, next to the name." or "")

    -- by gear, drops are judged at the planned key, else the first key that
    -- gains, else the cap (the tooltip fetches them otherwise)
    local entries = {}
    for _, d in ipairs(ns.dungeons) do
        local mapID = d.challengeMapID
        local e = ns:DungeonRating(mapID)
        local run = plan and plan.byMap[mapID] or nil
        local gearLevel = run and run.level or e.floor or cap
        entries[#entries + 1] = {
            d = d, mapID = mapID, e = e, run = run, avoided = ns:IsDungeonAvoided(mapID),
            floorGain = e.floor and ns:RatingGain(mapID, e.floor) or 0,
            gear = byGear and ns:DropsAtKey(d, gearLevel) or nil, gearLevel = gearLevel,
        }
    end
    table.sort(entries, CompareEntries(sortMode, byGear))

    local L = UI.Layout(page.Content)
    local _, maxL = ns:RatingLevelRange()
    for _, entry in ipairs(entries) do
        local row = L:Add(P.ioRows, function()
            return UI.NewRow(L.content, { { "Gain", UI.COL_GAIN }, { "Run", UI.COL_RUN }, { "Best", UI.COL_BEST } }, function(self)
                ns.uiExpandedRatingMapID = (ns.uiExpandedRatingMapID ~= self.mapID) and self.mapID or nil
                ns:RefreshWindow()
            end, function(self)
                ns:ToggleAvoidDungeon(self.mapID)
            end, function(self) ns:ShowRatingTooltip(self) end)
        end, ROW_H + 1)
        local d, e, run = entry.d, entry.e, entry.run
        row.mapID, row.dungeon, row.entry, row.run, row.avoided, row.hasPlan = entry.mapID, d, e, run, entry.avoided, plan ~= nil
        row.gear, row.gearLevel = entry.gear, entry.gearLevel
        row.Icon:SetTexture(DungeonIcon(d))
        local dim = entry.avoided or (plan ~= nil and not run)
        row.Icon:SetDesaturated(dim)
        row.Name:SetAlpha(dim and 0.45 or 1)
        row.Border:SetColorTexture(entry.avoided and 1 or 0, entry.avoided and 0.3 or 0, entry.avoided and 0.3 or 0, 1)
        local name = d.name .. (entry.avoided and " |cff888888avoid|r" or "")
        if byGear then
            local gear = entry.gear
            name = name .. (gear and gear.scanned and string.format("  %s%d|r", ns.DropsHex(gear), gear.upgrades) or "  |cff444444...|r")
        end
        row.Name:SetText(name)
        local expanded = ns.uiExpandedRatingMapID == entry.mapID
        row.Arrow:SetRotation(expanded and 0 or math.rad(90))
        row.Best:SetText(info.ready and BestText(e) or "|cff888888...|r")
        row.Run:SetText(run and string.format("|cffffffff+%d|r", run.level) or "|cff444444-|r")
        row.Gain:SetText(run and string.format("%s+%d|r", accent, ns:Round(run.gain)) or "")
        UI.RowBackground(row, L:Count(P.ioRows), expanded, ns.highlightMapID == entry.mapID)
        if expanded then
            local function Ladder() return UI.NewLadderRow(L.content) end
            local first = e.floor
            if first and info.ready then
                local last = math.min(math.max(first + UI.LADDER_ROWS - 1, run and (run.level + 1) or 0), maxL)
                for level = first, last do
                    local it = L:Add(P.ioLadder, Ladder, ITEM_H)
                    local score = ns:TimedScore(level)
                    it.Level:SetText(string.format("%s+%d|r  |cff888888timed|r", LevelHex(level), level))
                    it.Score:SetText(string.format("|cffffffff%d|r", ns:Round(score)))
                    it.Gain:SetText(string.format("%s+%d|r", accent, ns:Round(score - e.score)))
                    if run and run.level == level then
                        local r, g, b = Style.Accent()
                        it.Bg:SetColorTexture(r, g, b, 0.15)
                    else
                        it.Bg:SetColorTexture(1, 1, 1, 0)
                    end
                end
            else
                local it = L:Add(P.ioLadder, Ladder, ITEM_H)
                it.Level:SetText(info.ready and "|cff888888Nothing left to gain here.|r" or "|cff888888Waiting for rating data...|r")
                it.Score:SetText("")
                it.Gain:SetText("")
                it.Bg:SetColorTexture(1, 1, 1, 0)
            end
            L:Gap(4)
        end
    end
    L:Finish(P.ioRows, P.ioLadder)
    page.Status:SetText(IOStatusText(info, plan))
    page.Progress:Hide()
end

-------------------------------------------------------------------------------
-- Voidcore: where a Nebulous Voidcore is best spent
-------------------------------------------------------------------------------
local Voidcore = { key = "voidcore", label = "Voidcore" }

function Voidcore.Build(page)
    local strip = UI.Strip(page)
    local reread = UI.TextButton(strip, "Re-read", 56, 20, 10)
    reread:SetPoint("RIGHT", 0, 0)
    reread:SetScript("OnClick", function() ns:ClearVoidcorePools(); ns:RefreshWindow() end)
    UI.Tip(reread, "ANCHOR_BOTTOM", "Re-read the pools", "Reads every Voidcache tooltip again. Pools are re-read by themselves after a roll and when your loot spec changes.")
    strip.Text = UI.Line(strip, 11, "LEFT", 1, 1, 1, 0.53)
    strip.Text:SetPoint("LEFT", 4, 0)
    strip.Text:SetPoint("RIGHT", reread, "LEFT", -6, 0)
    page.Strip = strip
    page.ColHead = UI.ColumnHeader(page, {
        { "best", "Source", nil, "Dungeons at the selected key, bosses at the Raid tab's difficulty. Click a row for its pool. Click here to sort by the best place to roll." },
        { "pool", "Ideal", UI.COL_POOL, "Ideal rolls over usable ones. Ideal: an upgrade whose stats fit too (a 75% match, or better than the piece it replaces; with a weight profile, a weighted gain). Click to sort." },
        { "chance", "Chance", UI.COL_CHANCE, "The share of the pool that would be an upgrade. Click to sort." },
        { "gain", "Gain", UI.COL_EGAIN, "Item levels a roll here gains on average, slot-weighted; Voidcore targets and wanted items count extra. The tab sorts by this." },
        { "targets", "Targets", UI.COL_TARGET, "Voidcore targets still in the pool. Click to sort." },
    }, function(mode) ns.db.rollSort = mode end, STRIP_H)
    page.List, page.Content = UI.ListPanel(page, page.ColHead, 18)
    UI.StatusLine(page)
end

local function RollOrder(a, b)
    local ca, cb = a.voidcore and a.voidcore.class or -1, b.voidcore and b.voidcore.class or -1
    if ca ~= cb then return ca > cb end
    return ns.ItemName(a.token or a.item) < ns.ItemName(b.token or b.item)
end

function Voidcore.Refresh(page)
    local sortMode = SelectSort(page, "rollSort", { best = true, pool = true, chance = true, targets = true, gain = true }, "best")
    local lootSpec, evalSpec = ns:GetLootSpecID(), ns:GetEvalSpecID()
    local cores = ns:VoidcoreCount()
    local setText = ns:SetProgressText()
    page.Strip.Text:SetText(string.format("Pools for %s%s%s", ns:SpecName(lootSpec) or "your loot spec",
        cores and string.format("  ·  %d Voidcore%s", cores, cores == 1 and "" or "s") or "",
        setText and ("  ·  " .. setText) or ""))

    local sources = ns:VoidcoreSources(sortMode)
    local L = UI.Layout(page.Content)
    for _, s in ipairs(sources) do
        local row = L:Add(P.rollRows, function()
            return UI.NewRow(L.content, { { "Targets", UI.COL_TARGET }, { "EGain", UI.COL_EGAIN }, { "Chance", UI.COL_CHANCE }, { "Pool", UI.COL_POOL } }, function(self)
                ns.uiExpandedRollKey = (ns.uiExpandedRollKey ~= self.key) and self.key or nil
                ns:RefreshWindow()
            end, nil, function(self) ns:ShowRollTooltip(self) end)
        end, ROW_H + 1)
        row.key = s.cacheID or s.name
        row.source = s
        row.Icon:SetTexture(s.kind == "dungeon" and DungeonIcon(s.dungeon) or (s.boss and s.boss.portrait) or 134400)
        local dim = s.ready and s.usable == 0
        row.Icon:SetDesaturated(dim)
        row.Border:SetColorTexture(0, 0, 0, 1)
        row.Name:SetText(s.name .. (s.kind == "dungeon" and string.format("  |cff888888+%d|r", s.key or 0) or ""))
        row.Name:SetAlpha(dim and 0.45 or 1)
        local expanded = ns.uiExpandedRollKey == row.key
        row.Arrow:SetRotation(expanded and 0 or math.rad(90))
        if not s.ready then
            row.Pool:SetText("|cff888888...|r"); row.Chance:SetText(""); row.EGain:SetText(""); row.Targets:SetText("")
        else
            row.Pool:SetText(string.format("%s%d|r|cff888888/%d|r", HEX[s.ideal > 0 and TRACK or (s.usable > 0 and ILVL or NONE)], s.ideal, s.usable))
            row.Chance:SetText(s.count > 0 and string.format("|cffffffff%d%%|r", math.floor(s.chance * 100 + 0.5)) or "|cff444444-|r")
            row.EGain:SetText(s.ev > 0 and string.format("%s+%.1f|r", HEX[TRACK], s.ev) or "|cff444444-|r")
            row.Targets:SetText(s.targets > 0 and (ns.VC_HEX .. s.targets .. "|r") or "|cff444444-|r")
        end
        UI.RowBackground(row, L:Count(P.rollRows), expanded, false)
        if expanded then
            if s.missing then
                Note(L, P.rollItems, false, "No Voidcache known for this source.")
            elseif not s.ready then
                Note(L, P.rollItems, false, "Loot not scanned yet.")
            elseif s.total == 0 then
                Note(L, P.rollItems, false, "Nothing here can be rolled.")
            else
                -- the pool with each roll's verdict, then the rolled items dimmed
                for _, part in ipairs({ { list = s.items }, { list = s.rolledItems, rolled = true } }) do
                    local sorted = { unpack(part.list) }
                    table.sort(sorted, RollOrder)
                    for _, eval in ipairs(sorted) do
                        local it = L:Add(P.rollItems, function() return UI.NewItemRow(L.content, false) end, ITEM_H)
                        it.dungeonName, it.ctx, it.roll, it.source = nil, s.result.ctx, true, s
                        UI.FillItemRow(it, eval, nil, eval.voidcore)
                        if part.rolled then
                            it.Name:SetAlpha(0.35)
                            it.Icon:SetDesaturated(true)
                            it.Gain:SetText("|cff888888rolled|r")
                        end
                    end
                end
            end
            L:Gap(4)
        end
    end
    if #sources == 0 then Note(L, P.rollItems, false, ns.loot and "Nothing to roll on yet." or "Loot tables not scanned yet.") end
    L:Finish(P.rollRows, P.rollItems)
    if lootSpec ~= evalSpec then
        page.Status:SetText(string.format("Pools follow your loot spec; the window evaluates %s.", ns:SpecName(evalSpec) or "another spec"))
    else
        page.Status:SetText("Rolls are recorded as they happen; right-click an item to mark one by hand.")
    end
    page.Progress:Hide()
end

-------------------------------------------------------------------------------
-- Status line under the loot tabs
-------------------------------------------------------------------------------
local function StatusText()
    local status
    if ns.scanProgress then
        status = string.format("Scanning %d/%d: %s", ns.scanProgress.index, ns.scanProgress.total, ns.scanProgress.name or "")
    elseif not ns.dungeonsBuilt then
        status = "Waiting for season data..."
    elseif ns.loot and ns.loot.time then
        local age = time() - ns.loot.time
        local ageText = age < 3600 and string.format("%dm", age / 60) or age < 86400 and string.format("%dh", age / 3600) or string.format("%dd", age / 86400)
        status = string.format("Loot tables scanned %s ago", ageText)
    else
        status = "Loot tables not scanned yet"
    end
    if ns.trackOffsetApplied and ns.trackOffsetApplied ~= 0 then
        status = status .. string.format("  |cffaaaaaa(tracks %+d)|r", ns.trackOffsetApplied)
    end
    return status
end

function UI.RefreshStatusLine(page)
    page.Status:SetText(StatusText())
    local p = ns.scanProgress
    if p and p.total and p.total > 0 then
        page.Progress:SetValue(p.index / p.total)
        page.Progress:Show()
    else
        page.Progress:Hide()
    end
end

-- In tab-row order. ownHeader: the page has no loot toolbar above it.
UI.Tabs = { Dungeons, Raid, Gear, IO, Voidcore }
