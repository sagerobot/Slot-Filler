-- Slot Filler: decide which drops are upgrades and rank dungeons and bosses.
--
-- Every item is judged as the direct drop: end of dungeon at the chosen key
-- level, or off a raid boss at the chosen difficulty. That is what the
-- lists and counts show. It is also judged as a Nebulous Voidcore bonus
-- roll, which Blizzard awards at the Great Vault level (a key's vault item
-- level, +10 and up: Myth 1/6; a raid boss one upgrade track above the
-- difficulty); that verdict is only shown in tooltips while Shift is held.
-- Which drops to spend a Voidcore on is the player's call: the Voidcore
-- targets, a second star next to the wanted list.
local _, ns = ...

local NONE, STAT, ILVL, TRACK, WANT = ns.UPGRADE_NONE, ns.UPGRADE_STAT, ns.UPGRADE_ILVL, ns.UPGRADE_TRACK, ns.UPGRADE_WANT

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
-- Drop context for a raid boss at a difficulty
-------------------------------------------------------------------------------
function ns:GetRaidDifficulty()
    local key = self.db and self.db.raidDifficulty
    return (key and self.RAID_DIFF_BY_KEY[key]) and key or "heroic"
end

function ns:SetRaidDifficulty(key)
    if not self.RAID_DIFF_BY_KEY[key] or not self.db then return end
    self.db.raidDifficulty = key
    self:Fire("SETTINGS_CHANGED")
end

-- The direct drop is the difficulty's track; later bosses drop higher within
-- it. The level comes from the season table shipped with the addon, else
-- the boss's journal loot: the level remembered at scan time, else the
-- link's (right only while the journal holds the loot), else the track's
-- first step. The Voidcore roll (and the vault) is one track up at its
-- first step; on Mythic it is the fully upgraded item, or the drop itself
-- where that is already past the top of the track.
function ns:GetRaidContext(diffKey, boss, raid)
    local def = self.RAID_DIFF_BY_KEY[diffKey] or self.RAID_DIFF_BY_KEY.heroic
    local track = self.trackByKey[def.track]
    local ilvl, source
    if track and boss and not raid then
        for _, r in ipairs(self:GetRaids()) do
            for _, b in ipairs(r.bosses) do
                if b == boss then raid = r end
            end
        end
    end
    if track and boss and raid then
        ilvl = self:ShippedBossLevel(raid, boss, def.key, track)
        if ilvl then source = "season" end
    end
    local items = not ilvl and boss and self:GetBossLoot(boss, def.key)
    if track and items then
        for _, item in ipairs(items) do
            local l = item.ilvl or self.ItemLevelOf(item.link)
            if not l then self:NeedItemData(item.itemID) end
            if l and l >= track.min and (l <= track.max or def.track == "Myth") and (not ilvl or l > ilvl) then ilvl = l end
        end
        if ilvl then source = "journal" end
    end
    if not ilvl and track then ilvl, source = track.min, "track" end
    local ctx = Level(ilvl, source) or { source = source }
    ctx.raid = true
    ctx.difficulty = def.key
    ctx.difficultyName = def.name
    if track then
        local up
        for i, t in ipairs(self.tracks) do
            if t == track then up = self.tracks[i + 1]; break end
        end
        local vcIlvl = up and up.min or math.max(track.max, ilvl or 0)
        ctx.voidcore = Level(vcIlvl, source)
    end
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
-- Match level: a drop (or a roll) as it would be after the free upgrade to
-- the slot's level `mark`: the highest step of its own track at or under
-- the mark, never below the level itself. Returns `level` itself when
-- nothing changes.
-------------------------------------------------------------------------------
local function Matched(level, mark)
    if not level or not level.ilvl or not mark or mark <= level.ilvl then return level end
    local ilvl, step = level.ilvl, level.step
    if level.track then
        for i, v in ipairs(level.track.ilvls) do
            if v <= mark and v > ilvl then ilvl, step = v, i end
        end
    else
        ilvl = math.min(mark, level.potential or level.ilvl)
    end
    if ilvl == level.ilvl then return level end
    return { ilvl = ilvl, step = step, track = level.track, potential = level.potential, source = level.source,
        key = level.key, from = level.ilvl, mark = mark }
end

-- Same level, no lower ceiling, better stats: a weighted value above the
-- equipped item's when a scale is in use, else a better fit.
local function StatUpgrade(eval, r)
    if r.class ~= NONE or r.reason then return false end
    if (r.gain or 0) ~= 0 or (r.potentialGain or 0) < 0 then return false end
    if r.valueGain then return r.valueGain > 0 end
    if eval.fit and eval.equippedFit then return eval.fit > eval.equippedFit + 0.01 end
    return false
end

function ns:SetMatchLevel(on)
    if not self.db then return end
    self.db.matchLevel = on and true or false
    if on then self:ScanWatermarks() end
    self:Fire("SETTINGS_CHANGED")
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

    -- Match level: the drop and the roll as they would be after the free
    -- upgrade to the slot's level.
    local dropLevel, vcLevel = ctx, ctx.voidcore
    if self.db.matchLevel then
        local mark = self:FreeUpgradeLevel(item, candidates)
        eval.freeLevel = mark
        dropLevel = Matched(ctx, mark)
        vcLevel = Matched(ctx.voidcore, mark)
        if dropLevel ~= ctx then eval.matched = dropLevel end
        if vcLevel ~= ctx.voidcore then eval.voidcoreMatched = vcLevel end
    end

    local drop = Classify(g, dropLevel.ilvl, dropLevel.potential, itemState, slotState)
    eval.class, eval.reason, eval.gain, eval.potentialGain = drop.class, drop.reason, drop.gain, drop.potentialGain
    -- no roll verdict for what a bonus roll cannot award (the omni token)
    if vcLevel and vcLevel.ilvl and not item.noRoll then
        eval.voidcore = Classify(g, vcLevel.ilvl, vcLevel.potential, itemState, slotState)
    end
    -- Weighted values (Pawn scale): the drop at its (matched) level vs the equipped item.
    local scale = ctx.statWeights
    if scale then
        local equippedValue = (not g.empty) and self:ItemValue(g.link, scale) or (g.empty and 0) or nil
        eval.equippedValue = equippedValue
        local link, kind = self:LinkForContext(item, eval.matched or ctx)
        if kind == "exact" then
            eval.value = self:ItemValue(link, scale)
            if eval.value and equippedValue then eval.valueGain = eval.value - equippedValue end
        end
        if eval.voidcore and vcLevel and vcLevel.ilvl then
            local vlink, vkind = self:LinkForContext(item, { ilvl = vcLevel.ilvl, step = vcLevel.step, track = vcLevel.track, key = ctx.key, isVoidcore = true })
            if vkind == "exact" then
                eval.voidcore.value = self:ItemValue(vlink, scale)
                if eval.voidcore.value and equippedValue then eval.voidcore.valueGain = eval.voidcore.value - equippedValue end
            end
        end
    end
    -- Match level: at the same level, better stats make it an upgrade.
    if self.db.matchLevel then
        if StatUpgrade(eval, eval) then eval.class = STAT end
        if eval.voidcore and StatUpgrade(eval, eval.voidcore) then eval.voidcore.class = STAT end
    end
    return eval
end

-- Whether the direct drop counts in the Drops column.
function ns:CountsAsUpgrade(eval)
    if eval.class == TRACK or eval.class == WANT then return true end
    if (eval.class == ILVL or eval.class == STAT) and self.db.countIlvlUpgrades then return true end
    return false
end

-------------------------------------------------------------------------------
-- Slot ordering for display
-------------------------------------------------------------------------------
local slotOrder = {}
for i, s in ipairs(ns.SLOTS) do slotOrder[s.id] = i end

local function ItemSort(a, b)
    if a.class ~= b.class then return a.class > b.class end
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
-- A set piece read from the journal's Class Sets tab carries no name or
-- link until the client holds the item; fill them in once it does.
function ns:FillItemInfo(item)
    if not item or item.name or not item.itemID or not (C_Item and C_Item.GetItemInfo) then return end
    local ok, name, link = pcall(C_Item.GetItemInfo, item.itemID)
    if ok and name then
        item.name = name
        if link then item.link = link end
    end
end

-- Best first: class, then fully upgraded gain, then immediate gain.
local function BetterEval(a, b)
    if a.class ~= b.class then return a.class > b.class end
    if (a.potentialGain or 0) ~= (b.potentialGain or 0) then return (a.potentialGain or 0) > (b.potentialGain or 0) end
    return (a.gain or 0) > (b.gain or 0)
end

-- One loot entry: an item, or a tier token judged as the set piece(s) it
-- becomes: each piece is judged for its slot (eval.token names the token)
-- and the token stands as the best of them, with the pieces under it
-- (eval.pieces: one for a slot token, five for one traded for any slot).
local function EvaluateEntry(self, item, ctx)
    local pieces = item.pieces or (item.piece and { item.piece })
    if not pieces or #pieces == 0 then return self:EvaluateItem(item, ctx) end
    local evals = {}
    for _, piece in ipairs(pieces) do
        self:FillItemInfo(piece)
        self:NeedItemData(piece.itemID)
        local eval = self:EvaluateItem(piece, ctx)
        eval.token = item
        evals[#evals + 1] = eval
    end
    local best = evals[1]
    for i = 2, #evals do
        if BetterEval(evals[i], best) then best = evals[i] end
    end
    local top = {}
    for k, v in pairs(best) do top[k] = v end
    top.pieces, top.token = evals, item
    return top
end

-- One loot table (a dungeon's or a boss's) against one drop context. The
-- caller adds where it came from: sourceName / sourceKey and dungeon or
-- raid + boss.
local function EvaluateLoot(self, loot, ctx)
    local r = {
        ctx = ctx,
        items = {},
        upgrades = 0,        -- direct drop upgrades
        trackUpgrades = 0,
        total = 0,
        slots = {},
        slotCount = 0,
        chance = 0,
        wanted = 0,          -- items on the wanted list that drop here
        wantedItems = {},
        voidcore = 0,        -- Voidcore targets that drop here
        voidcoreItems = {},
        scanned = loot ~= nil,
    }
    if loot then
        for _, item in ipairs(loot) do
            r.total = r.total + 1
            self:NeedItemData(item.itemID)
            local eval = EvaluateEntry(self, item, ctx)
            local itemID = eval.item.itemID
            table.insert(r.items, eval)
            if self:GetItemState(itemID) == "want" then
                r.wanted = r.wanted + 1
                table.insert(r.wantedItems, eval)
            end
            if self:IsVoidcoreTarget(itemID) and not eval.item.noRoll then
                r.voidcore = r.voidcore + 1
                table.insert(r.voidcoreItems, eval)
            end
            if self:CountsAsUpgrade(eval) then
                r.upgrades = r.upgrades + 1
                if eval.class ~= ILVL and eval.class ~= STAT then r.trackUpgrades = r.trackUpgrades + 1 end
                if eval.slotID and not r.slots[eval.slotID] then
                    r.slots[eval.slotID] = true
                    r.slotCount = r.slotCount + 1
                end
            end
        end
        table.sort(r.items, ItemSort)
        if r.total > 0 then
            r.chance = r.upgrades / r.total
        end
    end
    return r
end

function ns:EvaluateDungeon(d, ctx)
    local r = EvaluateLoot(self, self:GetDungeonLoot(d.challengeMapID), ctx)
    r.dungeon = d
    r.sourceName = d.name
    r.sourceKey = "d" .. tostring(d.challengeMapID)
    return r
end

function ns:EvaluateBoss(raid, boss, diffKey)
    local ctx = self:GetRaidContext(diffKey, boss, raid)
    ctx.difficultyName = self:RaidDifficultyName(raid, diffKey)
    local r = EvaluateLoot(self, self:GetBossLoot(boss, diffKey), ctx)
    r.raid, r.boss = raid, boss
    r.sourceName = boss.name
    r.sourceKey = "b" .. tostring(boss.encounterID)
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

-- One dungeon at a key other than the selected one: the IO tab's planned
-- keys. Judged at the highest key that still raises the drop (gear stops
-- improving past it), cached until the next evaluation. In combat, or before
-- the gear has been scanned, the selected key's result stands in.
local dropsAtKey = {}
function ns:DropsAtKey(d, keyLevel)
    if not d or not self.db then return nil end
    local maxKey = self:MaxUsefulKey() or 10
    keyLevel = math.max(2, math.min(maxKey, math.floor(tonumber(keyLevel) or maxKey)))
    if keyLevel == (self.db.targetKey or 10) then return self:ResultForDungeon(d) end
    local key = d.challengeMapID .. ":" .. keyLevel
    local r = dropsAtKey[key]
    if r then return r end
    if InCombatLockdown() or not self.gearScanned then return self:ResultForDungeon(d) end
    r = self:EvaluateDungeonAt(d, keyLevel)
    dropsAtKey[key] = r
    return r
end

function ns:Evaluate()
    wipe(dropsAtKey)
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
        return a.dungeon.name < b.dungeon.name
    end)

    self.results = results
    self.dropCtx = ctx
    self.resultByMapID = {}
    for _, r in ipairs(results) do self.resultByMapID[r.dungeon.challengeMapID] = r end

    -- raid bosses at the chosen difficulty, grouped by raid
    local diffKey = self:GetRaidDifficulty()
    local rmode = self.db.raidSort or "boss"
    local raidResults, byEncounter = {}, {}
    for _, raid in ipairs(self:GetRaids()) do
        local group = { raid = raid, bosses = {} }
        for _, boss in ipairs(raid.bosses) do
            local r = self:EvaluateBoss(raid, boss, diffKey)
            table.insert(group.bosses, r)
            byEncounter[boss.encounterID] = r
        end
        if rmode ~= "boss" then
            table.sort(group.bosses, function(a, b)
                if rmode == "wanted" and a.wanted ~= b.wanted then return a.wanted > b.wanted end
                if a.upgrades ~= b.upgrades then return a.upgrades > b.upgrades end
                if a.wanted ~= b.wanted then return a.wanted > b.wanted end
                return a.boss.index < b.boss.index
            end)
        end
        table.insert(raidResults, group)
    end
    self.raidResults = raidResults
    self.resultByEncounter = byEncounter
    self:Fire("RESULTS_UPDATED")
    return results
end

-- The results the Gear tab draws from: dungeons, raid bosses or both.
function ns:GearResults()
    local source = self.db and self.db.gearSource or "both"
    local list = {}
    if source ~= "raid" then
        for _, r in ipairs(self.results or {}) do list[#list + 1] = r end
    end
    if source ~= "mplus" then
        for _, group in ipairs(self.raidResults or {}) do
            for _, r in ipairs(group.bosses) do list[#list + 1] = r end
        end
    end
    return list
end

-- Per-slot summary for the Gear tab: best upgrade class available anywhere
-- among the sources it lists, plus the wanted items and Voidcore targets.
function ns:SlotSummary()
    local summary = {}
    for _, s in ipairs(self.SLOTS) do
        summary[s.id] = { best = NONE, sources = {}, count = 0, wanted = {}, voidcore = {} }
    end
    for _, r in ipairs(self:GearResults()) do
        for _, top in ipairs(r.items) do
        for _, eval in ipairs(top.pieces or { top }) do
            if eval.slotID then
                local e = summary[eval.slotID]
                if self:GetItemState(eval.item.itemID) == "want" then
                    table.insert(e.wanted, { eval = eval, source = r.sourceName, ctx = r.ctx })
                end
                if self:IsVoidcoreTarget(eval.item.itemID) then
                    table.insert(e.voidcore, { eval = eval, source = r.sourceName, ctx = r.ctx })
                end
                if self:CountsAsUpgrade(eval) then
                    e.count = e.count + 1
                    if eval.class > e.best then e.best = eval.class end
                    local src = e.sources[r.sourceKey]
                    if not src then src = { name = r.sourceName, n = 0 }; e.sources[r.sourceKey] = src end
                    src.n = src.n + 1
                    -- best drop: largest fully-upgraded gain, then immediate gain
                    local gain = (eval.potentialGain or 0) * 1000 + (eval.gain or 0)
                    if eval.class ~= WANT and (not e.bestDrop or gain > e.bestDropScore) then
                        e.bestDrop, e.bestDropScore = { eval = eval, source = r.sourceName }, gain
                    end
                end
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
    -- A pass reads every drop's stats and links; nothing it shows matters
    -- mid-fight. Once, when combat ends.
    if InCombatLockdown() then ns.evaluatePending = true; return end
    if not ns.gearScanned then ns:ScanGear() end
    ns:Schedule("evaluate", 0.1, function() ns:Evaluate() end)
end

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if ns.evaluatePending then
        ns.evaluatePending = nil
        Reevaluate()
    end
end)

-------------------------------------------------------------------------------
-- Item data: a link answers nothing (no item level, no stats) until the
-- client holds the item, and after a login the cached loot is judged before
-- it does. Each missing item is asked for once; when the answers arrive the
-- pass runs again. An item that fails to load is not asked again.
-------------------------------------------------------------------------------
local itemRequests = {}     -- itemID -> true while asked and unanswered, false after
ns.itemRequests = itemRequests

function ns:NeedItemData(itemID)
    if not itemID or itemRequests[itemID] ~= nil then return end
    if not (C_Item and C_Item.IsItemDataCachedByID and C_Item.RequestLoadItemDataByID) then return end
    if C_Item.IsItemDataCachedByID(itemID) then return end
    itemRequests[itemID] = true
    C_Item.RequestLoadItemDataByID(itemID)
end

ns:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(itemID, success)
    if itemRequests[itemID] ~= true then return end
    itemRequests[itemID] = false
    if success then ns:Schedule("itemData", 0.5, Reevaluate) end
end)

ns:On("GEAR_UPDATED", Reevaluate)
ns:On("LOOT_UPDATED", Reevaluate)
ns:On("SETTINGS_CHANGED", Reevaluate)
ns:On("TRACKS_CHANGED", Reevaluate)
ns:On("DUNGEONS_UPDATED", Reevaluate)

-- Selector: +2 .. +maxKey (end-of-dungeon gear stops improving past it).
function ns:SetTargetKey(n)
    n = tonumber(n)
    if not n then return end
    local maxKey = self:MaxUsefulKey() or 10
    self.db.targetKey = math.max(2, math.min(maxKey, math.floor(n)))
    self:ClearRewardCache()
    self:Fire("SETTINGS_CHANGED")
end

function ns:StepTargetKey(delta)
    self:SetTargetKey((self.db.targetKey or 10) + delta)
end

function ns:TargetLabel()
    return "+" .. tostring(self.db.targetKey or 10)
end
