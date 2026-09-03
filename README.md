# Slot Filler

A World of Warcraft (retail, Midnight 12.1) addon that answers one question
when you open the Group Finder: **which Mythic+ dungeon should I run for gear?**

It docks a window to the left of the Dungeons & Raids window with five tabs:

- **Dungeons** ranks every dungeon in the season by how many of its drops
  would be upgrades for you at the key level you choose, and shows how many
  items from your wanted list drop there. Click a dungeon to see its drops.
- **Raid** does the same for every boss of the season's raids (the lair
  included) at the difficulty you pick on the tab, with the same Drops and
  Wanted columns.
- **Gear** is one row per slot with what you wear. Open a slot and every
  drop for it, from dungeons, raid bosses or both, is listed, best stat fit
  first, each with where it comes from and a star. That is where you compare
  same-slot drops and pick the one to want.
- **Voidcore** ranks where to spend a Nebulous Voidcore. A pool is what a
  roll can still give your loot spec from a source at a difficulty: the
  loot table less the rolls you have received, which are recorded as they
  happen (right-click an item to mark one by hand). The game's own list,
  in each Voidcache's tooltip, is read whenever the client fills it in
  (with the Adventure Guide or a roll prompt open) and corrects the record.
  The tab shows how much of each pool would be an upgrade, weighs Voidcore
  targets and wanted items highest, and opens a row into the pool with each
  roll's verdict. Sources are ranked by the item levels a roll gains on
  average, slot-weighted. The roll window itself gets a line with the
  same odds. Set pieces worn, the next set bonus and Catalyst charges show
  on the Gear and Voidcore tabs; a tier-slot drop's tooltip says the
  Catalyst can make it a set piece.
- **IO** shows your Mythic+ rating and plans the timed keys that reach a
  target (2000, 2500, 3000 or a custom number). Several plans are offered,
  from the fewest runs at higher keys to the most runs at the lowest keys;
  the addon never asks you to pick a key level. Right-click a dungeon to
  leave it out, click one for its key ladder.
- **Settings**.

Two questions, two stars. "Which key or boss gives me the most upgrades" is
the Drops column. "Where do I spend my Nebulous Voidcore" is yours to
answer: every drop row has two stars. The first puts the item on your
wanted list, which the Wanted column counts. The second, purple, marks it as
a Voidcore target, and a purple star appears on every dungeon or boss row
where one drops. Both leave the lists by themselves once the item turns up
equipped or in your bags.

The lists and counts are about direct drops only. What a Voidcore roll would
be worth is in the tooltips: hold Shift over a drop, a dungeon, a boss or a
slot and the roll's level, verdict and value appear. A roll is at the Great
Vault level: a key's vault item level (+10: Myth 1/6), and on a raid boss
one upgrade track above the difficulty (Normal: Hero 1/6, Heroic: Myth 1/6,
Mythic: fully upgraded Myth), so a Heroic boss roll and a +10 dungeon roll
are worth the same Myth 1/6 item.

Premade Groups listings get a line under each group: its upgrade drops for
you, wanted items and Voidcore targets that drop there. Mythic Keystone
tooltips (your key in the bags, keystone links in chat) get the upgrade
lines at that key's own level, plus the rating a timed run would add.

## What it does automatically

- **Season pool**: read live from the game (`C_ChallengeMode.GetMapTable`).
- **Loot tables**: scanned from the Adventure Guide, dungeons at Mythic
  Keystone difficulty and every raid boss at each raid difficulty, filtered
  for your spec exactly like the journal does. No drop table to maintain;
  rescans when the cache is a week old or the pool changes.
- **Raid boss levels**: later bosses drop higher within the difficulty's
  track. The steps per boss are shipped with the season data (Season.lua)
  and matched by boss name, then by journal position; a raid the table
  does not know falls back to the levels read from the journal at scan
  time.
- **Raids**: the season's raids and their bosses come from the journal's
  current-season tier. Tier tokens are judged as the set piece they turn
  into for your class (the piece comes from the journal's Class Sets tab;
  which token makes which slot is shipped with the season data, since the
  journal names no slot for them). A token row shows the token itself and
  opens on a click to the piece it makes; a setting shows the piece in the
  token's place instead. The final boss's token, traded for any slot,
  stands as the best of the five pieces and always lists all five; it is
  not in the bonus roll pool, so it gets no Voidcore star or roll verdict
  (slot tokens can be rolled, and are judged like any drop).
- **Rating**: your best run per dungeon (level, time, timed or not) and the
  overall rating come from the game's own season data; the IO tab's plans
  are recomputed only when they change.
- **Drop item levels**: end-of-dungeon and Great Vault levels per key from the
  Mythic+ reward API, with a Season 2 table as fallback until the client has
  loaded the season's reward data.
- **Your gear**: item level and upgrade track ("Upgrade Level: Hero 2/6") read
  from your equipped items' tooltips. The whole track ladder is rebuilt from
  those lines, so it stays right even if the season defaults are stale.
- **Weapons**: one-hand / two-hand / off-hand drops are compared against the
  hand they would actually replace, based on what you have equipped.
- **Stat priority (Auto mode)**: Crit / Haste / Mastery / Versatility are
  ranked by the weight profile in use, or without one by how much of each your
  equipped gear carries. Drops for the same slot are ordered by how well their
  secondaries match, the stats column is coloured by that match, and item
  tooltips compare the drop's stats with what you wear.

## What you control

- **Key level** (`+`/`-` in the window or `/sf key 10`): drops are evaluated at
  that key's end-of-dungeon item level, up to the last key that still raises
  it (+10). Item tooltips show the item as it drops at the selected key.
- **Match level** (the box on the toolbar, in Settings, or `/sf match`): in
  Midnight an item can be upgraded for free up to the item level you have
  already reached in that slot (rings, trinkets and one-handers go by the
  lower of the pair). With the box on, every drop and Voidcore roll is judged
  as if upgraded that far, as many steps of its own track as fit under the
  slot's level, so same-slot drops compare by stats: a drop at the same
  level with better stats (a higher weighted value with a profile, a better
  priority match without) is a *stat upgrade*. The slot levels come from the
  game (`C_ItemUpgrade.GetHighWatermarkForSlot`); until it reports them,
  the weaker candidate slot's own item level stands in. Tooltips name the
  free upgrade and the slot level, and show the item at that level.
- **Raid difficulty**: the strip on the Raid tab (LFR, Normal, Heroic,
  Mythic; the lair's World difficulty sits in the LFR slot). Bosses are
  judged at that difficulty, and so are raid drops on the Gear tab.
- **Gear tab sources**: the strip on the Gear tab lists drops from M+, Raid
  or Both (the default).
- **Spec**: follows your loot spec by default; click the spec button to pin one.
- **Wanted list and Voidcore targets** (per spec): star a drop under a
  dungeon or a boss. Wanted items count for their dungeon or boss, show in
  the Gear tab and in group and keystone tooltips. The purple star marks a
  Voidcore target: the row it drops from gets a purple star, and group and
  keystone tooltips name it. Excluding an item (right-click) clears its
  Voidcore star, and marking one lifts an exclusion.
  Export/import the list as text in Settings to share it.
- **Slots**: in the Gear tab, right-click a slot to cycle Auto / Want / Skip.
  *Want* counts every drop for that slot; *Skip* ignores it (e.g. a crafted
  piece).
- **Items**: right-click a drop to exclude it (a bad trinket, or something you
  already received from a Voidcore, since those leave the roll pool).
- **Sorting**: click a column header (Dungeon or Boss, Drops, Wanted).
- **Settings**: the cog in the title bar; click it again to come back.
- **Voidcore tab**: pools follow your loot spec; dungeons at the selected
  key, bosses at the Raid tab's difficulty. Re-read asks the game's own
  lists again (they fill in while the Adventure Guide is open).
- **Rating target** (IO tab): 2000 / 2500 / 3000, or Custom with a stepper
  in steps of 50. Starts at the next milestone above your rating.
- **Runs** (IO tab): the plans that reach the target, one tab per number of
  runs. The first is the fastest (fewest runs, higher keys), the last the
  easiest (most runs, lowest keys); the easiest is selected by default.
- **Order** (IO tab): the dropdown above the list orders the planned runs
  by rating gained (highest key first) or by gear drops (the dungeons with
  the most usable drops at the planned key first, the count next to the
  name).
- **Max key** (IO tab): plans use no key above it. Automatic (grey) is your
  highest timed key plus two; step it to set your own, right-click the box
  to go back to automatic.
- **Avoided dungeons** (IO tab): right-click a dungeon to leave it out of
  the plans, right-click again to bring it back.
- **Stat priority**: per spec, Manual or Auto in Settings. Manual is the
  default: the four stats sit in a row, best first, and start in the Auto
  order; left-click a stat to move it left, right-click to move it right.
  Auto follows the weight profile in use, or your gear without one. Pasting
  a Pawn string switches to Auto; the manual order is kept for when you
  switch back.
- **Weight profiles**: paste a Pawn scale string (from Pawn, Raidbots or a
  guide) into Settings, or `/sf pawn <string>`. Each import is saved as a
  named profile for the spec, so a healer can keep a Raid and a Mythic+
  profile and switch between them with the Weights button in the window
  (the toolbar also shows the resulting stat order). In Auto mode the
  profile in use orders the stats, and every drop gets a weighted value at the selected
  key's item level (primary stat included) that tooltips compare with your
  equipped item (and, with Shift, the Voidcore roll). Same-slot drops sort by that
  value. Rename and delete profiles in Settings. Profiles, like everything
  else the addon remembers about you, belong to the logged-in character.
- **Settings** tab (or `/sf options`): count immediate ilvl-only upgrades
  (stat upgrades follow the same switch), Match level,
  hide empty dungeons and bosses, wanted list sharing, weight profiles and stat priority,
  dock side (left, right, or free; a free window can be set to move with the
  Dungeons & Raids window for people who move that with another addon),
  auto-show rules, LFG badges, keystone tooltips, rating gain on listings
  and keystones, scale, manual track shift.

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

Each dungeon or boss row shows:

- **Drops**: how many spec-usable items there would upgrade a slot as a
  direct drop (end of dungeon at the key, or off the boss at the
  difficulty). Green means at least one is a *track* upgrade (higher
  fully-upgraded potential than what you wear), yellow means only immediate
  item level gains.
- **Wanted**: how many items from your wanted list drop there. The tooltip
  names them; a purple star on the row means a Voidcore target drops there,
  and Shift in the tooltip lists the targets and the roll's level.

Upgrade classes for an item:

| Class | Meaning |
| --- | --- |
| track upgrade | Fully upgraded, the drop ends higher than your current item can. |
| ilvl upgrade | Higher item level right now, but not a higher ceiling. |
| stat upgrade | Match level only: same level once upgraded free, no lower ceiling, better stats. |
| wanted | You flagged the item or its slot. |
| no upgrade | Neither. |

Inside a dungeon's or boss's list, the stats column shows the item's
secondaries coloured by how well they match your stat priority. Hold Shift
over a drop to see how it would do as a Voidcore roll.

## Commands

```
/sf                 toggle the window
/sf key <n>         set the key level
/sf match           toggle Match level (drops judged as upgraded free to your slot's level)
/sf rescan          rescan loot tables from the Adventure Guide
/sf options         open settings
/sf pawn <string>   save a Pawn scale as a weight profile for the current spec and use it
/sf pawn            list the spec's profiles: use <name>, rename <n> <name>, delete <name>, clear
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
| `Rating.lua` | Mythic+ rating per dungeon, timed-score model, run plans towards a target |
| `Loot.lua` | Adventure Guide loot scanner (dungeons, raid bosses per difficulty) and cache |
| `Evaluate.lua` | Upgrade classification (drop, and the Voidcore roll for tooltips), dungeon and boss ranking |
| `Voidcore.lua` | Bonus roll pools from the Voidcache tooltips, source ranking, the roll window line |
| `UI.lua` | Main window (Dungeons, Raid, Gear, IO and Voidcore tabs), docking (neighbour-aware) and Group Finder push |
| `Options.lua` | Settings tab and the Settings > AddOns entry |
| `LFGHook.lua` | Premade Groups badges and tooltip lines |

## Season data

`Season.lua` carries Midnight Season 2 numbers (Champion 1/6 = 292, six-step
tracks with +3/+3/+4/+3/+3, 13 between tracks, +10 = 311 Hero 3/6, vault +10 =
318 Myth 1/6). When a new season starts, the addon keeps working from the
live APIs and your own items; update the table when the numbers are public.

It also carries the Season 2 rating formula for a timed key: 155 at +2, 15
per level, 15 more at +5, +7, +10 and +12, and up to 15 for finishing 40%
under the timer. Plans count runs as timed exactly (no timer bonus). The
formula is checked against the game's own score for your timed runs;
`/sf status` reports how many matched.
