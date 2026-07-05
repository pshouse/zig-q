# zig-q

A Zig prototype for deterministic **dungeon crawl** simulation: character creation, dungeon tiles, level-1 combat sheet (HP/AC), turn-based combat, and SQLite save/load.

**Requires Zig 0.15+** (tested on 0.15.2). **Version:** `0.9.0` — see [ROADMAP.md](ROADMAP.md) for v1.0.

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
```

Use `--record` to save a transcript (default: `transcripts/session-<timestamp>-seed<N>.txt`). A bare number after `--record` is the **seed**, not a filename — use a path like `transcripts/foo.txt` for a custom file. Transcripts include `# version=<semver>`, `# seed=`, and `> command` lines. Override version metadata with `--semver 0.6.0-dev`.

The REPL loads **floor 1** dungeon tiles, rolls six stats on start, then accepts creation commands before spawning a player. After `spawn`, creation commands are disabled.

**Creation commands:** `roll`, `assign <6 picks>`, `race <1-3>`, `class <1-3>`, `spawn`, `stats` (draft preview before spawn)

**Exploration commands:** `look`, `time`, `move <north|south|east|west>`, `descend` (on stairs/door tile), `help`, `exit`

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
zig build dst -- @scenarios/descend_crawl.txt 42
```

- **bootstrap** — stat rolls, spawn, ticks, map render, look (v0.2 compat path)
- **explore** — spawn, look, move east, look, time, exit
- **create** — roll, assign picks, choose dwarf/barbarian, spawn, stats, exit
- **crawl_start** — floor 1 dungeon, creation, spawn, look, wall block, stats
- **brawl** — floor 1, creation, spawn, goblin fight, attack/end turn, stats
- **save_roundtrip** — floor 1 crawl, save/load slot 1, continue with look/stats/move
- **playthrough** — harvested from `transcripts/session-1783208416-seed42.txt` (dragonborn crawl)
- **descend_crawl** — floor 1 creation/explore, `descend` to procedural floor 2, look/stats
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

## Help

```bash
zig build run -- --help
```