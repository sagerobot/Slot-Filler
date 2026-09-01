# Slot Filler

A World of Warcraft (retail, Midnight 12.1) addon that answers one question
when you open the Group Finder: **which Mythic+ dungeon should I run for gear?**

It docks a window to the left of the Dungeons & Raids window, lists every
dungeon in the current season, and ranks them by how many of their drops would
be upgrades for you at the key level you choose. Every item is judged twice:
as the end-of-dungeon drop, and as a **Nebulous Voidcore** bonus roll (which
Blizzard awards at the Great Vault item level of that key, so a +10 roll is
Myth 1/6 even though the chest drops Hero 3/6). Premade Groups listings get a
badge with the upgrade count for that group's dungeon.

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

## What you control

- **Key level** (`+`/`-` in the window or `/sf key 10`): drops are evaluated at
  that key's end-of-dungeon item level; the Voidcore column uses the vault
  level of the same key. End-of-dungeon gear stops improving at +10, so one
  step past it the selector becomes **Voidcore** and evaluates the bonus roll
  (Myth 1/6) instead. Item tooltips show the item as it drops at the selected
  key, or as the Voidcore version.
- **Spec**: follows your loot spec by default; click the spec button to pin one.
- **Slots**: click a slot icon to cycle Auto / Want / Skip. *Want* counts every
  drop for that slot; *Skip* ignores it (e.g. a crafted piece you are keeping).
- **Items**: right-click an item in a dungeon list to exclude it (bad trinket,
  or something you already received from a Voidcore, since those leave the
  roll pool) or mark it wanted (BiS even if not an item level gain).
- **Sorting**: Drops, Voidcore, Slots, or Name. Hide empty dungeons.
- **Options** (button in the window or `/sf options`): count immediate
  ilvl-only upgrades, dock side, auto-show rules, LFG badges, scale, manual
  track shift.

## Reading the numbers

Each dungeon row shows:

- **Drops**: how many spec-usable items in that dungeon would upgrade a slot
  as an end-of-dungeon drop. Green means at least one is a *track* upgrade
  (higher fully-upgraded potential than what you wear), yellow means only
  immediate item level gains.
- **Voidcore**: the share of that dungeon's spec-usable loot that would be an
  upgrade when rolled at the vault item level. Spend Voidcores where this is
  highest.

Upgrade classes for an item:

| Class | Meaning |
| --- | --- |
| track upgrade | Fully upgraded, the drop ends higher than your current item can. |
| ilvl upgrade | Higher item level right now, but not a higher ceiling. |
| wanted | You flagged the item or its slot. |
| no upgrade | Neither. |

Inside a dungeon's list, an item that is only worth it from a Voidcore roll is
tagged `VC`; an item that is an upgrade both ways carries a `*`.

## Commands

```
/sf                 toggle the window
/sf key <n>         set the key level
/sf rescan          rescan loot tables from the Adventure Guide
/sf options         open settings
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
| `Tracks.lua` | Upgrade track ladder + self-calibration from equipped items |
| `Gear.lua` | Equipped gear scan and tooltip parsing |
| `Season.lua` | Season pool, reward/vault item levels, activity-to-dungeon mapping |
| `Loot.lua` | Adventure Guide loot scanner and cache |
| `Evaluate.lua` | Upgrade classification (drop + Voidcore) and dungeon ranking |
| `UI.lua` | Main window, docking and Group Finder push |
| `Options.lua` | Options overlay and Settings entry |
| `LFGHook.lua` | Premade Groups badges and tooltip lines |

## Season data

`Season.lua` carries Midnight Season 2 numbers (Champion 1/6 = 292, six-step
tracks with +3/+3/+4/+3/+3, 13 between tracks, +10 = 311 Hero 3/6, vault +10 =
318 Myth 1/6). When a new season starts, the addon keeps working from the
live APIs and your own items; update the table when the numbers are public.
