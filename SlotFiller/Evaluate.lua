-- Slot Filler: decide which drops are upgrades and rank dungeons.
--
-- Every item is judged twice:
--   * as the end-of-dungeon drop at the chosen key level, and
--   * as a Nebulous Voidcore bonus roll, which Blizzard awards at the Great
--     Vault item level of that key (+10 and up: Myth 1/6).
local _, ns = ...

local NONE, ILVL, TRACK, WANT = ns.UPGRADE_NONE, ns.UPGRADE_ILVL, ns.UPGRADE_TRACK, ns.UPGRADE_WANT

-------------------------------------------------------------------------------
-- Drop context for the chosen key level
-------------------------------------------------------------------------------
local function Level(ilvl, source)
    if not ilvl then return nil end
    local track, step = ns:TrackForIlvl(ilvl)
    return {
        ilvl = ilvl,
        source = source,
        track = track,
        step = step,
        potential = track and math.max(track.max, ilvl) or ilvl,
    }
end

function ns:GetDropContext(keyLevel)
    local maxKey = self:MaxUsefulKey() or 10
    if not keyLevel and self.db and self.db.voidcoreMode then
        -- Selector past the last useful key: the reward is the Voidcore roll,
        -- which uses the Great Vault item level of that key.
        local vaultIlvl, vaultSource = self:VaultIlvl(maxKey)
        local ctx = Level(vaultIlvl, vaultSource) or { source = vaultSource }
        ctx.key = maxKey
        ctx.isVoidcore = true
        ctx.voidcore = Level(vaultIlvl, vaultSource)
        ctx.statPrio, ctx.statPrioSource = self:GetStatPriority()
    ctx.statWeights = self:GetStatWeights()
        return ctx
    end
    keyLevel = keyLevel or (self.db and self.db.targetKey) or 10
    local ilvl, source = self:RewardIlvl(keyLevel)
    local vaultIlvl, vaultSource = self:VaultIlvl(keyLevel)
    local ctx = Level(ilvl, source) or { source = source }
    ctx.key = keyLevel
    ctx.voidcore = Level(vaultIlvl, vaultSource)
    ctx.statPrio, ctx.statPrioSource = self:GetStatPriority()
    ctx.statWeights = self:GetStatWeights()
    return ctx
end

-------------------------------------------------------------------------------
-- Classification of one drop against one equipped item
-------------------------------------------------------------------------------
local function Classify(g, dropIlvl, dropPotential, itemState, slotState)
    local r = {}
    r.gain = dropIlvl - (g.ilvl or 0)
    r.potentialGain = (dropPotential or dropIlvl) - (g.potential or 0)
    if itemState == "exclude" then
        r.class = NONE
        r.reason = "excluded"
    elseif itemState == "want" or slotState == "want" then
        r.class = WANT
    elseif g.empty then
        r.class = TRACK
        r.reason = "empty slot"
    elseif r.potentialGain > 0 then
        r.class = TRACK
    elseif r.gain > 0 then
        r.class = ILVL
    else
        r.class = NONE
    end
    return r
end

-------------------------------------------------------------------------------
-- Single item evaluation
-------------------------------------------------------------------------------
function ns:EvaluateItem(item, ctx)
    local eval = { item = item, class = NONE, slotID = nil }
    if not ctx.ilvl then
        eval.reason = "unknown drop item level"
        return eval
    end
    local candidates = self:CandidateSlotsFor(item.equipLoc)
    if not candidates then
        eval.reason = "not equippable"
        return eval
    end

    -- Pick the equipped slot this drop would replace: a "want" slot first,
    -- otherwise the weakest candidate by potential then item level.
    local best, bestScore
    for _, slotID in ipairs(candidates) do
        local state = self:GetSlotState(slotID)
        local g = self.gear[slotID] or { empty = true, ilvl = 0, potential = 0 }
        local score
        if state == "skip" then
            score = nil
        elseif state == "want" then
            score = -1
        else
            score = (g.potential or 0) * 1000 + (g.ilvl or 0)
        end
        if score and (not bestScore or score < bestScore) then
            best, bestScore = slotID, score
        end
    end
    if not best then
        eval.reason = "slot skipped"
        return eval
    end
    eval.slotID = best
    local g = self.gear[best] or { empty = true, ilvl = 0, potential = 0 }
    eval.equipped = g
    local fitScale = ctx.statPrioSource == "weights" and ctx.statWeights or nil
    eval.stats = self:ItemStats(item.link)
    eval.fit = self:StatFit(eval.stats, ctx.statPrio, fitScale)
    if not g.empty then
        eval.equippedStats = self:ItemStats(g.link)
        eval.equippedFit = self:StatFit(eval.equippedStats, ctx.statPrio, fitScale)
    end
    local slotState = self:GetSlotState(best)
    local itemState = self:GetItemState(item.itemID)

    -- Off-hand sanity: two-hander users don't want off-hands, and a shield or
    -- held item is not a replacement for a weapon in the off hand.
    if best == 17 then
        local loc = item.equipLoc
        if g.empty then
            local mh = self.gear[16]
            if mh and mh.equipLoc == "INVTYPE_2HWEAPON" then
                eval.reason = "using a two-hander"
                return eval
            end
        elseif (loc == "INVTYPE_SHIELD" or loc == "INVTYPE_HOLDABLE") and g.classID == self.ITEM_CLASS_WEAPON then
            eval.reason = "off hand holds a weapon"
            return eval
        end
    end

    local drop = Classify(g, ctx.ilvl, ctx.potential, itemState, slotState)
    eval.class, eval.reason, eval.gain, eval.potentialGain = drop.class, drop.reason, drop.gain, drop.potentialGain
    if ctx.voidcore and ctx.voidcore.ilvl then
        eval.voidcore = Classify(g, ctx.voidcore.ilvl, ctx.voidcore.potential, itemState, slotState)
    end
    -- Weighted values (Pawn scale): the drop at its actual level vs the equipped item.
    local scale = ctx.statWeights
    if scale then
        local equippedValue = (not g.empty) and self:ItemValue(g.link, scale) or (g.empty and 0) or nil
        eval.equippedValue = equippedValue
        local link, kind = self:LinkForContext(item, ctx)
        if kind == "exact" then
            eval.value = self:ItemValue(link, scale)
            if eval.value and equippedValue then eval.valueGain = eval.value - equippedValue end
        end
        local vc = ctx.voidcore
        if eval.voidcore and vc and vc.ilvl then
            local vlink, vkind = self:LinkForContext(item, { ilvl = vc.ilvl, step = vc.step, track = vc.track, key = ctx.key, isVoidcore = true })
            if vkind == "exact" then
                eval.voidcore.value = self:ItemValue(vlink, scale)
                if eval.voidcore.value and equippedValue then eval.voidcore.valueGain = eval.voidcore.value - equippedValue end
            end
        end
    end
    return eval
end

-- which: nil/"drop" for the end-of-dungeon drop, "voidcore" for the bonus roll
function ns:CountsAsUpgrade(eval, which)
    local r = eval
    if which == "voidcore" then
        r = eval.voidcore
        if not r then return false end
    end
    if r.class == TRACK or r.class == WANT then return true end
    if r.class == ILVL and self.db.countIlvlUpgrades then return true end
    return false
end

-------------------------------------------------------------------------------
-- Slot ordering for display
-------------------------------------------------------------------------------
local slotOrder = {}
for i, s in ipairs(ns.SLOTS) do slotOrder[s.id] = i end

local function ItemSort(a, b)
    if a.class ~= b.class then return a.class > b.class end
    local av, bv = a.voidcore and a.voidcore.class or 0, b.voidcore and b.voidcore.class or 0
    if av ~= bv then return av > bv end
    local sa, sb = slotOrder[a.slotID or 0] or 99, slotOrder[b.slotID or 0] or 99
    if sa ~= sb then return sa < sb end
    -- same slot: by weighted value when a scale is imported, else the drop
    -- whose stats sit higher in the priority first
    if a.value and b.value and a.value ~= b.value then return a.value > b.value end
    local fa, fb = a.fit or 0.5, b.fit or 0.5
    if fa ~= fb then return fa > fb end
    return (a.item.name or "") < (b.item.name or "")
end

-------------------------------------------------------------------------------
-- Full evaluation
-------------------------------------------------------------------------------
-- One dungeon against one drop context.
function ns:EvaluateDungeon(d, ctx)
    local loot = self:GetDungeonLoot(d.challengeMapID)
    local r = {
        dungeon = d,
        items = {},
        upgrades = 0,        -- end-of-dungeon drop upgrades
        trackUpgrades = 0,
        vcUpgrades = 0,      -- Voidcore roll upgrades
        vcTrackUpgrades = 0,
        total = 0,
        slots = {},
        slotCount = 0,
        chance = 0,
        vcChance = 0,
        wanted = 0,          -- items on the wanted list that drop here
        wantedItems = {},
        scanned = loot ~= nil,
    }
    if loot then
        for _, item in ipairs(loot) do
            r.total = r.total + 1
            local eval = self:EvaluateItem(item, ctx)
            table.insert(r.items, eval)
            if self:GetItemState(item.itemID) == "want" then
                r.wanted = r.wanted + 1
                table.insert(r.wantedItems, eval)
            end
            if self:CountsAsUpgrade(eval) then
                r.upgrades = r.upgrades + 1
                if eval.class ~= ILVL then r.trackUpgrades = r.trackUpgrades + 1 end
                if eval.slotID and not r.slots[eval.slotID] then
                    r.slots[eval.slotID] = true
                    r.slotCount = r.slotCount + 1
                end
            end
            if self:CountsAsUpgrade(eval, "voidcore") then
                r.vcUpgrades = r.vcUpgrades + 1
                if eval.voidcore.class ~= ILVL then r.vcTrackUpgrades = r.vcTrackUpgrades + 1 end
            end
        end
        table.sort(r.items, ItemSort)
        if r.total > 0 then
            r.chance = r.upgrades / r.total
            r.vcChance = r.vcUpgrades / r.total
        end
    end
    return r
end

-- One dungeon at a specific key level (keystone tooltips). The context used is
-- returned as r.ctx.
function ns:EvaluateDungeonAt(d, keyLevel)
    local ctx = self:GetDropContext(keyLevel)
    local r = self:EvaluateDungeon(d, ctx)
    r.ctx = ctx
    return r
end

function ns:Evaluate()
    local ctx = self:GetDropContext()
    local results = {}
    for _, d in ipairs(self.dungeons) do
        table.insert(results, self:EvaluateDungeon(d, ctx))
    end

    local mode = self.db.sortMode or "upgrades"
    table.sort(results, function(a, b)
        if mode == "name" then return a.dungeon.name < b.dungeon.name end
        if mode == "wanted" then
            if a.wanted ~= b.wanted then return a.wanted > b.wanted end
        end
        if a.upgrades ~= b.upgrades then return a.upgrades > b.upgrades end
        if a.wanted ~= b.wanted then return a.wanted > b.wanted end
        if a.chance ~= b.chance then return a.chance > b.chance end
        if a.vcChance ~= b.vcChance then return a.vcChance > b.vcChance end
        return a.dungeon.name < b.dungeon.name
    end)

    self.results = results
    self.dropCtx = ctx
    self.resultByMapID = {}
    for _, r in ipairs(results) do self.resultByMapID[r.dungeon.challengeMapID] = r end
    self:Fire("RESULTS_UPDATED")
    return results
end

-- Per-slot summary for the slot strip: best upgrade class available anywhere.
function ns:SlotSummary()
    local summary = {}
    for _, s in ipairs(self.SLOTS) do
        summary[s.id] = { best = NONE, dungeons = {}, count = 0, vcCount = 0, vcBest = NONE, wanted = {} }
    end
    if not self.results then return summary end
    for _, r in ipairs(self.results) do
        for _, eval in ipairs(r.items) do
            if eval.slotID then
                local e = summary[eval.slotID]
                if self:GetItemState(eval.item.itemID) == "want" then
                    table.insert(e.wanted, { eval = eval, dungeon = r.dungeon })
                end
                if self:CountsAsUpgrade(eval) then
                    e.count = e.count + 1
                    if eval.class > e.best then e.best = eval.class end
                    e.dungeons[r.dungeon.challengeMapID] = (e.dungeons[r.dungeon.challengeMapID] or 0) + 1
                    -- best drop: largest fully-upgraded gain, then immediate gain
                    local gain = (eval.potentialGain or 0) * 1000 + (eval.gain or 0)
                    if eval.class ~= WANT and (not e.bestDrop or gain > e.bestDropScore) then
                        e.bestDrop, e.bestDropScore = { eval = eval, dungeon = r.dungeon }, gain
                    end
                end
                if self:CountsAsUpgrade(eval, "voidcore") then
                    e.vcCount = e.vcCount + 1
                    if eval.voidcore.class > e.vcBest then e.vcBest = eval.voidcore.class end
                end
            end
        end
    end
    return summary
end

function ns:ResultForDungeon(d)
    return d and self.resultByMapID and self.resultByMapID[d.challengeMapID] or nil
end

-------------------------------------------------------------------------------
-- Re-evaluate whenever inputs change
-------------------------------------------------------------------------------
local function Reevaluate()
    if not ns.db or not ns.dungeonsBuilt then return end
    if not ns.gearScanned then ns:ScanGear() end
    ns:Schedule("evaluate", 0.1, function() ns:Evaluate() end)
end

ns:On("GEAR_UPDATED", Reevaluate)
ns:On("LOOT_UPDATED", Reevaluate)
ns:On("SETTINGS_CHANGED", Reevaluate)
ns:On("TRACKS_CHANGED", Reevaluate)
ns:On("DUNGEONS_UPDATED", Reevaluate)

-- Selector: +2 .. +maxKey, then "Voidcore" (end-of-dungeon gear stops
-- improving past maxKey, so the next thing up is the bonus roll).
function ns:SetTargetKey(n)
    n = tonumber(n)
    if not n then return end
    local maxKey = self:MaxUsefulKey() or 10
    if n > maxKey then
        self.db.voidcoreMode = true
        self.db.targetKey = maxKey
    else
        self.db.voidcoreMode = false
        self.db.targetKey = math.max(2, math.floor(n))
    end
    self:ClearRewardCache()
    self:Fire("SETTINGS_CHANGED")
end

function ns:StepTargetKey(delta)
    local maxKey = self:MaxUsefulKey() or 10
    if self.db.voidcoreMode then
        if delta < 0 then self:SetTargetKey(maxKey) end
        return
    end
    self:SetTargetKey((self.db.targetKey or 10) + delta)
end

function ns:TargetLabel()
    if self.db.voidcoreMode then return self.VC_HEX .. "Voidcore|r" end
    return "+" .. tostring(self.db.targetKey or 10)
end
