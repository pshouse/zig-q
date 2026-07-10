# zig-q

A Zig prototype for deterministic **dungeon crawl** simulation: character creation, dungeon tiles, level-1 combat sheet (HP/AC), turn-based combat, and SQLite save/load.

**Requires Zig 0.15+** (tested on 0.15.2). **Version:** `1.6.1` — deterministic dungeon crawl through crawl completeness (see ROADMAP.md).

SQLite is bundled via the amalgamation in `deps/sqlite3/` (no system SQLite install required).

```bash
zig build run -- --version
```

## Build

```bash
zig build
```

## Test

```bash
zig build test
```

Runs unit tests for dice/RNG determinism, world lifecycle, movement/map occupancy, dungeon terrain, character assignment and racial bonuses, HP/AC sheet, command handlers, REPL scripts, DST scenarios, and fuzz smoke tests.

**Release gate:** `zig build fuzz` must pass before each version ships (see ROADMAP.md).

## Run (non-interactive demo)

```bash
zig build run -- --demo
zig build run -- --demo 42    # explicit seed (default: 42)
```

## Run (REPL)

```bash
zig build run -- --repl
zig build run -- --repl 42
zig build run -- --repl 42 --record
zig build run -- --repl --record 42
zig build run -- --repl 42 --record my-session.txt
zig build run -- --repl 42 --live-ai
```

Use `--record` to save a transcript (default: `transcripts/session-<timestamp>-seed<N>.txt`). A bare number after `--record` is the **seed**, not a filename — use a path like `transcripts/foo.txt` for a custom file. Transcripts include `# version=<semver>`, `# seed=`, and `> command` lines. Override version metadata with `--semver 0.6.0-dev`.

The REPL loads **floor 1** dungeon tiles, rolls six stats on start, then accepts creation commands before spawning a player. After `spawn`, creation commands are disabled.

**Creation commands:** `roll`, `assign <6 picks>`, `race <1-3>`, `class <1-3>`, `spawn`, `stats` (draft preview before spawn)

**Exploration commands:** `look`, `time`, `move <north|south|east|west>`, `m <dir>`, `wait`, `food`, `rest`, `sleep`, `conditions`, `descend` (on stairs/door tile), `help`, `help gear`, `exit`

**Gear commands:** `get [item]` (nearest floor item), `get from corpse` / `loot from corpse` (an adjacent corpse's gear), `loot` (an adjacent corpse's gear first, else the nearest floor item), `drop <item>`, `inventory`, `examine <item>`, `equip <item>`, `unequip <slot|item>` (aliases `unwield`, `remove`, `take off`), `use <item>`. `look` lists nearby items and corpses; stand adjacent to pick up. Equipped gear stays in the bag; `unequip` clears the slot, and dropping an equipped item clears its slot too.

**Combat commands:** `attack [target]`, `end turn` (melee d20 + STR mod vs AC; monsters counter on their turn)

**Persistence commands:** `save [slot]`, `load <slot>` (slots 1–9; default save slot 1; database file `zig-q.sqlite` in the working directory)

Races: 1=dragonborn, 2=dwarf (+2 CON), 3=elf (+2 DEX). Classes: 1=barbarian, 2=fighter, 3=bard.

Piped crawl script (PowerShell):

```powershell
@(
  "assign 6 5 4 3 2 1",
  "race 2",
  "class 1",
  "stats",
  "spawn",
  "look",
  "move north",
  "stats",
  "exit"
) | .\zig-out\bin\zig-q.exe --repl 42
```

Use newline-terminated lines. Each line is echoed as `> <command>` in the transcript.

Piped sessions run with **explore AI off** by default: monsters do not patrol, chase, or ambush between your actions, so scripted verification paths stay stable. Pass `--live-ai` to keep explore AI on in a piped session — monsters roam exactly as in an interactive TTY run. AI draws come from the seeded stream in a fixed order, so a `--live-ai` script is still byte-identical across replays. DST scenarios and wave-gate captures do not use this flag; their golden transcripts are unchanged.

## DST harness (deterministic simulation testing)

```bash
zig build dst -- bootstrap
zig build dst -- bootstrap 42
zig build dst -- explore
zig build dst -- explore 42
zig build dst -- create
zig build dst -- create 42
zig build dst -- crawl_start
zig build dst -- crawl_start 42
zig build dst -- playthrough
zig build dst -- playthrough 42
zig build dst -- brawl
zig build dst -- brawl 42
zig build dst -- save_roundtrip
zig build dst -- save_roundtrip 42
zig build dst -- descend_crawl
zig build dst -- descend_crawl 42
zig build dst -- reference_crawl 42
zig build dst -- @scenarios/descend_crawl.txt 42
zig build dst -- @scenarios/reference_crawl.txt 42
```

- **bootstrap** — stat rolls, spawn, ticks, map render, look (v0.2 compat path)
- **explore** — spawn, look, move east, look, time, exit
- **create** — roll, assign picks, choose dwarf/barbarian, spawn, stats, exit
- **crawl_start** — floor 1 dungeon, creation, spawn, look, wall block, stats
- **brawl** — floor 1, creation, spawn, goblin fight, attack/end turn, stats
- **save_roundtrip** — floor 1 crawl, save/load slot 1, continue with look/stats/move
- **playthrough** — harvested from `transcripts/session-1783208416-seed42.txt` (dragonborn crawl)
- **descend_crawl** — floor 1 creation/explore, `descend` to procedural floor 2, look/stats
- **reference_crawl** — floor 1→3 descent, goblin fights, save/load on floor 2 (seed 42 regression)
- **combat_flee** — exhausted fighter attacks then `flee`s; adjacent goblin gets one opportunity attack, combat ends
- **catch_breath** — exhausted fighter trades combat turns to `catch breath`, shedding fatigue as the goblin counters
- **combat_reposition** — step out of the goblin's reach mid-combat, then `end turn` / `catch breath`; the unreachable goblin forfeits its counter (crash regression), re-engage proves combat stayed live
- **rest_floor** — rest sheds fatigue only to the floor (20); only sleep clears exhaustion (survival-economy guard)
- **exhausted_sleep** — sleep from fatigue 60 crosses the tier-4 "HP max halved" band mid-sleep yet wakes at full HP (the halving caps recovery, it never drains); at tier 4 a bandage heals only to half max and is refused at the cap
- **starve_out** — starvation drains HP to 0 outside combat; permadeath gate blocks further play (walking-dead guard)
- **glyph_look** — viewport glyph legend: live monsters render as kind letters (`g` goblin, `s` skeleton, `h` hobgoblin, `w` skeleton_warrior), dead ones stop rendering; `*` no longer marks monsters
- **deadly_floor** — floor-4 danger-tier counters after every player attack; `flee` under pressure
- **elite_brawl** — hobgoblin/skeleton_warrior with danger-tier AC/HP on deep floors
- **scarce_heals** — floor 4–5 loot plans place fewer bandages than the floor-2 baseline
- **save_v4_roundtrip** — schema v4 `danger_tier` survives save/load
- **survival_economy** — food-vs-ticks audit per generated floor: planned rations, spawn→stairs distance, minimum crossing cost (danger floors guarantee ≥ 1 ration)
- **monster_endurance** — goblin outlives 135 ticks of world clock and is still attackable; regression for monsters dying of exhaustion (survival pressure is player-only)
- **bleed_out** — poisoned goblin dies of DoT outside combat; the death mirrors a combat kill (corpse with loot drops, tile map frees, player walks onto the tile)
- **@scenarios/*.txt** — data-driven step files (`load_floor`, `command`, `spawn`, …)

Floors 2+ are generated deterministically from `(seed, floor_index)`; floor 1 stays handcrafted for regression.

Two consecutive runs with the same scenario and seed produce byte-identical transcripts.

## Harvest playthrough transcripts

After a recorded REPL session (`--record`), extract input commands for regression:

```bash
zig build run -- --harvest transcripts/session-1783208416-seed42.txt
```

Each `> command` line becomes one output line (seed header included). The harvested script is wired into the `playthrough` DST scenario and a REPL determinism test.

Roguelike shorthands from recorded sessions (`l`, `m n`, `move nw`, `move w w`, `;` chains) are expanded by `executeLine` before command parsing — see [ROADMAP.md](ROADMAP.md).

## Fuzz harness

Zig's built-in `--fuzz` UI is not available on Windows yet, so zig-q ships a deterministic REPL fuzzer:

```bash
zig build fuzz
zig build fuzz -- 10000 0 42
```

Arguments: `iterations` (default 10000), fuzz `seed` (default 0), `world_seed` (default 42).

Each iteration loads floor 1, generates random command scripts, executes through the REPL path, and checks world/map/terrain invariants after every step.

## Project layout

```
src/
  terrain.zig    Dungeon tile types and terrain map
  dungeon.zig    Floor layout data
  character.zig  Stat assignment, racial bonus, HP/AC sheet
  choose.zig     1-based pick indexing
  movement.zig   Entity movement on sparse map
  commands.zig   REPL command parse/execute
  repl.zig       REPL loop and scripted driver
  session.zig    Stat rolls and creation draft
  dice.zig       Dice rolling
  rng.zig        Seeded deterministic RNG
  world.zig      World init/spawn/deinit
  dst.zig        DST harness scenarios
  fuzz.zig       Deterministic REPL fuzz harness
  main.zig       CLI entry point
```

## Playtest fleet (balance instrument)

`.claude/workflows/survival-fleet.js` is a committed agent-playtest harness: 4 personas
(speedrunner / cautious / hoarder / exploit-hunter) x N seeds play ironman runs against a build and
report a death-cause + depth summary. Used to A/B balance changes (see SPRINT_V1.7 SD5): run with
identical `seeds`/`turnBudget` on baseline and candidate builds and diff the summaries. Invoke from a
Claude Code session: `Workflow({ name: 'survival-fleet', args: { label: 'retuned' } })`. The v1.6.1
baseline (0/12 reached floor 5; 3 of 4 deaths were clock/environment) is recorded on issue #40.
Raw session logs land in `.fleet/<label>/` (gitignored); each is a deterministic replay file.

## Help

```bash
zig build run -- --help
```

## Version history

| Version | Theme |
|---------|--------|
| **1.6.1** | Exhaustion tier 4 "HP max halved" is a recovery cap, not a drain: crossing fatigue 70 (e.g. mid-`sleep`) no longer permanently halves current HP; instead bandage healing stops at half max while the tier is active |
| **1.6.0** | Depth danger: initiative counters on floor ≥4, danger-tier stats, elites, scarce heals, save v4 |
| **1.5.5** | Monsters exempt from hunger/fatigue/exhaustion: survival pressure is player-only, so floors no longer die off corpseless ~95 ticks after spawning (poison DoT still applies to monsters) |
| **1.5.4** | Survival economy: `rest` floored at fatigue 20; only `sleep` fully clears exhaustion (sleep no longer strictly dominated) |
| **1.5.3** | Review fixes: look no longer perturbs combat RNG, unique deep-floor monster names, honest cross-wave gate |
| **1.5.2** | DoT HP notices for poison/starvation ticks |
| **1.5.1** | v1.5 crawl + WIS-gated trap spotting in `look` |
| **1.5.0** | Bandage heal, procedural traps on descend, depth-scaled monsters/loot |
| **1.4.0** | Survival clock: hunger, fatigue, exhaustion, food/rest/sleep, poison DoT |
| **1.3.0** | Living dungeon: monster AI, doors, step-traps, pathfinding |
| **1.2.0** | Mundane gear: inventory, weapons, armour, encumbrance, corpse loot |
| **1.1.0** | Foundation: save v2, LOS, conditions registry, permadeath, ambush handoff |
| **1.0.0** | Stable crawl engine, public API, `reference_crawl` regression |