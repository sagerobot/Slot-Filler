# Slot Filler

A World of Warcraft (retail, Midnight 12.1) addon that answers one question
when you open the Group Finder: **which Mythic+ dungeon should I run for gear?**

It docks a window to the left of the Dungeons & Raids window with three tabs:

- **Dungeons** ranks every dungeon in the season by how many of its drops
  would be upgrades for you at the key level you choose, and shows how many
  items from your wanted list drop there. Click a dungeon to see its drops.
- **Gear** is one row per slot with what you wear. Open a slot and every
  drop for it from every dungeon is listed, best stat fit first, each with
  the dungeon it comes from and a star. That is where you compare same-slot
  drops and pick the one to want.
- **Settings**.

Two questions, two answers. "Which key gives me the most upgrades" is the
Drops column. "Where do I spend my Nebulous Voidcore" is the Wanted column:
you get one roll a week at most, so it goes where an item you are after
drops, not where the most random drops would be upgrades. Star a drop to put
it on the wanted list; it leaves the list by itself once the item turns up
equipped or in your bags.

Premade Groups listings get a badge with the upgrade count (and a star when
a wanted item drops there), and Mythic Keystone tooltips (your key in the
bags, keystone links in chat) get the same lines at that key's own level.

## What it does automatically

- **Season pool**: read live from the game (`C_ChallengeMode.GetMapTable`).
- **Loot tables**: scanned from the Adventure Guide at Mythic Keystone
  difficulty, filtered for your spec exactly like the journal does. No drop
  table to maintain; rescans when the cache is a week old or the pool changes.
- **Drop item levels**: end-of-dungeon and Great Vault levels per key from the
  Mythic+ reward API, with a Season 2 table as fallback until the client has
  loaded the season's reward data.
- **Your gear**: item level and upgrade track ("Upgrade Level: Hero 2/6") read
  from your equipped items' tooltips. The whole track ladder is rebuilt from
  those lines, so it stays right even if the season defaults are stale.
- **Weapons**: one-hand / two-hand / off-hand drops are compared against the
  hand they would actually replace, based on what you have equipped.
- **Stat priority**: Crit / Haste / Mastery / Versatility are ranked by how
  much of each your equipped gear carries. Drops for the same slot are ordered
  by how well their secondaries match, the stats column is coloured by that
  match, and item tooltips compare the drop's stats with what you wear.

## What you control

- **Key level** (`+`/`-` in the window or `/sf key 10`): drops are evaluated at
  that key's end-of-dungeon item level; the Voidcore column uses the vault
  level of the same key. End-of-dungeon gear stops improving at +10, so one
  step past it the selector becomes **Voidcore** and evaluates the bonus roll
  (Myth 1/6) instead. Item tooltips show the item as it drops at the selected
  key, or as the Voidcore version.
- **Spec**: follows your loot spec by default; click the spec button to pin one.
- **Wanted list** (per spec): star a drop under a dungeon. Wanted items count
  for their dungeon, show in the Gear tab and in group and keystone tooltips.
  Export/import the list as text in Settings to share it.
- **Slots**: in the Gear tab, right-click a slot to cycle Auto / Want / Skip.
  *Want* counts every drop for that slot; *Skip* ignores it (e.g. a crafted
  piece).
- **Items**: right-click a drop to exclude it (a bad trinket, or something you
  already received from a Voidcore, since those leave the roll pool).
- **Sorting**: click a column header (Dungeon, Drops, Wanted).
- **Stat priority**: the learned order can be overridden per spec in the
  options (left-click a stat to move it up, right-click to move it down, or
  go back to weights / gear).
- **Pawn weights**: paste a Pawn scale string (from Pawn, Raidbots or a
  guide) into the options, or `/sf pawn <string>`. Real weights then order
  the stats, and every drop gets a weighted value at the selected key's item
  level (primary stat included) that tooltips compare with your equipped item
  and with the Voidcore version. Same-slot drops sort by that value.
- **Settings** tab (or `/sf options`): count immediate ilvl-only upgrades,
  hide empty dungeons, wanted list sharing, stat priority and Pawn weights,
  dock side, auto-show rules, LFG badges, keystone tooltips, scale, manual
  track shift.

## Look and feel

The window is built to sit next to an EllesmereUI-skinned Group Finder. When
EllesmereUI is installed, Slot Filler registers with its public skinning API
(`EllesmereUI.RegisterSkin`) and EllesmereUI paints the window itself: its
window style (EllesmereUI or Modern), accent colour, font and control look all
follow the user's EllesmereUI settings, live. Users can turn this off per addon
under *Blizz UI Enhanced > Blizzard Window Skins > Third-Party Addons*.

Without EllesmereUI, or with that toggle off, `Style.lua` paints the same flat
look with fixed colours (dark panels, 1px borders, teal accent, the game's
default font). No EllesmereUI files or settings are read either way.

EllesmereUI also parks the character sheet on the Group Finder's left edge when
both are open. Slot Filler docks outside whichever window is furthest left, so
the two never overlap.

## Reading the numbers

Each dungeon row shows:

- **Drops**: how many spec-usable items in that dungeon would upgrade a slot
  as an end-of-dungeon drop. Green means at least one is a *track* upgrade
  (higher fully-upgraded potential than what you wear), yellow means only
  immediate item level gains.
- **Wanted**: how many items from your wanted list drop there. The dungeon
  tooltip names them and what a Voidcore roll there would be worth.

Upgrade classes for an item:

| Class | Meaning |
| --- | --- |
| track upgrade | Fully upgraded, the drop ends higher than your current item can. |
| ilvl upgrade | Higher item level right now, but not a higher ceiling. |
| wanted | You flagged the item or its slot. |
| no upgrade | Neither. |

Inside a dungeon's list, an item that is only worth it from a Voidcore roll is
tagged `VC`. The stats column shows the item's secondaries coloured by how well
they match your stat priority.

## Commands

```
/sf                 toggle the window
/sf key <n>         set the key level
/sf rescan          rescan loot tables from the Adventure Guide
/sf options         open settings
/sf pawn <string>   import a Pawn scale for the current spec (/sf pawn clear)
/sf status          print what the addon knows (season, tracks, gear, cache)
/sf reset overrides|cache|all
/sf debug           toggle debug output
```

## Install

Run `install.ps1` to create a junction from the WoW AddOns folder to
`SlotFiller/` in this repo, or copy the `SlotFiller` folder into
`World of Warcraft\_retail_\Interface\AddOns\`. After editing files, `/reload`.

## Tests

`tests/harness.lua` stubs the WoW API and runs the real addon files under
Lua 5.1 (the game's Lua version):

```
lua tests/harness.lua
```

## Files

| File | Purpose |
| --- | --- |
| `Core.lua` | Namespace, saved variables, events, slash commands |
| `Data.lua` | Slot definitions, inventory-type mapping, fallback IDs |
| `Style.lua` | Widget painting: EllesmereUI skin registration with a flat fallback |
| `Tracks.lua` | Upgrade track ladder + self-calibration from equipped items |
| `Gear.lua` | Equipped gear scan and tooltip parsing |
| `Season.lua` | Season pool, reward/vault item levels, activity-to-dungeon mapping |
| `Loot.lua` | Adventure Guide loot scanner and cache |
| `Evaluate.lua` | Upgrade classification (drop + Voidcore) and dungeon ranking |
| `UI.lua` | Main window (Dungeons and Gear tabs), docking (neighbour-aware) and Group Finder push |
| `Options.lua` | Settings tab and the Settings > AddOns entry |
| `LFGHook.lua` | Premade Groups badges and tooltip lines |

## Season data

`Season.lua` carries Midnight Season 2 numbers (Champion 1/6 = 292, six-step
tracks with +3/+3/+4/+3/+3, 13 between tracks, +10 = 311 Hero 3/6, vault +10 =
318 Myth 1/6). When a new season starts, the addon keeps working from the
live APIs and your own items; update the table when the numbers are public.
