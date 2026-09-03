-- Slot Filler: badges and tooltip lines on Premade Groups search results.
local _, ns = ...

local hookedButtons = {}
local scrollHooked = false

local NONE, ILVL, TRACK = ns.UPGRADE_NONE, ns.UPGRADE_ILVL, ns.UPGRADE_TRACK

local function HexFor(r)
    local class = NONE
    if r and r.upgrades > 0 then class = (r.trackUpgrades > 0) and TRACK or ILVL end
    local c = ns.UPGRADE_COLOR[class]
    return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Resolve the dungeon for a search result, respecting 12.x secret values.
local function DungeonForResult(resultID)
    if not resultID or ns.issecret(resultID) then return nil end
    local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
    if not ok or type(info) ~= "table" or ns.issecret(info) then return nil end
    local activityID = info.activityID
    if type(activityID) ~= "number" and type(info.activityIDs) == "table" and not ns.issecret(info.activityIDs) then
        activityID = info.activityIDs[1]
    end
    if type(activityID) ~= "number" or ns.issecret(activityID) then return nil end
    return ns:DungeonForActivity(activityID)
end
ns.DungeonForResult = DungeonForResult

-- A listing's title ("+13 ...") is a protected string: the screen can
-- draw it, no addon can read it. So nothing about rating is shown on a
-- listing; keystone tooltips, which know their level, carry it.

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
    if badge.SetMaxLines then badge:SetMaxLines(1) end
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
        coreMarkup = false
        local id = ns:VoidcoreCurrencyID()
        if id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
            local icon = ok and type(info) == "table" and info.iconFileID
            if type(icon) == "number" and not ns.issecret(icon) then coreMarkup = string.format("|T%d:12:12|t", icon) end
        end
    end
    return starMarkup, coreMarkup
end

local function UpdateButton(button)
    if not ns.db then return end
    local d = DungeonForResult(button.resultID)
    -- "2 upgrades · [star]1 · [core]1", each part in its own colour, on
    -- the entry's third line, clipped at its edge
    local parts = {}
    if ns.db.lfgBadges then
        local r = d and ns:ResultForDungeon(d)
        if r and r.scanned then
            local star, core = Icons()
            if r.upgrades > 0 then
                parts[#parts + 1] = string.format("%s%d upgrade%s|r", HexFor(r), r.upgrades, r.upgrades == 1 and "" or "s")
            else
                parts[#parts + 1] = "|cff666666no upgrades|r"
            end
            if r.wanted and r.wanted > 0 then
                parts[#parts + 1] = string.format("%s%s%d|r", ns.Style.AccentHex(), star or "wanted ", r.wanted)
            end
            if r.voidcore and r.voidcore > 0 then
                parts[#parts + 1] = string.format("%s%s%d|r", ns.VC_HEX, core or "Voidcore ", r.voidcore)
            end
        end
    end
    local text = #parts > 0 and table.concat(parts, "|cff666666  ·  |r") or nil
    if text then
        EnsureBadge(button):SetText(text)
    elseif button.SlotFillerBadge then
        button.SlotFillerBadge:SetText("")
    end
end

local function OnEnter(button)
    local d = DungeonForResult(button.resultID)
    ns:SetHighlightDungeon(d and d.challengeMapID or nil)
end

local function OnLeave()
    ns:SetHighlightDungeon(nil)
end

local function HookButtons(frames)
    for _, button in ipairs(frames) do
        if not hookedButtons[button] then
            hookedButtons[button] = true
            button:HookScript("OnEnter", OnEnter)
            button:HookScript("OnLeave", OnLeave)
        end
        UpdateButton(button)
    end
end

function ns:RefreshLFGBadges()
    local panel = LFGListFrame and LFGListFrame.SearchPanel
    local scrollBox = panel and panel.ScrollBox
    if not scrollBox or not scrollBox:IsVisible() then return end
    if scrollBox.GetFrames then
        local frames = scrollBox:GetFrames()
        if frames then HookButtons(frames) end
    end
end

local function HookScrollBox()
    if scrollHooked then return end
    local panel = LFGListFrame and LFGListFrame.SearchPanel
    local scrollBox = panel and panel.ScrollBox
    if not scrollBox or not scrollBox.RegisterCallback or not ScrollBoxListMixin then return end
    scrollHooked = true
    scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, function()
        ns:RefreshLFGBadges()
    end, ns)
    ns:RefreshLFGBadges()
end

-- Tooltip lines shared by group listings and keystones: upgrade count for the
-- dungeon at `key`, the wanted items and the Voidcore targets that drop there.
local function AddDungeonLines(tooltip, r, key, ctx)
    tooltip:AddLine(" ")
    if r.upgrades > 0 then
        local slots = {}
        for slotID in pairs(r.slots) do
            local s = ns.SLOT_BY_ID[slotID]
            table.insert(slots, ns.SLOT_SHORT[slotID] or (s and s.key) or tostring(slotID))
        end
        table.sort(slots)
        tooltip:AddLine(string.format("Slot Filler: %s%d upgrade drop(s)|r at +%d (%s)", HexFor(r), r.upgrades, key, table.concat(slots, ", ")), 1, 1, 1, true)
    else
        tooltip:AddLine(string.format("Slot Filler: no upgrade drops at +%d", key), 0.6, 0.6, 0.6)
    end
    if r.wanted and r.wanted > 0 then
        local names = {}
        for _, eval in ipairs(r.wantedItems or {}) do
            names[#names + 1] = eval.item.link and eval.item.link:match("%[(.-)%]") or eval.item.name or "?"
        end
        tooltip:AddLine(string.format("%sWanted here:|r %s", ns.Style.AccentHex(), table.concat(names, ", ")), 1, 1, 1, true)
    end
    if r.voidcore and r.voidcore > 0 then
        local names = {}
        for _, eval in ipairs(r.voidcoreItems or {}) do
            names[#names + 1] = eval.item.link and eval.item.link:match("%[(.-)%]") or eval.item.name or "?"
        end
        tooltip:AddLine(string.format("%sVoidcore target here:|r %s", ns.VC_HEX, table.concat(names, ", ")), 1, 1, 1, true)
    end
end

local function OnSearchEntryTooltip(tooltip, resultID)
    if not ns.db then return end
    local d = DungeonForResult(resultID)
    if not d then return end
    local shown = false
    if ns.db.lfgTooltip then
        local r = ns:ResultForDungeon(d)
        if r and r.scanned then
            AddDungeonLines(tooltip, r, ns.db.targetKey or 10, ns.dropCtx)
            shown = true
        end
    end
    if shown then tooltip:Show() end
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
    local d = self.dungeonByMapID and self.dungeonByMapID[mapID]
    if not d then return end
    local shown = false
    if self.db.keystoneTooltip then
        local r = self:EvaluateDungeonAt(d, level)
        if not r.scanned then
            tooltip:AddLine(" ")
            tooltip:AddLine("Slot Filler: loot table not scanned yet", 0.6, 0.6, 0.6)
        else
            AddDungeonLines(tooltip, r, level or (self.db.targetKey or 10), r.ctx)
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
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local ok, _, displayed = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        if ok and type(displayed) == "string" then link = displayed end
    end
    if ns.issecret(link) then return end
    local mapID, level = ns.KeystoneFromLink(link)
    if not mapID then
        -- the keystone item without a keystone link: it can only be ours
        local id = data and data.id
        if id and not ns.issecret(id) and id == KEYSTONE_ITEM
            and C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
            mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
            level = C_MythicPlus.GetOwnedKeystoneLevel()
        end
    end
    if not mapID or ns.issecret(mapID) or ns.issecret(level) then return end
    ns:AddKeystoneTooltip(tooltip, mapID, level)
end

ns:On("LOGIN", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    end
end)

ns:On("LOGIN", function()
    if LFGListUtil_SetSearchEntryTooltip then
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", OnSearchEntryTooltip)
    end
    -- every search entry refresh goes through this global in 12.x
    if LFGListSearchEntry_Update then
        hooksecurefunc("LFGListSearchEntry_Update", function(button)
            if not button or not button.resultID then return end
            if not hookedButtons[button] then
                hookedButtons[button] = true
                button:HookScript("OnEnter", OnEnter)
                button:HookScript("OnLeave", OnLeave)
            end
            UpdateButton(button)
        end)
    end
    HookScrollBox()
    if LFGListFrame and LFGListFrame.SearchPanel then
        LFGListFrame.SearchPanel:HookScript("OnShow", function()
            HookScrollBox()
            C_Timer.After(0, function() ns:RefreshLFGBadges() end)
        end)
    end
    ns:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED", function()
        C_Timer.After(0, function() ns:RefreshLFGBadges() end)
    end)
    ns:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED", function()
        C_Timer.After(0, function() ns:RefreshLFGBadges() end)
    end)
end)

local function Quoted(v)
    if ns.issecret(v) then return "secret" end
    if type(v) == "string" then return '"' .. v .. '"' end
    return tostring(v)
end

-- /sf lfg: what the client exposes for the listings on screen
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

ns:On("RESULTS_UPDATED", function() ns:RefreshLFGBadges() end)
ns:On("SETTINGS_CHANGED", function() ns:RefreshLFGBadges() end)
