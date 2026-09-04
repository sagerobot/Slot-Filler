-- Slot Filler: item links at a chosen upgrade track step.
--
-- Loot links from the Adventure Guide describe the base Mythic+ item. To show
-- the item as it actually drops at +N (or as a Nebulous Voidcore roll at the
-- vault level) we need the link with the matching upgrade-track bonus ID.
-- The journal can preview keystone levels (Loot.lua captures those links), but
-- it cannot preview a vault-level item. So this module also learns the track
-- bonus IDs by experiment: starting from a link that carries a track bonus
-- (a journal link, or one of the player's own equipped items), it swaps that
-- bonus for nearby IDs and asks the client (tooltip / upgrade info) which one
-- yields the wanted item level and step. Results are cached per season.
local _, ns = ...

local SEARCH_RANGE = 96

-------------------------------------------------------------------------------
-- Link surgery
-- item:itemID:enchant:gem1:gem2:gem3:gem4:suffix:unique:linkLevel:spec:
--      modifiersMask:context:numBonus:bonus1..bonusN:numModifiers:(type:value)..
-------------------------------------------------------------------------------
local function SplitLink(link)
    if type(link) ~= "string" then return nil end
    local prefix, body, suffix = link:match("^(.-)(item:[%-%d:]*)(.*)$")
    if not body then return nil end
    local fields = {}
    for f in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = f end
    while #fields < 14 do fields[#fields + 1] = "" end
    return prefix, fields, suffix
end

local function JoinLink(prefix, fields, suffix)
    return (prefix or "") .. table.concat(fields, ":") .. (suffix or "")
end

function ns:LinkBonusIDs(link)
    local _, fields = SplitLink(link)
    local ids = {}
    for i = 1, fields and tonumber(fields[14]) or 0 do
        local v = tonumber(fields[14 + i])
        if v then ids[#ids + 1] = v end
    end
    return ids
end

local function ReplaceBonusID(link, fromID, toID)
    local prefix, fields, suffix = SplitLink(link)
    if not fields then return nil end
    local replaced = false
    for i = 1, tonumber(fields[14]) or 0 do
        if tonumber(fields[14 + i]) == fromID then
            fields[14 + i] = tostring(toID)
            replaced = true
        end
    end
    return replaced and JoinLink(prefix, fields, suffix) or nil
end

local function AddBonusID(link, id)
    local prefix, fields, suffix = SplitLink(link)
    if not fields then return nil end
    local n = tonumber(fields[14]) or 0
    for i = 1, n do
        if tonumber(fields[14 + i]) == id then return link end
    end
    table.insert(fields, 14 + n + 1, tostring(id))
    fields[14] = tostring(n + 1)
    return JoinLink(prefix, fields, suffix)
end

-- Journal links may carry an item context that pins the item level; drop it
-- so an added track bonus can take effect.
local function ClearContext(link)
    local prefix, fields, suffix = SplitLink(link)
    if not fields or fields[13] == "" then return nil end
    fields[13] = ""
    return JoinLink(prefix, fields, suffix)
end

-- A link stripped down to the item and one track bonus (no enchants, gems,
-- context or modifiers): the plain item at that track step.
local function MinimalLink(link, bonus)
    local prefix, fields, suffix = SplitLink(link)
    if not fields then return nil end
    return (prefix or "") .. string.format("item:%s::::::::%s:%s:::1:%d", fields[2] or "", fields[10] or "", fields[11] or "", bonus) .. (suffix or "")
end

-------------------------------------------------------------------------------
-- Probing: what item level / upgrade step does a link show?
-------------------------------------------------------------------------------
-- The rendered tooltip is the source of truth for a constructed link; the
-- upgrade-info API is only a fallback (it may answer from cached item data).
function ns:ProbeLink(link)
    if not link then return nil end
    local ilvl = self.ItemLevelOf(link)
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    local name, cur, max
    if ok and data then name, cur, max = self.ParseUpgradeFromTooltip(data) end
    if not cur then name, cur, max = self.UpgradeInfoOf(link) end
    return ilvl, name, cur, max
end

-- targetKey: expected track key ("Hero", "Myth", ...). The journal's item
-- context can keep its own upgrade line (Champion 1/6) after the track bonus
-- has changed the item level, so the name must be checked as well.
local function Matches(ilvl, cur, name, targetIlvl, targetStep, targetKey)
    if ilvl ~= targetIlvl then return false end
    if targetStep and cur and cur ~= targetStep then return false end
    if targetKey and name then
        local key = ns:TrackKeyForName(name)
        if key and key ~= targetKey then return false end
    end
    return true
end

local function Differs(ilvlA, curA, nameA, ilvlB, curB, nameB)
    if ilvlA ~= ilvlB then return true end
    if (curA == nil) ~= (curB == nil) then return true end
    if curA and curB and curA ~= curB then return true end
    if nameA and nameB and nameA ~= nameB then return true end
    return false
end

-------------------------------------------------------------------------------
-- Cache (per season): known track bonus IDs and discovered targets
-------------------------------------------------------------------------------
local STORE_VERSION = 2

local function Store()
    if not ns.db then return nil end
    local season = ns:GetSeasonID() or 0
    local s = ns.db.linkBonus[season]
    if not s or s.version ~= STORE_VERSION then
        s = { version = STORE_VERSION, known = {}, targets = {} }
        ns.db.linkBonus[season] = s
    end
    return s
end

-- Two links of the same item at different levels differ only by their track
-- bonus: whatever differs is a track bonus ID.
function ns:LearnTrackBonusFromPair(linkA, linkB)
    local store = Store()
    if not store or not linkA or not linkB or linkA == linkB then return end
    local a, b = self:LinkBonusIDs(linkA), self:LinkBonusIDs(linkB)
    local setA, setB = {}, {}
    for _, v in ipairs(a) do setA[v] = true end
    for _, v in ipairs(b) do setB[v] = true end
    for _, v in ipairs(a) do if not setB[v] then store.known[v] = true end end
    for _, v in ipairs(b) do if not setA[v] then store.known[v] = true end end
end

-- Experiment: which bonus in this link is the track bonus? A neighbouring ID
-- of the real track bonus is another step, so the upgrade line stays but its
-- step (or track name) changes. That is the strong signal. Merely changing
-- the item level or losing the line is weak: difficulty tags like 3524 do it.
local function FindTrackBonusByExperiment(self, link)
    local ids = self:LinkBonusIDs(link)
    if #ids == 0 then return nil end
    local baseIlvl, baseName, baseCur = self:ProbeLink(link)
    if not baseIlvl then return nil end
    local weak
    for _, b in ipairs(ids) do
        for delta = 1, 3 do
            for _, sign in ipairs({ 1, -1 }) do
                local ilvl, name, cur = self:ProbeLink(ReplaceBonusID(link, b, b + sign * delta))
                if ilvl then
                    if cur and baseCur and (cur ~= baseCur or (name and baseName and name ~= baseName)) then return b, true end
                    if not weak and Differs(baseIlvl, baseCur, baseName, ilvl, cur, name) then weak = b end
                end
            end
        end
    end
    return weak, false
end

-- Which bonus ID in this link is a known upgrade track bonus?
local function KnownTrackBonusIn(self, link)
    local store = Store()
    for _, b in ipairs(store and self:LinkBonusIDs(link) or {}) do
        if store.known[b] then return b end
    end
    return nil
end

-- The player's equipped items carry real track bonus IDs for this season and
-- no journal context, so they are the best anchors. Learned once per session.
function ns:LearnTrackBonusesFromGear()
    if self.gearAnchors then return self.gearAnchors end
    local store = Store()
    local anchors = {}
    for _, slot in ipairs(self.SLOTS) do
        local g = self.gear[slot.id]
        if g and g.link and g.cur and g.max then
            local b, strong = FindTrackBonusByExperiment(self, g.link)
            if b and strong then
                anchors[#anchors + 1] = { link = g.link, bonus = b, ilvl = g.ilvl, cur = g.cur }
                if store then
                    store.known[b] = true
                    local key = tostring(g.ilvl) .. "/" .. tostring(g.cur)
                    store.targets[key] = store.targets[key] or b
                end
                if #anchors >= 3 then break end
            end
        end
    end
    if #anchors > 0 then self.gearAnchors = anchors end
    self:Debug("Track bonus anchors from gear:", #anchors)
    return anchors
end

-- Searches near a known track bonus for the ID that yields the target.
function ns:FindTrackBonus(link, trackBonus, targetIlvl, targetStep, targetKey)
    for delta = 0, SEARCH_RANGE do
        for _, sign in ipairs({ 1, -1 }) do
            if delta > 0 or sign == 1 then
                local cand = trackBonus + sign * delta
                local test = (cand == trackBonus) and link or ReplaceBonusID(link, trackBonus, cand)
                if test then
                    local ilvl, name, cur = self:ProbeLink(test)
                    if Matches(ilvl, cur, name, targetIlvl, targetStep, targetKey) then return cand end
                end
            end
        end
    end
    return nil
end

-- The bonus ID that renders any item at targetIlvl / targetStep, or nil.
-- Searches from equipped-gear anchors first (reliable), then from the link's
-- own track bonus when it has a real one.
function ns:FindTargetBonus(targetIlvl, targetStep, link, targetKey)
    local store = Store()
    local key = tostring(targetIlvl) .. "/" .. tostring(targetStep or 0) .. "/" .. tostring(targetKey or "")
    if store and store.targets[key] then return store.targets[key] end
    local found
    for _, a in ipairs(self:LearnTrackBonusesFromGear()) do
        found = self:FindTrackBonus(a.link, a.bonus, targetIlvl, targetStep, targetKey)
        if found then break end
    end
    if not found and link then
        local b, strong = FindTrackBonusByExperiment(self, link)
        if b and strong then found = self:FindTrackBonus(link, b, targetIlvl, targetStep, targetKey) end
    end
    if found and store then
        store.targets[key] = found
        store.known[found] = true
        self:Debug("Track bonus for", key, "=", found)
        self:ClearLinkCache() -- links that failed for want of it can resolve now
    end
    return found
end

-------------------------------------------------------------------------------
-- The given link rewritten to the wanted item level / step / track, or nil.
-- Resolving renders tooltips (several per link when it fails), and an
-- evaluation asks for every drop twice; resolved links are remembered for
-- the session as "link|ilvl|step|track" -> link | false.
-------------------------------------------------------------------------------
local linkCache = {}

function ns:ClearLinkCache()
    wipe(linkCache)
end

local function ResolveLinkAtLevel(self, link, targetIlvl, targetStep, targetKey)
    local ilvl, name, cur = self:ProbeLink(link)
    if Matches(ilvl, cur, name, targetIlvl, targetStep, targetKey) then return link end
    local target = self:FindTargetBonus(targetIlvl, targetStep, link, targetKey)
    if not target then return nil end
    -- graft the bonus onto this item and keep the first variant the client
    -- renders exactly right. Context-free variants first: the journal context
    -- keeps its own upgrade line and would mislabel the track.
    local existing = KnownTrackBonusIn(self, link)
    local grafted = existing and ReplaceBonusID(link, existing, target) or AddBonusID(link, target)
    local variants = {}
    for _, v in ipairs({ grafted and ClearContext(grafted) or false, MinimalLink(link, target) or false, grafted or false }) do
        if v then variants[#variants + 1] = v end
    end
    for _, v in ipairs(variants) do
        ilvl, name, cur = self:ProbeLink(v)
        if Matches(ilvl, cur, name, targetIlvl, targetStep, targetKey) then return v end
    end
    return nil
end

function ns:LinkAtLevel(link, targetIlvl, targetStep, targetKey)
    if not link or not targetIlvl then return nil end
    local key = link .. "|" .. targetIlvl .. "|" .. (targetStep or 0) .. "|" .. (targetKey or "")
    local hit = linkCache[key]
    if hit ~= nil then return hit or nil end
    local resolved = ResolveLinkAtLevel(self, link, targetIlvl, targetStep, targetKey)
    -- a miss on an item whose data has not arrived (no item level yet) is
    -- not remembered: it is asked again later
    if resolved or self.ItemLevelOf(link) then linkCache[key] = resolved or false end
    return resolved
end

-- Track names learned later can change what a rendered link is taken for.
ns:On("TRACKS_CHANGED", function() ns:ClearLinkCache() end)

-------------------------------------------------------------------------------
-- Link for a loot item under a drop context. Returns link, kind ("exact" | "base").
-------------------------------------------------------------------------------
function ns:LinkForContext(item, ctx)
    if not item or not item.link then return nil, "none" end
    -- a tier token has no item level to rewrite; the token itself is shown
    if item.token then return item.link, "base" end
    -- the best journal preview link at or below the key
    local base = item.link
    if item.links then
        local bestLevel
        for level in pairs(item.links) do
            if (ctx.isVoidcore or level <= (ctx.key or 0)) and (not bestLevel or level > bestLevel) then bestLevel = level end
        end
        if bestLevel then base = item.links[bestLevel] end
    end
    if ctx and ctx.ilvl then
        local ok, exact = pcall(self.LinkAtLevel, self, base, ctx.ilvl, ctx.step, ctx.track and ctx.track.key)
        if ok and exact then return exact, "exact" end
        if not ok then self:Debug("LinkAtLevel error:", exact) end
    end
    return base, "base"
end

-------------------------------------------------------------------------------
-- /sf link : diagnostics for the tooltip link machinery
-------------------------------------------------------------------------------
function ns:PrintLinkDiagnostics()
    self:Print("Link diagnostics")
    local ctx = self.dropCtx or self:GetDropContext()
    print(string.format("  Context: key +%d%s ilvl %s step %s", ctx.key or 0, ctx.isVoidcore and " (Voidcore)" or "",
        tostring(ctx.ilvl), tostring(ctx.step)))
    local store = Store()
    if store then
        local known, targets = {}, {}
        for b in pairs(store.known) do known[#known + 1] = tostring(b) end
        for k, v in pairs(store.targets) do targets[#targets + 1] = k .. "=" .. tostring(v) end
        print("  Known track bonus ids: " .. (#known > 0 and table.concat(known, ", ") or "none"))
        print("  Discovered targets: " .. (#targets > 0 and table.concat(targets, ", ") or "none"))
    end
    for _, s in ipairs(self.SLOTS) do
        local g = self.gear[s.id]
        if g and g.link and g.cur then
            print(string.format("  Gear %s: %s bonus ids [%s]", s.key, g.link:gsub("|", "||"), table.concat(self:LinkBonusIDs(g.link), ",")))
            break
        end
    end
    local anchors = self:LearnTrackBonusesFromGear()
    for _, a in ipairs(anchors) do
        print(string.format("  Gear anchor: bonus %d = ilvl %s step %s", a.bonus, tostring(a.ilvl), tostring(a.cur)))
    end
    if #anchors == 0 then print("  Gear anchors: none found (no equipped item reacted to a bonus swap)") end
    if ctx.ilvl then
        print(string.format("  Target bonus for %s/%s/%s: %s", tostring(ctx.ilvl), tostring(ctx.step), tostring(ctx.track and ctx.track.key),
            tostring(self:FindTargetBonus(ctx.ilvl, ctx.step, nil, ctx.track and ctx.track.key))))
    end
    local shown = 0
    for _, d in ipairs(self.dungeons) do
        local entry = self.loot and self.loot.dungeons[d.challengeMapID]
        local items = entry and entry.items
        if items and items[1] and shown < 2 then
            shown = shown + 1
            local it = items[1]
            print(string.format("  %s (journal difficulty %s, %d items, %d with preview links)", d.name, tostring(entry.difficulty), #items, entry.previews or 0))
            print("    base link: " .. tostring(it.link):gsub("|", "||"))
            local ilvl, name, cur, max = self:ProbeLink(it.link)
            print(string.format("    base probe: ilvl %s, upgrade %s %s/%s, bonus ids [%s]", tostring(ilvl), tostring(name), tostring(cur), tostring(max),
                table.concat(self:LinkBonusIDs(it.link), ",")))
            if it.links then
                local levels = {}
                for l in pairs(it.links) do levels[#levels + 1] = l end
                table.sort(levels)
                for _, l in ipairs(levels) do
                    local li, ln, lc = self:ProbeLink(it.links[l])
                    print(string.format("    preview +%d: ilvl %s %s %s  [%s]", l, tostring(li), tostring(ln), tostring(lc), table.concat(self:LinkBonusIDs(it.links[l]), ",")))
                end
            end
            local link, kind = self:LinkForContext(it, ctx)
            local ri, rn, rc = self:ProbeLink(link)
            print(string.format("    result (%s): ilvl %s %s %s  %s", kind, tostring(ri), tostring(rn), tostring(rc), tostring(link):gsub("|", "||")))
        end
    end
    -- raid bosses at the Raid tab's difficulty: the drop level each one is
    -- judged at and where it came from, with every link's own level
    local diffKey = self:GetRaidDifficulty()
    local waiting = 0
    for _, v in pairs(self.itemRequests) do if v == true then waiting = waiting + 1 end end
    for _, raid in ipairs(self:GetRaids()) do
        print(string.format("  %s (%s%s)", raid.name, self:RaidDifficultyName(raid, diffKey), waiting > 0 and string.format(", %d items still loading", waiting) or ""))
        local shownLink = false
        for _, boss in ipairs(raid.bosses) do
            local items = self:GetBossLoot(boss, diffKey) or {}
            local bctx = self:GetRaidContext(diffKey, boss, raid)
            local scanned, live = {}, {}
            for _, it in ipairs(items) do
                scanned[#scanned + 1] = tostring(it.ilvl)
                live[#live + 1] = tostring(self.ItemLevelOf(it.link))
            end
            print(string.format("    %s: drop %s %s %s/%s (%s); levels at scan [%s], links now [%s]", boss.name, tostring(bctx.ilvl),
                tostring(bctx.track and bctx.track.key), tostring(bctx.step), tostring(bctx.track and #bctx.track.ilvls),
                tostring(bctx.source), table.concat(scanned, ","), table.concat(live, ",")))
            if not shownLink and items[1] then
                shownLink = true
                print("      first link: " .. tostring(items[1].link):gsub("|", "||"))
            end
        end
    end
end
