-- Slot Filler: which drops are upgrades, and the ranking of dungeons and bosses.
--
-- Every item is judged as the direct drop: end of dungeon at the chosen key
-- level, or off a raid boss at the chosen difficulty. That is what the
-- lists and counts show. It is also judged as a Nebulous Voidcore bonus
-- roll, which the game awards at the Great Vault level (a key's vault item
-- level, +10 and up: Myth 1/6; a raid boss one upgrade track above the
-- difficulty); that verdict is only shown in tooltips while Shift is held.
-- Which drops to spend a Voidcore on is the player's call: the Voidcore
-- targets, a second star next to the wanted list.
local _, ns = ...

local NONE, STAT, ILVL, TRACK, WANT = ns.UPGRADE_NONE, ns.UPGRADE_STAT, ns.UPGRADE_ILVL, ns.UPGRADE_TRACK, ns.UPGRADE_WANT

-------------------------------------------------------------------------------
-- Drop contexts: the level a drop (and its Voidcore roll) arrives at
-------------------------------------------------------------------------------
local function Level(ilvl, source)
    if not ilvl then return nil end
    local track, step = ns:TrackForIlvl(ilvl)
    return { ilvl = ilvl, source = source, track = track, step = step, potential = track and math.max(track.max, ilvl) or ilvl }
end

local function AddStats(ctx)
    ctx.statPrio, ctx.statPrioSource = ns:GetStatPriority()
    ctx.statWeights = ns:GetStatWeights()
    return ctx
end

-- A dungeon at a key level.
function ns:GetDropContext(keyLevel)
    keyLevel = keyLevel or self.db.targetKey
    local ilvl, source = self:RewardIlvl(keyLevel)
    local ctx = Level(ilvl, source) or { source = source }
    ctx.key = keyLevel
    ctx.voidcore = Level(self:VaultIlvl(keyLevel))
    return AddStats(ctx)
end

function ns:GetRaidDifficulty()
    local key = self.db and self.db.raidDifficulty
    return self.RAID_DIFF_BY_KEY[key] and key or "heroic"
end

function ns:SetRaidDifficulty(key)
    if not self.RAID_DIFF_BY_KEY[key] or not self.db then return end
    self.db.raidDifficulty = key
    self:Fire("SETTINGS_CHANGED")
end

-- A raid boss at a difficulty. The direct drop is the difficulty's track;
-- later bosses drop higher within it. The level comes from the season table
-- shipped with the addon, else the boss's journal loot: the level remembered
-- at scan time, else the link's (right only while the journal holds the
-- loot), else the track's first step. The Voidcore roll (and the vault) is
-- one track up at its first step; on Mythic it is the fully upgraded item,
-- or the drop itself where that is already past the top of the track.
function ns:GetRaidContext(diffKey, boss, raid)
    local def = self.RAID_DIFF_BY_KEY[diffKey] or self.RAID_DIFF_BY_KEY.heroic
    local track = self.trackByKey[def.track]
    raid = raid or (boss and self:RaidOfBoss(boss))
    local ilvl, source
    if track and boss then
        ilvl = self:ShippedBossLevel(raid, boss, def.key, track)
        if ilvl then source = "season" end
    end
    if track and not ilvl and boss then
        for _, item in ipairs(self:GetBossLoot(boss, def.key) or {}) do
            local l = item.ilvl or self.ItemLevelOf(item.link)
            if not l then self:NeedItemData(item.itemID) end
            if l and l >= track.min and (l <= track.max or def.track == "Myth") and (not ilvl or l > ilvl) then ilvl = l end
        end
        if ilvl then source = "journal" end
    end
    if not ilvl and track then ilvl, source = track.min, "track" end
    local ctx = Level(ilvl, source) or { source = source }
    ctx.raid, ctx.difficulty, ctx.difficultyName = true, def.key, self:RaidDifficultyName(raid, def.key)
    if track then
        local up
        for i, t in ipairs(self.tracks) do
            if t == track then up = self.tracks[i + 1] end
        end
        ctx.voidcore = Level(up and up.min or math.max(track.max, ilvl or 0), source)
    end
    return AddStats(ctx)
end

-------------------------------------------------------------------------------
-- One drop against one equipped item
-------------------------------------------------------------------------------
-- `owned`: the best copy of the item you hold, if any. A copy that already
-- reaches the drop's fully upgraded level makes the drop redundant; a
-- weaker copy leaves it an upgrade (over the copy too).
local function Classify(g, level, itemState, slotState, owned)
    local r = { gain = level.ilvl - (g.ilvl or 0), potentialGain = (level.potential or level.ilvl) - (g.potential or 0) }
    if itemState == "exclude" then
        r.class, r.reason = NONE, "excluded"
    elseif owned and (level.potential or level.ilvl) <= (owned.potential or 0) then
        r.class, r.reason = NONE, "owned"
    elseif itemState == "want" or slotState == "want" then
        r.class = WANT
    elseif g.empty then
        r.class, r.reason = TRACK, "empty slot"
    elseif r.potentialGain > 0 then
        r.class = TRACK
    elseif r.gain > 0 then
        r.class = ILVL
    else
        r.class = NONE
    end
    return r
end

-- Match level: a drop (or a roll) as it would be after the free upgrade to
-- the slot's level `mark`: the highest step of its own track at or under
-- the mark, never below the level itself. Returns `level` itself when
-- nothing changes.
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
    return { ilvl = ilvl, step = step, track = level.track, potential = level.potential, source = level.source, key = level.key, from = level.ilvl, mark = mark }
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

-- The equipped slot a drop would replace: a Want slot first, otherwise the
-- weakest candidate by fully upgraded level, then item level; nil when every
-- candidate is skipped.
local function TargetSlot(self, candidates)
    local best, bestScore
    for _, slotID in ipairs(candidates) do
        local state = self:GetSlotState(slotID)
        local g = self.gear[slotID] or { empty = true, ilvl = 0, potential = 0 }
        local score = (state == "want" and -1) or (state ~= "skip" and (g.potential or 0) * 1000 + (g.ilvl or 0)) or nil
        if score and (not bestScore or score < bestScore) then best, bestScore = slotID, score end
    end
    return best
end

function ns:EvaluateItem(item, ctx)
    local eval = { item = item, class = NONE }
    if not ctx.ilvl then
        eval.reason = "unknown drop item level"
        return eval
    end
    local candidates = self:CandidateSlotsFor(item.equipLoc)
    if not candidates then
        eval.reason = "not equippable"
        return eval
    end
    local best = TargetSlot(self, candidates)
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
    local slotState, itemState = self:GetSlotState(best), self:GetItemState(item.itemID)
    -- already yours: equipped, in the bags or a bank (the best copy), or
    -- already catalyzed into the set piece worn in this slot
    local owned = self:OwnedCopy(item.itemID) or self:CatalyzedCopy(eval, g)
    eval.owned = owned

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
        dropLevel, vcLevel = Matched(ctx, mark), Matched(ctx.voidcore, mark)
        if dropLevel ~= ctx then eval.matched = dropLevel end
        if vcLevel ~= ctx.voidcore then eval.voidcoreMatched = vcLevel end
    end

    local drop = Classify(g, dropLevel, itemState, slotState, owned)
    eval.class, eval.reason, eval.gain, eval.potentialGain = drop.class, drop.reason, drop.gain, drop.potentialGain
    -- no roll verdict for what a bonus roll cannot award (the omni token)
    if vcLevel and vcLevel.ilvl and not item.noRoll then
        eval.voidcore = Classify(g, vcLevel, itemState, slotState, owned)
    end
    -- weighted values (Pawn scale): the drop at its (matched) level vs the equipped item
    local scale = ctx.statWeights
    if scale then
        local equippedValue = g.empty and 0 or self:ItemValue(g.link, scale)
        eval.equippedValue = equippedValue
        local link, kind = self:LinkForContext(item, eval.matched or ctx)
        if kind == "exact" then
            eval.value = self:ItemValue(link, scale)
            if eval.value and equippedValue then eval.valueGain = eval.value - equippedValue end
        end
        if eval.voidcore then
            local vlink, vkind = self:LinkForContext(item, { ilvl = vcLevel.ilvl, step = vcLevel.step, track = vcLevel.track, key = ctx.key, isVoidcore = true })
            if vkind == "exact" then
                eval.voidcore.value = self:ItemValue(vlink, scale)
                if eval.voidcore.value and equippedValue then eval.voidcore.valueGain = eval.voidcore.value - equippedValue end
            end
        end
    end
    -- Match level: at the same level, better stats make it an upgrade
    if self.db.matchLevel then
        if StatUpgrade(eval, eval) then eval.class = STAT end
        if eval.voidcore and StatUpgrade(eval, eval.voidcore) then eval.voidcore.class = STAT end
    end
    return eval
end

-- Whether a verdict counts in the Drops column.
function ns:CountsAsUpgrade(eval)
    if eval.class == TRACK or eval.class == WANT then return true end
    return (eval.class == ILVL or eval.class == STAT) and self.db.countIlvlUpgrades or false
end

-------------------------------------------------------------------------------
-- A loot table against a drop context
-------------------------------------------------------------------------------
local slotOrder = {}
for i, s in ipairs(ns.SLOTS) do slotOrder[s.id] = i end

-- Class first, then slot order; same slot: by weighted value when a scale is
-- imported, else the drop whose stats sit higher in the priority first.
local function ItemSort(a, b)
    if a.class ~= b.class then return a.class > b.class end
    local sa, sb = slotOrder[a.slotID or 0] or 99, slotOrder[b.slotID or 0] or 99
    if sa ~= sb then return sa < sb end
    if a.value and b.value and a.value ~= b.value then return a.value > b.value end
    local fa, fb = a.fit or 0.5, b.fit or 0.5
    if fa ~= fb then return fa > fb end
    return (a.item.name or "") < (b.item.name or "")
end

-- A set piece read from the journal's Class Sets tab carries no name or
-- link until the client holds the item; filled in once it does.
function ns:FillItemInfo(item)
    if not item or item.name or not item.itemID then return end
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

-- One loot table (a dungeon's or a boss's) against one drop context.
local function EvaluateLoot(self, loot, ctx)
    local r = {
        ctx = ctx, items = {}, total = 0, chance = 0,
        upgrades = 0, trackUpgrades = 0, slots = {}, slotCount = 0,   -- direct drop upgrades
        wanted = 0, wantedItems = {},                                  -- wanted list items that drop here
        voidcore = 0, voidcoreItems = {},                              -- Voidcore targets that drop here
        scanned = loot ~= nil,
    }
    for _, item in ipairs(loot or {}) do
        r.total = r.total + 1
        self:NeedItemData(item.itemID)
        local eval = EvaluateEntry(self, item, ctx)
        local itemID = eval.item.itemID
        r.items[#r.items + 1] = eval
        if self:GetItemState(itemID) == "want" then
            r.wanted = r.wanted + 1
            r.wantedItems[#r.wantedItems + 1] = eval
        end
        if self:IsVoidcoreTarget(itemID) and not eval.item.noRoll then
            r.voidcore = r.voidcore + 1
            r.voidcoreItems[#r.voidcoreItems + 1] = eval
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
    if r.total > 0 then r.chance = r.upgrades / r.total end
    return r
end

function ns:EvaluateDungeon(d, ctx)
    local r = EvaluateLoot(self, self:GetDungeonLoot(d.challengeMapID), ctx)
    r.dungeon, r.sourceName, r.sourceKey = d, d.name, "d" .. d.challengeMapID
    return r
end

function ns:EvaluateBoss(raid, boss, diffKey)
    local r = EvaluateLoot(self, self:GetBossLoot(boss, diffKey), self:GetRaidContext(diffKey, boss, raid))
    r.raid, r.boss, r.sourceName, r.sourceKey = raid, boss, boss.name, "b" .. boss.encounterID
    return r
end

-- One dungeon at a specific key level (keystone tooltips).
function ns:EvaluateDungeonAt(d, keyLevel)
    return self:EvaluateDungeon(d, self:GetDropContext(keyLevel))
end

-- One dungeon at a key other than the selected one: the IO tab's planned
-- keys. Judged at the highest key that still raises the drop (gear stops
-- improving past it), cached until the next evaluation. In combat, or before
-- the gear has been scanned, the selected key's result stands in.
local dropsAtKey = {}
function ns:DropsAtKey(d, keyLevel)
    if not d or not self.db then return nil end
    local maxKey = self:MaxUsefulKey()
    keyLevel = math.max(2, math.min(maxKey, math.floor(tonumber(keyLevel) or maxKey)))
    if keyLevel == self.db.targetKey then return self:ResultForDungeon(d) end
    local key = d.challengeMapID .. ":" .. keyLevel
    if dropsAtKey[key] then return dropsAtKey[key] end
    if InCombatLockdown() or not self.gearScanned then return self:ResultForDungeon(d) end
    dropsAtKey[key] = self:EvaluateDungeonAt(d, keyLevel)
    return dropsAtKey[key]
end

-------------------------------------------------------------------------------
-- The full pass: every dungeon at the selected key, every boss at the Raid
-- tab's difficulty
-------------------------------------------------------------------------------
function ns:Evaluate()
    wipe(dropsAtKey)
    self:ClearOwnedCache()
    local ctx = self:GetDropContext()
    local results = {}
    for _, d in ipairs(self.dungeons) do results[#results + 1] = self:EvaluateDungeon(d, ctx) end
    local mode = self.db.sortMode
    table.sort(results, function(a, b)
        if mode == "name" then return a.dungeon.name < b.dungeon.name end
        if mode == "wanted" and a.wanted ~= b.wanted then return a.wanted > b.wanted end
        if a.upgrades ~= b.upgrades then return a.upgrades > b.upgrades end
        if a.wanted ~= b.wanted then return a.wanted > b.wanted end
        if a.chance ~= b.chance then return a.chance > b.chance end
        return a.dungeon.name < b.dungeon.name
    end)
    self.results, self.dropCtx, self.resultByMapID = results, ctx, {}
    for _, r in ipairs(results) do self.resultByMapID[r.dungeon.challengeMapID] = r end

    local diffKey, rmode = self:GetRaidDifficulty(), self.db.raidSort
    self.raidResults, self.resultByEncounter = {}, {}
    for _, raid in ipairs(self:GetRaids()) do
        local group = { raid = raid, bosses = {} }
        for _, boss in ipairs(raid.bosses) do
            local r = self:EvaluateBoss(raid, boss, diffKey)
            group.bosses[#group.bosses + 1] = r
            self.resultByEncounter[boss.encounterID] = r
        end
        if rmode ~= "boss" then
            table.sort(group.bosses, function(a, b)
                if rmode == "wanted" and a.wanted ~= b.wanted then return a.wanted > b.wanted end
                if a.upgrades ~= b.upgrades then return a.upgrades > b.upgrades end
                if a.wanted ~= b.wanted then return a.wanted > b.wanted end
                return a.boss.index < b.boss.index
            end)
        end
        self.raidResults[#self.raidResults + 1] = group
    end
    self:Fire("RESULTS_UPDATED")
    return results
end

function ns:ResultForDungeon(d)
    return d and self.resultByMapID and self.resultByMapID[d.challengeMapID] or nil
end

-- The results the Gear tab draws from: dungeons, raid bosses or both.
function ns:GearResults()
    local source = self.db.gearSource
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

-- Per Gear row (a slot, or a ring or trinket pair): the best upgrade class
-- among the sources it lists, the count per source, the best drop, and the
-- wanted items and Voidcore targets.
function ns:SlotSummary()
    local summary = {}
    for _, s in ipairs(self.SLOTS) do
        summary[s.id] = { best = NONE, sources = {}, count = 0, wanted = {}, voidcore = {} }
    end
    for _, r in ipairs(self:GearResults()) do
        for _, top in ipairs(r.items) do
            for _, eval in ipairs(top.pieces or { top }) do
                local e = eval.slotID and summary[self.PAIR_ROW[eval.slotID] or eval.slotID]
                if e then
                    local id = eval.item.itemID
                    if self:GetItemState(id) == "want" then e.wanted[#e.wanted + 1] = { eval = eval, source = r.sourceName, ctx = r.ctx } end
                    if self:IsVoidcoreTarget(id) then e.voidcore[#e.voidcore + 1] = { eval = eval, source = r.sourceName, ctx = r.ctx } end
                    if self:CountsAsUpgrade(eval) then
                        e.count = e.count + 1
                        if eval.class > e.best then e.best = eval.class end
                        local src = e.sources[r.sourceKey]
                        if not src then src = { name = r.sourceName, n = 0 }; e.sources[r.sourceKey] = src end
                        src.n = src.n + 1
                        -- best drop: largest fully upgraded gain, then immediate gain
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

-------------------------------------------------------------------------------
-- Re-evaluate whenever an input changes
-------------------------------------------------------------------------------
local function Reevaluate()
    if not ns.db or not ns.dungeonsBuilt then return end
    -- a pass reads every drop's stats and links; nothing it shows matters
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

for _, message in ipairs({ "GEAR_UPDATED", "BAGS_UPDATED", "LOOT_UPDATED", "SETTINGS_CHANGED", "TRACKS_CHANGED", "DUNGEONS_UPDATED" }) do
    ns:On(message, Reevaluate)
end

-------------------------------------------------------------------------------
-- Item data: a link answers nothing (no item level, no stats) until the
-- client holds the item, and after a login the cached loot is judged before
-- it does. Each missing item is asked for once; when the answers arrive the
-- pass runs again. An item that fails to load is not asked again.
-------------------------------------------------------------------------------
local itemRequests = {}     -- itemID -> true while asked and unanswered, false after
ns.itemRequests = itemRequests

function ns:NeedItemData(itemID)
    if not itemID or itemRequests[itemID] ~= nil or C_Item.IsItemDataCachedByID(itemID) then return end
    itemRequests[itemID] = true
    C_Item.RequestLoadItemDataByID(itemID)
end

ns:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(itemID, success)
    if itemRequests[itemID] ~= true then return end
    itemRequests[itemID] = false
    if success then ns:Schedule("itemData", 0.5, Reevaluate) end
end)

-------------------------------------------------------------------------------
-- The key selector: +2 .. the last key that still raises the drop
-------------------------------------------------------------------------------
function ns:SetTargetKey(n)
    n = tonumber(n)
    if not n then return end
    self.db.targetKey = math.max(2, math.min(self:MaxUsefulKey(), math.floor(n)))
    self:ClearRewardCache()
    self:Fire("SETTINGS_CHANGED")
end

function ns:StepTargetKey(delta)
    self:SetTargetKey(self.db.targetKey + delta)
end
