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

local function EnsureBadge(button)
    if button.SlotFillerBadge then return button.SlotFillerBadge end
    local badge = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.Style.Font(badge)
    local anchor = button.DataDisplay or button
    if button.DataDisplay then
        badge:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
    else
        badge:SetPoint("RIGHT", anchor, "RIGHT", -100, 0)
    end
    button.SlotFillerBadge = badge
    return badge
end

local function UpdateButton(button)
    local badge = button.SlotFillerBadge
    if not ns.db or not ns.db.lfgBadges then
        if badge then badge:SetText("") end
        return
    end
    local d = DungeonForResult(button.resultID)
    local r = d and ns:ResultForDungeon(d)
    badge = EnsureBadge(button)
    if r and r.scanned then
        local text
        if r.upgrades > 0 then
            text = string.format("%s%d^|r", HexFor(r), r.upgrades)
        else
            text = "|cff666666-|r"
        end
        if r.wanted and r.wanted > 0 then
            text = text .. ns.Style.AccentHex() .. "*|r"
        end
        badge:SetText(text)
    else
        badge:SetText("")
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
-- dungeon at `key`, plus the Voidcore chance when the context has one.
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
end

local function OnSearchEntryTooltip(tooltip, resultID)
    if not ns.db or not ns.db.lfgTooltip then return end
    local d = DungeonForResult(resultID)
    if not d then return end
    local r = ns:ResultForDungeon(d)
    if not r or not r.scanned then return end
    AddDungeonLines(tooltip, r, ns.db.targetKey or 10, ns.dropCtx)
    tooltip:Show()
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
    local r = self:EvaluateDungeonAt(d, level)
    if not r.scanned then
        tooltip:AddLine(" ")
        tooltip:AddLine("Slot Filler: loot table not scanned yet", 0.6, 0.6, 0.6)
    else
        AddDungeonLines(tooltip, r, level or (self.db.targetKey or 10), r.ctx)
    end
    tooltip:Show()
end

local function OnItemTooltip(tooltip, data)
    if not ns.db or not ns.db.keystoneTooltip then return end
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

ns:On("RESULTS_UPDATED", function() ns:RefreshLFGBadges() end)
ns:On("SETTINGS_CHANGED", function() ns:RefreshLFGBadges() end)
