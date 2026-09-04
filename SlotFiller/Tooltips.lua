-- Slot Filler: the tooltips of the window's rows.
local _, ns = ...
local Style, UI = ns.Style, ns.UI

local NONE, STAT, TRACK = ns.UPGRADE_NONE, ns.UPGRADE_STAT, ns.UPGRADE_TRACK
local HEX = ns.UPGRADE_HEX

local function Shift()
    return IsShiftKeyDown and IsShiftKeyDown() or false
end

-------------------------------------------------------------------------------
-- Equipped item descriptions
-------------------------------------------------------------------------------
-- "311  Hero 3/6  (up to 321)"
function UI.EquippedDesc(g)
    if not g or g.empty then return "empty slot" end
    local s = string.format("%d", g.ilvl or 0)
    if g.track and g.cur then
        s = s .. string.format("  %s %d/%d", ns:TrackDisplayName(g.track), g.cur, g.max or g.track.steps)
        if g.potential and g.potential > (g.ilvl or 0) then s = s .. string.format("  (up to %d)", g.potential) end
    elseif g.cur and g.max then
        s = s .. string.format("  %s %d/%d", g.trackName or "?", g.cur, g.max)
    end
    return s
end

-- "311 Hero 3/6" in row colours.
function UI.EquippedShort(g)
    if not g or g.empty then return "|cffff5555empty|r" end
    local s = string.format("|cffffffff%d|r", g.ilvl or 0)
    if g.track and g.cur then
        s = s .. string.format(" |cffaaaaaa%s %d/%d|r", ns:TrackDisplayName(g.track), g.cur, g.max or g.track.steps)
    elseif g.cur and g.max then
        s = s .. string.format(" |cffaaaaaa%s %d/%d|r", g.trackName or "?", g.cur, g.max)
    end
    return s
end

local function ItemList(header, list)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(header)
    for _, w in ipairs(list) do
        GameTooltip:AddLine(string.format("  %s  |cff888888%s|r", w.eval.item.link or ns.ItemName(w.eval.item), w.source or "?"), 1, 1, 1)
    end
end

-------------------------------------------------------------------------------
-- Gear tab: a slot row
-------------------------------------------------------------------------------
function ns:ShowSlotTooltip(btn)
    local slot = self.SLOT_BY_ID[btn.slotID]
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.PAIR_LABEL[btn.slotID] or slot.name or slot.key)
    for _, id in ipairs({ btn.slotID, self.PAIR_OF[btn.slotID] }) do
        local g = self.gear[id]
        if g and not g.empty and g.link then
            GameTooltip:AddLine(g.link)
            GameTooltip:AddLine(UI.EquippedDesc(g), 0.9, 0.9, 0.9)
        else
            GameTooltip:AddLine("Nothing equipped", 0.7, 0.7, 0.7)
        end
    end
    if self.PAIR_OF[btn.slotID] then GameTooltip:AddLine("|cff888888A drop is judged against the weaker of the two.|r") end
    local summary = self.slotSummary and self.slotSummary[btn.slotID]
    if summary then
        if #summary.wanted > 0 then ItemList(Style.AccentHex() .. "Wanted|r", summary.wanted) end
        if #summary.voidcore > 0 then
            if Shift() then
                ItemList(ns.VC_HEX .. "Voidcore targets|r", summary.voidcore)
            else
                GameTooltip:AddLine("|cff888888Shift: Voidcore targets|r")
            end
        end
        GameTooltip:AddLine(" ")
        if summary.count > 0 then
            GameTooltip:AddLine(string.format("%s%d upgrade drop(s)|r", HEX[summary.best], summary.count))
            local sources = {}
            for _, src in pairs(summary.sources) do sources[#sources + 1] = src end
            table.sort(sources, function(a, b) return a.name < b.name end)
            for _, src in ipairs(sources) do GameTooltip:AddLine(string.format("  %s: %d", src.name, src.n), 0.8, 0.8, 0.8) end
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

-------------------------------------------------------------------------------
-- Dungeons and Raid tabs: a dungeon or boss row
-------------------------------------------------------------------------------
function ns:ShowDungeonTooltip(row)
    local r = row.result
    if not r then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(r.sourceName or "?")
    if r.raid then GameTooltip:AddLine(r.raid.name, 0.7, 0.7, 0.7) end
    if not r.scanned then
        GameTooltip:AddLine(r.raid and "No loot listed for this difficulty." or "Loot table not scanned yet.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
        return
    end
    local ctx = r.ctx
    GameTooltip:AddDoubleLine("Usable items for your spec", tostring(r.total), 0.9, 0.9, 0.9, 1, 1, 1)
    if ctx.ilvl then
        GameTooltip:AddLine(" ")
        local label = ctx.raid and ((ctx.difficultyName or "Raid") .. " drop") or string.format("End of dungeon (+%d)", ctx.key or 0)
        GameTooltip:AddLine(string.format("%s: %d %s", label, ctx.ilvl, self:TrackText(ctx.track, ctx.step)), 1, 0.82, 0)
        GameTooltip:AddDoubleLine("  Upgrade drops", string.format("%s%d|r", HEX[r.upgrades > 0 and TRACK or NONE], r.upgrades), 0.9, 0.9, 0.9)
        GameTooltip:AddDoubleLine("  Slots covered", tostring(r.slotCount), 0.9, 0.9, 0.9, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    if r.wanted > 0 then
        GameTooltip:AddLine(Style.AccentHex() .. "Wanted items here|r")
        for _, eval in ipairs(r.wantedItems) do GameTooltip:AddLine("  " .. (eval.item.link or ns.ItemName(eval.item)), 1, 1, 1) end
    else
        GameTooltip:AddLine("Nothing from your wanted list drops here.", 0.6, 0.6, 0.6)
        GameTooltip:AddLine(string.format("Click the %s and star the drops you are after.", r.raid and "boss" or "dungeon"), 0.6, 0.6, 0.6, true)
    end
    -- the Voidcore roll, on request
    if Shift() then
        GameTooltip:AddLine(" ")
        local vc = ctx.voidcore
        if vc and vc.ilvl then
            GameTooltip:AddLine(string.format("%sVoidcore roll here:|r %d %s", ns.VC_HEX, vc.ilvl, self:TrackText(vc.track, vc.step)), 1, 1, 1)
        end
        if r.voidcore > 0 then
            GameTooltip:AddLine(ns.VC_HEX .. "Voidcore targets here|r")
            for _, eval in ipairs(r.voidcoreItems) do GameTooltip:AddLine("  " .. (eval.item.link or ns.ItemName(eval.item)), 1, 1, 1) end
        else
            GameTooltip:AddLine("No Voidcore targets here.", 0.6, 0.6, 0.6)
        end
    else
        GameTooltip:AddLine("|cff888888Shift: Voidcore roll|r")
    end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- A drop row: the item as it drops (or as the roll would give it), what it
-- would replace, its stats and value, the verdicts and the flags on it
-------------------------------------------------------------------------------
local function ValueLine(label, r)
    if not r.value then return end
    local s = string.format("%s: |cffffffff%d|r", label, r.value + 0.5)
    if r.valueGain then
        s = s .. string.format(" (%s%+d|r vs equipped)", r.valueGain >= 0 and "|cff33dd33" or "|cffff5555", r.valueGain + (r.valueGain >= 0 and 0.5 or -0.5))
    end
    GameTooltip:AddLine(s, 1, 1, 1, true)
end

local function Verdict(r)
    local s = HEX[r.class] .. ns.UPGRADE_LABEL[r.class] .. "|r" .. (r.reason and (" - " .. r.reason) or "")
    if r.class == STAT then
        s = s .. "  (same level, better stats)"
    elseif r.gain and r.class ~= NONE then
        s = s .. string.format("  (%+d now, %+d fully upgraded)", r.gain, r.potentialGain or 0)
    end
    return s
end

local function StatLine(label, stats, fit, r, g, b)
    GameTooltip:AddLine(string.format("%s: %s%s", label, ns:StatText(stats, fit, true),
        fit and string.format("  |cff888888%d%% match|r", fit * 100 + 0.5) or ""), r, g, b, true)
end

function ns:ShowItemTooltip(btn)
    local eval = btn.eval
    if not eval then return end
    local item = eval.item
    local ctx = btn.ctx or self.dropCtx
    -- a token row shows the token's own tooltip; the piece has its own row;
    -- a Voidcore tab row shows the item as the roll would give it
    local nested = UI.TokenNested(eval)
    local vc = ctx and ctx.voidcore
    local roll = btn.roll and eval.voidcore and vc and vc.ilvl and true or false
    local shift = roll or Shift()
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    local link, kind
    if nested then
        link, kind = eval.token.link, "token"
    elseif roll then
        link, kind = self:LinkForContext(item, eval.voidcoreMatched or { ilvl = vc.ilvl, step = vc.step, track = vc.track, potential = vc.potential, key = ctx.key, isVoidcore = true })
    else
        link, kind = self:LinkForContext(item, eval.matched or ctx or {})
    end
    if link then
        GameTooltip:SetHyperlink(link)
    else
        GameTooltip:SetItemByID((nested and eval.token or item).itemID)
    end
    GameTooltip:AddLine(" ")
    if eval.token then
        local slot = eval.slotID and self.SLOT_BY_ID[eval.slotID]
        local slotName = slot and (slot.name or slot.key) or "?"
        if nested and #eval.pieces > 1 then
            GameTooltip:AddLine(string.format("%s: traded for the set piece of any slot. Best for you: %s. Click to list all five.", ns.ItemName(eval.token), slotName), 0.9, 0.9, 0.9, true)
        elseif nested then
            GameTooltip:AddLine(string.format("%s: turns into %s (%s). Click to show it.", ns.ItemName(eval.token), ns.ItemName(item), slotName), 0.9, 0.9, 0.9, true)
        else
            GameTooltip:AddLine("From " .. ns.ItemName(eval.token) .. " (tier token)", 0.9, 0.9, 0.9)
        end
    end
    if btn.dungeonName then GameTooltip:AddLine("Drops in " .. btn.dungeonName, 0.9, 0.9, 0.9) end
    if ctx and ctx.ilvl and not nested then
        if kind == "exact" then
            local where = ctx.raid and ("on " .. (ctx.difficultyName or "this difficulty")) or string.format("from a +%d", ctx.key or 0)
            local matched = roll and eval.voidcoreMatched or (not roll and eval.matched)
            GameTooltip:AddLine(string.format("|cff888888Shown as %s %s%s|r", roll and "a Voidcore roll" or "it drops", where,
                matched and string.format(", upgraded free to %d", matched.ilvl) or ""))
        elseif item.token then
            GameTooltip:AddLine(item.equipLoc == "TIER_ANY" and "|cff888888Tier token: traded for your set piece of any slot; judged for the weakest|r"
                or "|cff888888Tier token: turns into your set piece for this slot|r")
        else
            GameTooltip:AddLine("|cff888888Base item shown; the drop's own level is listed below|r")
        end
    end
    if eval.slotID then
        local slot = self.SLOT_BY_ID[eval.slotID]
        GameTooltip:AddLine(string.format("Would replace (%s): %s", slot.name or slot.key, UI.EquippedDesc(eval.equipped)), 0.9, 0.9, 0.9, true)
    end
    if eval.stats and not nested then
        StatLine("Stats", eval.stats, eval.fit, 1, 1, 1)
        if eval.equippedStats then StatLine("Equipped", eval.equippedStats, eval.equippedFit, 0.9, 0.9, 0.9) end
    end
    local scale = ctx and ctx.statWeights
    ValueLine(string.format("Weighted value (%s)", scale and scale.name or "Pawn"), eval)
    if ctx and ctx.ilvl then
        local label = ctx.raid and ((ctx.difficultyName or "Raid") .. " drop") or string.format("End of dungeon +%d", ctx.key or 0)
        GameTooltip:AddLine(string.format("%s: |cffffffff%d|r %s%s", label, ctx.ilvl, self:TrackText(ctx.track, ctx.step),
            (ctx.potential and ctx.potential > ctx.ilvl) and string.format(" (up to %d)", ctx.potential) or ""), 1, 0.82, 0, true)
    end
    -- the free upgrade to the slot's level (Match level)
    if self.db.matchLevel and eval.freeLevel and eval.freeLevel > 0 then
        local m = eval.matched
        if m then
            GameTooltip:AddLine(string.format("Free upgrade: |cffffffff%d|r %s  |cff888888(slot level %d)|r", m.ilvl, self:TrackText(m.track, m.step), eval.freeLevel), 1, 0.82, 0, true)
        else
            GameTooltip:AddLine(string.format("|cff888888Free upgrade: none (slot level %d)|r", eval.freeLevel), 1, 1, 1, true)
        end
    end
    GameTooltip:AddLine("  " .. Verdict(eval), 1, 1, 1, true)
    if btn.roll and btn.source then
        if self:IsRolled(btn.source, (eval.token or item).itemID) then
            GameTooltip:AddLine("|cff888888Rolled already: out of this pool until it refills. Right-click: not rolled.|r")
        else
            GameTooltip:AddLine("|cff888888Right-click: mark as rolled.|r")
        end
    end
    if eval.owned then
        local o = eval.owned
        local further = eval.reason == "owned" and "" or "; the drop would go further"
        if o.catalyzed then
            GameTooltip:AddLine(string.format("|cff888888You already have this, catalyzed into %s: %d %s (%s)%s|r", o.name or "a set piece", o.ilvl or 0,
                self:TrackText(o.track, o.cur), o.where or "equipped", further))
        elseif o.unknownLevel then
            GameTooltip:AddLine("|cff888888You already have this (bags or bank)|r")
        else
            GameTooltip:AddLine(string.format("|cff888888You already have this: %d %s (%s)%s|r", o.ilvl or 0, self:TrackText(o.track, o.cur), o.where or "?", further))
        end
    end
    if self:IsCatalystCandidate(eval) then
        local p = self:SetProgress()
        GameTooltip:AddLine(string.format("|cff888888Catalyst: can become a set piece, stats kept%s%s|r",
            p.nextBonus and string.format(" (%d-piece needs %d)", p.nextBonus, p.need) or "",
            p.charges and string.format(", %d charge%s", p.charges, p.charges == 1 and "" or "s") or ""))
    end
    -- the Voidcore roll, on request
    if item.noRoll then
        GameTooltip:AddLine("|cff888888Not in the bonus roll pool|r")
    elseif vc and vc.ilvl and eval.voidcore then
        if shift then
            GameTooltip:AddLine(string.format("%sVoidcore roll|r: |cffffffff%d|r %s%s", ns.VC_HEX, vc.ilvl, self:TrackText(vc.track, vc.step),
                (vc.potential and vc.potential > vc.ilvl) and string.format(" (up to %d)", vc.potential) or ""), 1, 1, 1, true)
            local m = eval.voidcoreMatched
            if m then GameTooltip:AddLine(string.format("  Free upgrade: |cffffffff%d|r %s", m.ilvl, self:TrackText(m.track, m.step)), 1, 1, 1, true) end
            GameTooltip:AddLine("  " .. Verdict(eval.voidcore), 1, 1, 1, true)
            ValueLine("  " .. ns.VC_HEX .. "Roll value|r", eval.voidcore)
        else
            GameTooltip:AddLine("|cff888888Shift: Voidcore roll|r")
        end
    end
    local state = self:GetItemState(item.itemID)
    local target = self:IsVoidcoreTarget(item.itemID) and not item.noRoll
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

-------------------------------------------------------------------------------
-- IO tab: a dungeon row
-------------------------------------------------------------------------------
function ns:ShowRatingTooltip(row)
    local e, d = row.entry, row.dungeon
    if not e or not d then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(d.name)
    if not e.hasRun then
        GameTooltip:AddLine("Not run this season.", 0.7, 0.7, 0.7)
    else
        local when = e.durationSec and (" " .. self:FormatDuration(e.durationSec)) or ""
        GameTooltip:AddLine(string.format("Best: +%d %s%s (%d)", e.level, e.timed and "timed" or "over time", when, self:Round(e.score)), 1, 1, 1)
    end
    local gear = row.gear or (row.gearLevel and self:DropsAtKey(d, row.gearLevel))
    if gear and gear.scanned then
        GameTooltip:AddLine(string.format("Drops at +%d: %d upgrade%s%s.", row.gearLevel or 0, gear.upgrades, gear.upgrades == 1 and "" or "s",
            gear.wanted > 0 and string.format(", %d wanted", gear.wanted) or ""), 1, 1, 1)
    end
    if row.avoided then
        GameTooltip:AddLine("|cffff5555Avoided|r: left out of the plans.", 1, 1, 1)
    elseif row.run then
        GameTooltip:AddLine(string.format("%sPlan|r: time a +%d for +%d.", Style.AccentHex(), row.run.level, self:Round(row.run.gain)), 1, 1, 1)
    elseif row.hasPlan then
        GameTooltip:AddLine("Not in this plan.", 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine("Click: key ladder.  Right-click: avoid.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- Voidcore tab: a source row
-------------------------------------------------------------------------------
function ns:ShowRollTooltip(row)
    local s = row.source
    if not s then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(s.name)
    local where = s.kind == "dungeon" and string.format("a +%d", s.key or 0) or self:RaidDifficultyName(s.raid, s.diffKey)
    if not s.ready then
        GameTooltip:AddLine("Loot not scanned yet.", 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine(string.format("Pool for %s from %s: %d of %d left%s", self:SpecName(self:GetLootSpecID()) or "your loot spec", where,
            s.count, s.total, s.tooltipRead and "  |cff888888(the game's own list)|r" or ""), 1, 1, 1)
        if s.count > 0 then
            GameTooltip:AddLine(string.format("%d usable (%d%%), %d ideal (%d%%), %d target%s, %d wanted", s.usable, math.floor(s.chance * 100 + 0.5),
                s.ideal, math.floor(s.idealChance * 100 + 0.5), s.targets, s.targets == 1 and "" or "s", s.wanted), 1, 1, 1)
            GameTooltip:AddLine("|cff888888Ideal: an upgrade whose stats fit too (a 75% match, better than the piece it replaces, or a weighted gain with a profile).|r", 1, 1, 1, true)
            GameTooltip:AddLine(string.format("A roll here gains |cffffffff+%.1f|r item levels on average (slot-weighted; targets and wanted items count extra).", s.ev), 0.9, 0.9, 0.9, true)
            if s.best then
                GameTooltip:AddLine(string.format("Best in the pool: %s (+%.1f)", ns.ItemName(s.best.token or s.best.item), s.bestValue), 0.9, 0.9, 0.9, true)
            end
        end
    end
    GameTooltip:AddLine("Click: the pool, with what each roll would be. Right-click an item there: mark it rolled.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
