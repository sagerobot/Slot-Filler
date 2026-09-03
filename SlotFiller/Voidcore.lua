-- Slot Filler: where to spend a Nebulous Voidcore (the Voidcore tab and a
-- line on the bonus roll window).
--
-- A pool is what a bonus roll can still give the current loot spec from
-- one source at one difficulty ("Items may be received once per difficulty
-- level until all potential items for your current specialization have
-- been transmuted"). It is built from the loot the addon already knows,
-- less the omni token and less the rolls received, which are recorded from
-- the roll result (and can be marked by hand). Every source also has a
-- Nebulous Voidcache item whose tooltip lists the pool as the game sees
-- it; the client fills that list in only while the Adventure Guide or a
-- roll prompt is open, so it is read then and used to correct the rolled
-- set. Each item's roll verdict comes from the evaluation.
local _, ns = ...

-- Enum.ItemCreationContext: the difficulty the tooltip answers for
local RAID_CONTEXT = { normal = 3, lfr = 4, heroic = 5, mythic = 6 }
local CONTEXT_DIFF = { [3] = "normal", [4] = "lfr", [5] = "heroic", [6] = "mythic" }
local MPLUS_CONTEXT = 16
local MAX_TRIES = 8       -- reads of a tooltip before the journal loot stands in
local READS_PER_STEP = 2  -- tooltips read per tick: the client fills them in between
local STEP = 0.25

local pools = {}          -- "cache:context:level" -> { items = { [name] = true }, count, ready, tries, gaveUp }
ns.voidcorePools = pools
local counters = { lootData = 0, tooltipData = 0 }   -- events seen since login, for /sf voidcore

local function Voidcache()
    local d = ns:GetSeasonData()
    return d and d.voidcache or nil
end

function ns:VoidcacheForDungeon(d)
    local vc = Voidcache()
    return vc and d and vc.dungeons and vc.dungeons[d.challengeMapID] or nil
end

function ns:VoidcacheForBoss(boss)
    local vc = Voidcache()
    local key = boss and self:NormalizeName(boss.name)
    return vc and key and vc.bosses and vc.bosses[key] or nil
end

function ns:VoidcoreCurrencyID()
    local vc = Voidcache()
    return vc and vc.currency or nil
end

-- Voidcores in the bag, or nil when the client cannot say.
function ns:VoidcoreCount()
    local id = self:VoidcoreCurrencyID()
    if not id or not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
    if not ok or type(info) ~= "table" then return nil end
    local q = info.quantity
    if type(q) == "number" and not self.issecret(q) then return q end
    return nil
end

local function StripColor(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Leading spaces (ASCII or no-break) skipped; returns the rest and how far.
local SPACES = { " ", "\t", "\194\160" }
local function SkipSpaces(s, i)
    local moved = true
    while moved do
        moved = false
        for _, sp in ipairs(SPACES) do
            if s:sub(i, i + #sp - 1) == sp then i = i + #sp; moved = true end
        end
    end
    return i
end

-- The list marker the client puts before each item: a hyphen, an en or em
-- dash, or a bullet.
local MARKERS = { "-", "\226\128\147", "\226\128\148", "\226\128\162" }

-- The item name on a "- name" line, or nil for any other line.
local function ListedName(text)
    text = StripColor(text)
    local i = SkipSpaces(text, 1)
    local marker
    for _, m in ipairs(MARKERS) do
        if text:sub(i, i + #m - 1) == m then marker = m; break end
    end
    if not marker then return nil end
    i = SkipSpaces(text, i + #marker)
    local name = text:sub(i):gsub("%s+$", "")
    if name == "" then return nil end
    return name
end
ns.VoidcacheListedName = ListedName

-- One Voidcache tooltip: the listed items, the tooltip's line count and
-- the read's dataInstanceID (the client resolves the list later and says
-- so with TOOLTIP_DATA_UPDATE for that id). nil while nothing is listed.
-- Marker lines first; failing that, the non-empty lines after a header
-- ending in ":" ("Contains one of the following items:").
local function ReadPool(cacheID, context, level)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil, 0 end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, cacheID, nil, context, level)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil, 0 end
    local instance = data.dataInstanceID
    local items, count = {}, 0
    local function Add(name)
        local key = ns:NormalizeName(name)
        if key and key ~= "" and not items[key] then
            items[key] = true
            count = count + 1
        end
    end
    for _, line in ipairs(data.lines) do
        local text = line and line.leftText
        if type(text) == "string" then
            local name = ListedName(text)
            if name then Add(name) end
        end
    end
    if count == 0 then
        local afterHeader = false
        for _, line in ipairs(data.lines) do
            local text = line and line.leftText
            if type(text) == "string" then
                local clean = StripColor(text):gsub("^%s+", ""):gsub("%s+$", "")
                if afterHeader then
                    if clean == "" then break end
                    Add(clean)
                elseif clean:sub(-1) == ":" then
                    afterHeader = true
                end
            end
        end
    end
    if count == 0 then return nil, #data.lines, instance end
    return { items = items, count = count }, #data.lines, instance
end

-- Reading is paced: a few tooltips per tick, and a pool is accepted once
-- two reads in a row list the same number of items (the client fills a
-- tooltip in over several frames, and reading many at once returns most
-- of them empty). The client builds the list from the journal's loot for
-- that source, which nothing has loaded after a login, so the source's
-- journal loot is asked for once before its first read. A pool that lists
-- nothing after MAX_TRIES reads is shown as empty but read again the next
-- time the tab opens.
local queue, queued = {}, {}
local awaiting = {}       -- dataInstanceID -> queue entry whose read the client is still resolving
local ReadNext

local function Accept(e, p, read)
    p.items, p.count, p.ready = read.items, read.count, true
    queued[e.key] = nil
end

-- The client resolved a read: the same tooltip, read again right now,
-- carries the list (a later read starts a new lookup instead).
local function OnTooltipData(instance)
    local e = instance and awaiting[instance]
    if not e then return end
    awaiting[instance] = nil
    local p = pools[e.key]
    if not p or (p.ready and not p.gaveUp) then return end
    local read, lines, again = ReadPool(e.cacheID, e.context, e.level)
    p.tries = p.tries + 1
    p.lastLines = lines
    p.resolved = (p.resolved or 0) + 1
    if read then
        Accept(e, p, read)
        p.gaveUp = nil
        ns:Fire("VOIDCORE_POOLS_UPDATED")
    elseif again then
        awaiting[again] = e
    end
end

local function Enqueue(key, cacheID, context, level, source)
    if queued[key] then return end
    queued[key] = true
    queue[#queue + 1] = { key = key, cacheID = cacheID, context = context, level = level, source = source }
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, cacheID) end
    ns:Schedule("voidcoreRead", STEP, ReadNext)
end

ReadNext = function()
    if #queue == 0 then return end
    if InCombatLockdown() then
        ns:Schedule("voidcoreRead", 1, ReadNext)
        return
    end
    local changed = false
    for _ = 1, math.min(READS_PER_STEP, #queue) do
        local e = table.remove(queue, 1)
        local p = pools[e.key]
        if p and not p.ready then
            -- the journal must hold this source's loot first: ask until it does
            -- (an open Adventure Guide already holds what it shows)
            if not e.touched and EncounterJournal and EncounterJournal:IsShown() then e.touched = true end
            if not e.touched then
                local asked, n, why = ns:TouchJournalLoot(e.source, true)
                p.touches = (p.touches or 0) + 1
                p.journalLoot, p.touchNote = n, why
                e.touched = asked and n > 0
            end
            local read, lines, instance = ReadPool(e.cacheID, e.context, e.level)
            p.tries = p.tries + 1
            p.lastLines = lines
            if instance and not read then awaiting[instance] = e end
            local count = read and read.count or 0
            if read and p.lastCount == count then
                Accept(e, p, read)
                changed = true
            elseif p.tries >= MAX_TRIES then
                p.ready, p.gaveUp = true, true
                queued[e.key] = nil
                changed = true
            else
                p.lastCount = count
                queue[#queue + 1] = e
            end
        else
            queued[e.key] = nil
        end
    end
    if #queue > 0 then
        ns:Schedule("voidcoreRead", STEP, ReadNext)
    else
        ns:RestoreJournalAfterTouch()
    end
    if changed then ns:Fire("VOIDCORE_POOLS_UPDATED") end
end

-- The pool for one cache at one difficulty (a key level for dungeons):
-- what is known so far; not ready until read.
function ns:VoidcorePool(cacheID, context, level, source)
    local key = cacheID .. ":" .. context .. ":" .. (level or 0)
    local p = pools[key]
    if not p then
        p = { items = {}, count = 0, ready = false, tries = 0 }
        pools[key] = p
    end
    if not p.ready then Enqueue(key, cacheID, context, level, source) end
    return p
end

function ns:ClearVoidcorePools()
    wipe(pools); wipe(queue); wipe(queued); wipe(awaiting)
    self:RestoreJournalAfterTouch()
end

-- Pools the client never listed are tried again (when the tab opens).
function ns:RetryEmptyVoidcorePools()
    for key, p in pairs(pools) do
        if p.gaveUp then pools[key] = nil end
    end
end

-------------------------------------------------------------------------------
-- Sources: each dungeon at the selected key and each boss at the Raid
-- tab's difficulty, with what its pool still holds for you
-------------------------------------------------------------------------------
local function NameOf(item)
    return item.name or (item.link and item.link:match("%[(.-)%]")) or ""
end

-------------------------------------------------------------------------------
-- The class set and the Catalyst
-------------------------------------------------------------------------------
local TIER_SLOTS = { [1] = true, [3] = true, [5] = true, [10] = true, [7] = true }

function ns:IsTierSlot(slotID)
    return slotID and TIER_SLOTS[slotID] or false
end

-- Catalyst charges in hand (Venomblight Manaflux), or nil when unknown.
function ns:CatalystCharges()
    local data = self:GetSeasonData()
    local id = data and data.catalystCurrency
    if not id or not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
    if not ok or type(info) ~= "table" then return nil end
    local q = info.quantity
    if type(q) == "number" and not self.issecret(q) then return q end
    return nil
end

local function SetPieceIDs(self)
    local set = self.loot and self.loot.classSet
    local ids, total = {}, 0
    for _, p in pairs(set and set.pieces or {}) do
        ids[p.itemID] = true
        total = total + 1
    end
    return ids, total
end

-- Set pieces worn (the set the journal names for the class), the next set
-- bonus and how many pieces it still needs, and the Catalyst charges.
function ns:SetProgress()
    local ids, total = SetPieceIDs(self)
    local worn = 0
    for _, s in ipairs(self.SLOTS) do
        local g = self.gear and self.gear[s.id]
        if g and not g.empty and g.itemID and ids[g.itemID] then worn = worn + 1 end
    end
    local nextBonus = (worn < 2 and 2) or (worn < 4 and 4) or nil
    return { worn = worn, total = total, known = total > 0, nextBonus = nextBonus,
        need = nextBonus and (nextBonus - worn) or 0, charges = self:CatalystCharges() }
end

-- A drop the Catalyst could turn into a set piece: a tier slot, not a set
-- piece already.
function ns:IsCatalystCandidate(eval)
    if not eval or not eval.slotID or not TIER_SLOTS[eval.slotID] then return false end
    local ids = SetPieceIDs(self)
    return not ids[eval.item.itemID]
end

function ns:IsSetPiece(itemID)
    return itemID ~= nil and SetPieceIDs(self)[itemID] == true
end

local SLOT_EQUIPLOC = { [1] = { "INVTYPE_HEAD" }, [3] = { "INVTYPE_SHOULDER" }, [5] = { "INVTYPE_CHEST", "INVTYPE_ROBE" }, [10] = { "INVTYPE_HAND" }, [7] = { "INVTYPE_LEGS" } }

-- The class set's piece for a tier slot, or nil.
function ns:SetPieceForSlot(slotID)
    local set = self.loot and self.loot.classSet
    if not set or not set.pieces then return nil end
    for _, inv in ipairs(SLOT_EQUIPLOC[slotID or 0] or {}) do
        if set.pieces[inv] then return set.pieces[inv] end
    end
    return nil
end

-- The set piece this drop has already become: worn in its slot, or a copy
-- of the slot's set piece you hold, with this drop's stats (the Catalyst
-- keeps them). An owned-copy entry flagged catalyzed, or nil.
function ns:CatalyzedCopy(eval, worn)
    if not eval or not eval.stats or not self:IsCatalystCandidate(eval) then return nil end
    local candidates = {}
    if worn and not worn.empty and worn.link and self:IsSetPiece(worn.itemID) then candidates[#candidates + 1] = worn end
    local piece = self:SetPieceForSlot(eval.slotID)
    if piece then
        local copy = self:OwnedCopy(piece.itemID)
        if copy and copy.link then candidates[#candidates + 1] = copy end
    end
    for _, c in ipairs(candidates) do
        if self:StatsAlike(eval.stats, self:ItemStats(c.link)) then
            local entry = {}
            for k, v in pairs(c) do entry[k] = v end
            entry.catalyzed = true
            entry.where = entry.where or "equipped"
            entry.name = entry.name or (entry.link and entry.link:match("%[(.-)%]")) or nil
            return entry
        end
    end
    return nil
end

-- "Set 2/5, 4-piece needs 2, 1 charge" for a status line; nil without a set.
function ns:SetProgressText()
    local p = self:SetProgress()
    if not p.known then return nil end
    local text = string.format("Set %d/%d", p.worn, p.total)
    if p.nextBonus then
        text = text .. string.format(", %d-piece needs %d", p.nextBonus, p.need)
    else
        text = text .. ", 4-piece done"
    end
    if p.charges then text = text .. string.format(", %d Catalyst charge%s", p.charges, p.charges == 1 and "" or "s") end
    return text
end

-------------------------------------------------------------------------------
-- What one roll result is worth
-------------------------------------------------------------------------------
-- Item levels a roll gains, weighted by the slot's stat budget (a weapon
-- or trinket outweighs a wrist), and multiplied for what is chased: a
-- Voidcore target most, then a wanted item, then a Want slot. Second
-- return: whether the roll would be usable at all.
local SLOT_BUDGET = { [1] = 1, [5] = 1, [7] = 1, [3] = 0.75, [10] = 0.75, [6] = 0.75, [8] = 0.75, [2] = 0.75,
    [11] = 0.75, [12] = 0.75, [9] = 0.56, [15] = 0.56, [13] = 1.25, [14] = 1.25, [16] = 1, [17] = 1 }
local TWO_HAND = { INVTYPE_2HWEAPON = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true }

-- An ideal roll: an upgrade whose stats fit as well. With a weight
-- profile, a weighted gain over the piece it replaces; without one, a stat
-- match of at least 75%, or better than that piece's. An item with no
-- secondaries to judge (a weapon, most trinkets) counts on level alone.
local IDEAL_FIT = 0.75
local function IdealRoll(self, eval, vc)
    if not vc or not self:CountsAsUpgrade(vc) then return false end
    if eval.fit == nil then return true end
    if vc.valueGain ~= nil then return vc.valueGain > 0 end
    if eval.equippedFit and eval.fit > eval.equippedFit then return true end
    return eval.fit >= IDEAL_FIT
end
ns.IdealRoll = IdealRoll

-- Returns value, usable, ideal.
local function RollValue(self, eval)
    local vc = eval.voidcore
    if not vc or vc.reason == "owned" then return 0, false, false end
    local itemID = eval.item.itemID
    local target = self:IsVoidcoreTarget(itemID)
    local wanted = self:GetItemState(itemID) == "want"
    if not (self:CountsAsUpgrade(vc) or target or wanted) then return 0, false, false end
    local ideal = IdealRoll(self, eval, vc)
    -- capped: an empty slot is a big gain, not a bottomless one
    local levels = math.min(30, math.max(vc.potentialGain or 0, vc.gain or 0, 0))
    if vc.class == self.UPGRADE_STAT then levels = math.max(levels, 3) end
    if levels == 0 then levels = 3 end            -- chased regardless of level: still worth having
    local budget = TWO_HAND[eval.item.equipLoc] and 2 or SLOT_BUDGET[eval.slotID or 0] or 0.75
    local value = levels * budget
    -- stats that fit count extra, stats that do not count half
    if ideal then
        value = value * 1.25
    elseif eval.fit and eval.fit < 0.5 then
        value = value * 0.5
    end
    if target then
        value = value * 3
    elseif wanted then
        value = value * 2
    elseif eval.slotID and self:GetSlotState(eval.slotID) == "want" then
        value = value * 1.5
    end
    return value, true, ideal
end
ns.RollValue = RollValue

-------------------------------------------------------------------------------
-- Rolls received: per loot spec and pool, kept per character
-------------------------------------------------------------------------------
-- A pool's identity: a boss at a difficulty, or a dungeon at the roll's
-- reward track (the level a key rolls at).
local function PoolKey(s)
    if s.kind == "boss" and s.boss then return "b" .. tostring(s.boss.encounterID) .. ":" .. tostring(s.diffKey) end
    if s.kind == "dungeon" and s.dungeon then
        local vc = s.result and s.result.ctx and s.result.ctx.voidcore
        local track = vc and vc.track and vc.track.key or ("key" .. tostring(s.key))
        return "d" .. tostring(s.dungeon.challengeMapID) .. ":" .. track
    end
    return nil
end
ns.VoidcorePoolKey = PoolKey

local function RolledSet(self, s, create)
    local key = PoolKey(s)
    local spec = self:GetLootSpecID()
    if not key or not spec or not self.cdb then return nil end
    self.cdb.rolled = self.cdb.rolled or {}
    local bySpec = self.cdb.rolled[spec]
    if not bySpec then
        if not create then return nil end
        bySpec = {}
        self.cdb.rolled[spec] = bySpec
    end
    local set = bySpec[key]
    if not set and create then
        set = {}
        bySpec[key] = set
    end
    return set
end

function ns:IsRolled(s, itemID)
    local set = RolledSet(self, s, false)
    return set and set[itemID] and true or false
end

function ns:SetRolled(s, itemID, on, quiet)
    local set = RolledSet(self, s, true)
    if not set or not itemID then return end
    set[itemID] = on and time() or nil
    if not quiet then self:Fire("VOIDCORE_POOLS_UPDATED") end
end

function ns:ToggleRolled(s, itemID)
    self:SetRolled(s, itemID, not self:IsRolled(s, itemID))
end

-- One source: its pool from the loot table (the tooltip's list, when the
-- client gave one, corrects the rolled set), with each pool item's roll
-- weight. A pool with every item rolled has refilled: the set is cleared.
local function Source(self, name, r, cacheID, context, level, extra)
    local s = { name = name, result = r, cacheID = cacheID, context = context, level = level,
        items = {}, rolledItems = {}, usable = 0, ideal = 0, targets = 0, wanted = 0, value = 0, count = 0, total = 0, chance = 0, idealChance = 0, ev = 0, bestValue = 0 }
    for k, v in pairs(extra or {}) do s[k] = v end
    local pool = cacheID and self:VoidcorePool(cacheID, context, level, s) or nil
    s.pool = pool
    s.tooltipRead = pool and pool.ready and pool.count > 0 or false
    s.gaveUp = pool and pool.gaveUp or nil
    -- the tooltip is for the loot spec; only a matching evaluation can be
    -- checked against it
    local sync = s.tooltipRead and self:GetLootSpecID() == self:GetEvalSpecID()
    s.ready = (r and r.scanned) and true or false
    if not s.ready then return s end
    local rolled = RolledSet(self, s, false)
    local entries = {}
    for _, eval in ipairs(r.items) do
        local shown = eval.token or eval.item      -- a token is listed and rolled as the token
        if not shown.noRoll then
            local id = shown.itemID
            local isRolled
            if sync then
                isRolled = not pool.items[self:NormalizeName(NameOf(shown))]
                if isRolled ~= (rolled and rolled[id] and true or false) then
                    self:SetRolled(s, id, isRolled, true)
                    rolled = RolledSet(self, s, false)
                end
            else
                isRolled = rolled and rolled[id] and true or false
            end
            entries[#entries + 1] = { eval = eval, id = id, rolled = isRolled }
        end
    end
    s.total = #entries
    -- everything rolled: the game refills the pool
    if s.total > 0 and not sync then
        local all = true
        for _, e in ipairs(entries) do if not e.rolled then all = false; break end end
        if all then
            local set = RolledSet(self, s, false)
            if set then wipe(set) end
            for _, e in ipairs(entries) do e.rolled = false end
            s.refilled = true
        end
    end
    for _, e in ipairs(entries) do
        if e.rolled then
            s.rolledItems[#s.rolledItems + 1] = e.eval
        else
            local eval = e.eval
            local v, usable, ideal = RollValue(self, eval)
            eval.rollValue, eval.rollIdeal = v, ideal
            s.items[#s.items + 1] = eval
            if usable then s.usable = s.usable + 1 end
            if ideal then s.ideal = s.ideal + 1 end
            if self:IsVoidcoreTarget(eval.item.itemID) then s.targets = s.targets + 1 end
            if self:GetItemState(eval.item.itemID) == "want" then s.wanted = s.wanted + 1 end
            s.value = s.value + v
            if v > s.bestValue then s.best, s.bestValue = eval, v end
        end
    end
    -- the tooltip may list items the scan does not know; they still dilute
    s.count = s.tooltipRead and math.max(pool.count, #s.items) or #s.items
    if s.count > 0 then
        s.chance = s.usable / s.count
        s.idealChance = s.ideal / s.count
        s.ev = s.value / s.count
    end
    return s
end

local function SortSources(list, mode)
    table.sort(list, function(a, b)
        if a.missing ~= b.missing then return not a.missing end
        if mode == "name" then return a.name < b.name end
        if mode == "chance" then
            if a.chance ~= b.chance then return a.chance > b.chance end
        elseif mode == "pool" then
            if a.ideal ~= b.ideal then return a.ideal > b.ideal end
            if a.usable ~= b.usable then return a.usable > b.usable end
        elseif mode == "targets" then
            if a.targets ~= b.targets then return a.targets > b.targets end
        end
        if a.ev ~= b.ev then return a.ev > b.ev end
        if a.chance ~= b.chance then return a.chance > b.chance end
        if a.count ~= b.count then return a.count < b.count end
        return a.name < b.name
    end)
    return list
end

-- Every source, best place to roll first. mode: "best" | "chance" | "pool" | "name".
function ns:VoidcoreSources(mode)
    local list = {}
    local key = self.db and self.db.targetKey or 10
    for _, d in ipairs(self.dungeons) do
        list[#list + 1] = Source(self, d.name, self:ResultForDungeon(d), self:VoidcacheForDungeon(d), MPLUS_CONTEXT, key,
            { kind = "dungeon", dungeon = d, key = key })
    end
    local diffKey = self:GetRaidDifficulty()
    for _, group in ipairs(self.raidResults or {}) do
        for _, r in ipairs(group.bosses) do
            list[#list + 1] = Source(self, r.boss.name, r, self:VoidcacheForBoss(r.boss), RAID_CONTEXT[diffKey] or RAID_CONTEXT.heroic, nil,
                { kind = "boss", raid = group.raid, boss = r.boss, diffKey = diffKey })
        end
    end
    return SortSources(list, mode or "best")
end

-- The source behind a Voidcache item at a context (the roll window's own
-- prompt), evaluated at that difficulty or key.
function ns:VoidcoreSourceFor(cacheID, context, level)
    if not cacheID then return nil end
    for _, d in ipairs(self.dungeons) do
        if self:VoidcacheForDungeon(d) == cacheID then
            local key = tonumber(level) or self.db.targetKey or 10
            return Source(self, d.name, self:DropsAtKey(d, key), cacheID, MPLUS_CONTEXT, key, { kind = "dungeon", dungeon = d, key = key })
        end
    end
    local diffKey = CONTEXT_DIFF[tonumber(context) or 0] or self:GetRaidDifficulty()
    for _, raid in ipairs(self:GetRaids()) do
        for _, boss in ipairs(raid.bosses) do
            if self:VoidcacheForBoss(boss) == cacheID then
                local r = self.resultByEncounter and self.resultByEncounter[boss.encounterID]
                if not r or r.ctx.difficulty ~= diffKey then r = self:EvaluateBoss(raid, boss, diffKey) end
                return Source(self, boss.name, r, cacheID, RAID_CONTEXT[diffKey], nil, { kind = "boss", raid = raid, boss = boss, diffKey = diffKey })
            end
        end
    end
    return nil
end

-- "3 of 9 usable (33%), 1 target" for a source; nil while unknown.
function ns:VoidcoreSummary(s)
    if not s then return nil end
    if not s.ready then return "loot not scanned yet" end
    if s.count == 0 then return "nothing left in this pool" end
    local text = string.format("%d ideal, %d of %d usable (%d%%), +%.1f per roll", s.ideal, s.usable, s.count, math.floor(s.chance * 100 + 0.5), s.ev)
    if s.targets > 0 then text = text .. string.format(", %d target%s", s.targets, s.targets == 1 and "" or "s") end
    return text
end

-------------------------------------------------------------------------------
-- /sf voidcore: every pool's state, and one tooltip's raw lines
-------------------------------------------------------------------------------
function ns:PrintVoidcoreDiagnostics()
    self:Print("Voidcore pools")
    print(string.format("  Loot spec %s, evaluated spec %s, Voidcores %s, %d pool(s) queued; since login: %d journal loot event(s), %d tooltip data event(s)",
        tostring(self:SpecName(self:GetLootSpecID())), tostring(self:SpecName(self:GetEvalSpecID())), tostring(self:VoidcoreCount()), #queue,
        counters.lootData, counters.tooltipData))
    local shownRaw = false
    for _, s in ipairs(self:VoidcoreSources()) do
        local p = s.pool
        print(string.format("  %s: pool %s, %d of %d left, %d usable%s | cache %s ctx %s lvl %s: %s, %d read(s) (last %s lines, %d after a data update), journal asked %d time(s): %s loot%s",
            s.name, s.tooltipRead and "from the Voidcache" or "from the journal loot", #s.items, s.total, s.usable,
            s.refilled and " (refilled)" or "",
            tostring(s.cacheID), tostring(s.context), tostring(s.level),
            not s.cacheID and "no id" or (p and p.ready and (p.gaveUp and "no list" or ("listed " .. tostring(p.count))) or "reading"),
            p and p.tries or 0, tostring(p and p.lastLines), p and p.resolved or 0, p and p.touches or 0, tostring(p and p.journalLoot),
            p and p.touchNote and (" (" .. tostring(p.touchNote) .. ")") or ""))
        if not shownRaw and s.cacheID and C_TooltipInfo and C_TooltipInfo.GetItemByID then
            shownRaw = true
            local asked, n, why = self:TouchJournalLoot(s)
            print(string.format("    journal now: asked %s, %s loot entries%s", tostring(asked), tostring(n), why and (", " .. tostring(why)) or ""))
            local ok, data = pcall(C_TooltipInfo.GetItemByID, s.cacheID, nil, s.context, s.level)
            local lines = ok and type(data) == "table" and data.lines or nil
            print(string.format("    raw tooltip: %s line(s)", lines and #lines or "no"))
            for i, line in ipairs(lines or {}) do
                if i > 14 then print("    ..."); break end
                local text = tostring(line and line.leftText)
                local bytes = {}
                for b = 1, math.min(6, #text) do bytes[#bytes + 1] = string.format("%02X", text:byte(b)) end
                print(string.format("    %2d: %s  |cff888888[%s]%s|r", i, (text:gsub("|", "||")), table.concat(bytes, " "),
                    ListedName(text) and (" -> " .. ListedName(text)) or ""))
            end
        end
    end
end

-------------------------------------------------------------------------------
-- The bonus roll window: one line with this source's odds
-------------------------------------------------------------------------------
local function PromptSource()
    if not GetSpellConfirmationPromptsInfo then return nil end
    local ok, prompts = pcall(GetSpellConfirmationPromptsInfo)
    if not ok or type(prompts) ~= "table" then return nil end
    for _, p in ipairs(prompts) do
        if type(p) == "table" and p.displayItemID then
            return p.displayItemID, p.itemContext, p.treasureContextLevel
        end
    end
    return nil
end

function ns:RollWindowText()
    local cacheID, context, level = PromptSource()
    local s = self:VoidcoreSourceFor(cacheID, context, level)
    if not s then return nil end
    local summary = self:VoidcoreSummary(s)
    if not summary then return nil end
    return string.format("%s: %s", s.name, summary), s
end

-- The prompt on screen, kept for the result that follows it.
local lastPrompt
function ns:NoteRollPrompt()
    local cacheID, context, level = PromptSource()
    if cacheID then lastPrompt = { cacheID = cacheID, context = context, level = level, at = time() } end
    return lastPrompt
end

-- A roll's item leaves its pool.
function ns:RecordRoll(itemLink, specID)
    local id = tonumber(itemLink and itemLink:match("|Hitem:(%d+)") or nil)
    if not id or not lastPrompt then return nil end
    local s = self:VoidcoreSourceFor(lastPrompt.cacheID, lastPrompt.context, lastPrompt.level)
    if not s then return nil end
    self:SetRolled(s, id, true)
    self:Debug(string.format("Voidcore roll recorded: item %d from %s", id, s.name))
    return s
end

local rollLine
local function UpdateRollWindow()
    if not BonusRollFrame then return end
    ns:NoteRollPrompt()
    if not rollLine then
        rollLine = BonusRollFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rollLine:SetPoint("TOP", BonusRollFrame, "BOTTOM", 0, -2)
        rollLine:SetWidth(320)
        rollLine:SetJustifyH("CENTER")
    end
    local text = ns:RollWindowText()
    rollLine:SetText(text and ("|cff4fc3f7Slot Filler|r  " .. text) or "")
    rollLine:SetShown(text ~= nil)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
ns:On("LOGIN", function()
    ns:RegisterEvent("EJ_LOOT_DATA_RECIEVED", function() counters.lootData = counters.lootData + 1 end)
    ns:RegisterEvent("EJ_LOOT_DATA_RECEIVED", function() counters.lootData = counters.lootData + 1 end)
    ns:RegisterEvent("TOOLTIP_DATA_UPDATE", function(instance)
        counters.tooltipData = counters.tooltipData + 1
        OnTooltipData(instance)
    end)
    if BonusRollFrame and BonusRollFrame.HookScript then
        BonusRollFrame:HookScript("OnShow", function()
            ns:NoteRollPrompt()
            ns:Schedule("rollWindow", 0.2, UpdateRollWindow)
        end)
    end
    ns:RegisterEvent("BONUS_ROLL_RESULT", function(_, itemLink, _, specID)
        ns:RecordRoll(itemLink, specID)
        -- the game's own list shrinks by the roll; read it again once it has
        ns:Schedule("voidcoreRolled", 1.5, function()
            ns:ClearVoidcorePools()
            ns:Fire("VOIDCORE_POOLS_UPDATED")
        end)
    end)
    ns:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED", function() ns:ClearVoidcorePools() end)
    -- the client fills the Voidcache tooltips in while the Adventure Guide is
    -- open: read them then
    local function HookJournal()
        if EncounterJournal and not ns.voidcoreJournalHooked then
            ns.voidcoreJournalHooked = true
            EncounterJournal:HookScript("OnShow", function()
                ns:RetryEmptyVoidcorePools()
                ns:Schedule("voidcoreJournal", 0.5, function() ns:VoidcoreSources() end)
            end)
        end
    end
    HookJournal()
    ns:RegisterEvent("ADDON_LOADED", function(name) if name == "Blizzard_EncounterJournal" then HookJournal() end end)
end)

ns:On("SPEC_CHANGED", function() ns:ClearVoidcorePools() end)
ns:On("VOIDCORE_POOLS_UPDATED", function() if BonusRollFrame and BonusRollFrame:IsShown() then UpdateRollWindow() end end)
