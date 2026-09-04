-- Slot Filler: Premade Groups listings (a line under each group and lines in
-- its tooltip) and Mythic Keystone tooltips.
local _, ns = ...

local hookedButtons = {}

-- The dungeon a search result is for, respecting 12.x secret values.
local function DungeonForResult(resultID)
    if not ns.Num(resultID) then return nil end
    local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
    info = ok and ns.Tbl(info)
    local ids = info and ns.Tbl(info.activityIDs)
    return ids and ns:DungeonForActivity(ids[1]) or nil
end
ns.DungeonForResult = DungeonForResult

-------------------------------------------------------------------------------
-- The line under a listing. (A listing's title, "+13 ...", is a protected
-- string no addon can read, so nothing about rating is shown here; keystone
-- tooltips, which know their level, carry it.)
-------------------------------------------------------------------------------
local function EnsureBadge(button)
    if button.SlotFillerBadge then return button.SlotFillerBadge end
    local badge = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.Style.Font(badge)
    -- the third line of an entry, after the Relaxed / Competitive tag (the
    -- activity line is too crowded: the name runs under the role icons)
    if button.Playstyle then
        badge:SetPoint("LEFT", button.Playstyle, "RIGHT", 6, 0)
        badge:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    elseif button.ActivityName then
        badge:SetPoint("TOPLEFT", button.ActivityName, "BOTTOMLEFT", 0, -1)
        badge:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    elseif button.DataDisplay then
        badge:SetPoint("RIGHT", button.DataDisplay, "LEFT", -2, 0)
    else
        badge:SetPoint("RIGHT", button, "RIGHT", -100, 0)
    end
    badge:SetJustifyH("LEFT")
    badge:SetWordWrap(false)
    badge:SetMaxLines(1)
    button.SlotFillerBadge = badge
    return badge
end

-- Inline icons for the badge: the wanted star and the Voidcore currency.
local starMarkup, coreMarkup
local function Icons()
    if starMarkup == nil then
        local atlas = ns.Style.FindAtlas({ "auctionhouse-icon-favorite", "PetJournal-FavoritesIcon" })
        starMarkup = atlas and string.format("|A:%s:0:0|a", atlas) or false
    end
    if coreMarkup == nil then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, ns:VoidcoreCurrencyID())
        local icon = ok and ns.Tbl(info) and ns.Num(info.iconFileID)
        coreMarkup = icon and string.format("|T%d:12:12|t", icon) or false
    end
    return starMarkup, coreMarkup
end

-- "2 upgrades · [star]1 · [core]1", each part in its own colour.
local function UpdateButton(button)
    if not ns.db then return end
    local parts = {}
    local d = ns.db.lfgBadges and DungeonForResult(button.resultID)
    local r = d and ns:ResultForDungeon(d)
    if r and r.scanned then
        local star, core = Icons()
        if r.upgrades > 0 then
            parts[#parts + 1] = string.format("%s%d upgrade%s|r", ns.DropsHex(r), r.upgrades, r.upgrades == 1 and "" or "s")
        else
            parts[#parts + 1] = "|cff666666no upgrades|r"
        end
        if r.wanted > 0 then parts[#parts + 1] = string.format("%s%s%d|r", ns.Style.AccentHex(), star or "wanted ", r.wanted) end
        if r.voidcore > 0 then parts[#parts + 1] = string.format("%s%s%d|r", ns.VC_HEX, core or "Voidcore ", r.voidcore) end
    end
    if #parts > 0 then
        EnsureBadge(button):SetText(table.concat(parts, "|cff666666  ·  |r"))
    elseif button.SlotFillerBadge then
        button.SlotFillerBadge:SetText("")
    end
end

local function HookButton(button)
    if hookedButtons[button] then return end
    hookedButtons[button] = true
    button:HookScript("OnEnter", function(self)
        local d = DungeonForResult(self.resultID)
        ns:SetHighlightDungeon(d and d.challengeMapID or nil)
    end)
    button:HookScript("OnLeave", function() ns:SetHighlightDungeon(nil) end)
end

-- Repaints the listings on screen (after an evaluation or a setting change).
function ns:RefreshLFGBadges()
    local scrollBox = LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.ScrollBox
    if not scrollBox or not scrollBox:IsVisible() then return end
    for _, button in ipairs(scrollBox:GetFrames() or {}) do
        HookButton(button)
        UpdateButton(button)
    end
end

-------------------------------------------------------------------------------
-- Tooltip lines shared by group listings and keystones: the upgrade count
-- for the dungeon at `key`, the wanted items and the Voidcore targets there.
-------------------------------------------------------------------------------
local function Names(evals)
    local names = {}
    for _, eval in ipairs(evals) do names[#names + 1] = ns.ItemName(eval.item) end
    return table.concat(names, ", ")
end

local function AddDungeonLines(tooltip, r, key)
    tooltip:AddLine(" ")
    if r.upgrades > 0 then
        local slots = {}
        for slotID in pairs(r.slots) do slots[#slots + 1] = ns.SLOT_BY_ID[slotID].short end
        table.sort(slots)
        tooltip:AddLine(string.format("Slot Filler: %s%d upgrade drop(s)|r at +%d (%s)", ns.DropsHex(r), r.upgrades, key, table.concat(slots, ", ")), 1, 1, 1, true)
    else
        tooltip:AddLine(string.format("Slot Filler: no upgrade drops at +%d", key), 0.6, 0.6, 0.6)
    end
    if r.wanted > 0 then tooltip:AddLine(string.format("%sWanted here:|r %s", ns.Style.AccentHex(), Names(r.wantedItems)), 1, 1, 1, true) end
    if r.voidcore > 0 then tooltip:AddLine(string.format("%sVoidcore target here:|r %s", ns.VC_HEX, Names(r.voidcoreItems)), 1, 1, 1, true) end
end

local function OnSearchEntryTooltip(tooltip, resultID)
    if not ns.db or not ns.db.lfgTooltip then return end
    local r = ns:ResultForDungeon(DungeonForResult(resultID))
    if r and r.scanned then
        AddDungeonLines(tooltip, r, ns.db.targetKey)
        tooltip:Show()
    end
end

-------------------------------------------------------------------------------
-- Mythic Keystone tooltips: the keystone in your bags and keystone links in
-- chat. Evaluated at that key's own level, not the window's selected key.
-------------------------------------------------------------------------------
local KEYSTONE_ITEM = 180653

function ns.KeystoneFromLink(link)
    if type(link) ~= "string" then return nil end
    local mapID, level = link:match("|Hkeystone:%d+:(%d+):(%d+)")
    if mapID then return tonumber(mapID), tonumber(level) end
    return nil
end

function ns:AddKeystoneTooltip(tooltip, mapID, level)
    local d = self.dungeonByMapID[mapID]
    if not d then return end
    local shown = false
    if self.db.keystoneTooltip then
        local r = self:EvaluateDungeonAt(d, level)
        if r.scanned then
            AddDungeonLines(tooltip, r, level or self.db.targetKey)
        else
            tooltip:AddLine(" ")
            tooltip:AddLine("Slot Filler: loot table not scanned yet", 0.6, 0.6, 0.6)
        end
        shown = true
    end
    -- the rating this key would give if timed, against the dungeon's best
    if self.db.ioBadge and level and self:RatingsReady() then
        local e = self:DungeonRating(mapID)
        local score = self:TimedScore(level)
        local gain = math.max(0, score - e.score)
        if not shown then tooltip:AddLine(" ") end
        if gain > 0 then
            tooltip:AddLine(string.format("Rating: %d -> %d (+%d) if timed", self:Round(e.score), self:Round(score), self:Round(gain)), 1, 1, 1)
        else
            tooltip:AddLine(string.format("Rating: no gain at +%d (best %d)", level, self:Round(e.score)), 0.6, 0.6, 0.6)
        end
        shown = true
    end
    if shown then tooltip:Show() end
end

local function OnItemTooltip(tooltip, data)
    if not ns.db or not (ns.db.keystoneTooltip or ns.db.ioBadge) then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local link = data and data.hyperlink
    local ok, _, displayed = pcall(TooltipUtil.GetDisplayedItem, tooltip)
    if ok and type(displayed) == "string" then link = displayed end
    if ns.issecret(link) then return end
    local mapID, level = ns.KeystoneFromLink(link)
    -- the keystone item without a keystone link: it can only be ours
    if not mapID and data and ns.Num(data.id) == KEYSTONE_ITEM then
        mapID, level = C_MythicPlus.GetOwnedKeystoneChallengeMapID(), C_MythicPlus.GetOwnedKeystoneLevel()
    end
    if not ns.Num(mapID) or (level ~= nil and not ns.Num(level)) then return end
    ns:AddKeystoneTooltip(tooltip, mapID, level)
end

-------------------------------------------------------------------------------
-- /sf lfg: what the client exposes for the listings on screen
-------------------------------------------------------------------------------
local function Quoted(v)
    if ns.issecret(v) then return "secret" end
    if type(v) == "string" then return '"' .. v .. '"' end
    return tostring(v)
end

function ns:PrintLFGDiagnostics()
    self:Print("Group listings")
    local n = 0
    for button in pairs(hookedButtons) do
        if button:IsShown() and button.resultID then
            n = n + 1
            local id = button.resultID
            local okInfo, info = pcall(C_LFGList.GetSearchResultInfo, id)
            local title = "no info"
            if okInfo and type(info) == "table" then title = ns.issecret(info) and "secret info" or Quoted(info.name) end
            local okText, text = pcall(function() return button.Name and button.Name:GetText() end)
            local d = DungeonForResult(id)
            local badge = button.SlotFillerBadge and button.SlotFillerBadge:GetText() or ""
            print(string.format("  result %s: %s | title from result: %s | entry name: %s | badge: %s",
                tostring(id), d and d.name or "no dungeon", title, okText and Quoted(text) or "error", (badge:gsub("|", "||"))))
        end
    end
    if n == 0 then print("  no listings on screen (open Premade Groups and search first)") end
end

-------------------------------------------------------------------------------
-- Hooks
-------------------------------------------------------------------------------
ns:On("LOGIN", function()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", OnSearchEntryTooltip)
    -- every search entry refresh goes through this
    hooksecurefunc("LFGListSearchEntry_Update", function(button)
        if not button or not button.resultID then return end
        HookButton(button)
        UpdateButton(button)
    end)
end)

ns:On("RESULTS_UPDATED", function() ns:RefreshLFGBadges() end)
ns:On("SETTINGS_CHANGED", function() ns:RefreshLFGBadges() end)
