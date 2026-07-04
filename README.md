# zig-q

A Zig prototype for tabletop-style character creation, dice rolling, and world simulation.

**Requires Zig 0.15+** (tested on 0.15.2).

## Build

```bash
zig build
```

## Test

```bash
zig build test
```

Runs unit tests for dice/RNG determinism, world lifecycle, movement/map occupancy, character assignment and racial bonuses, command handlers, REPL scripts, and DST scenarios.

## Run (non-interactive demo)

```bash
zig build run -- --demo
zig build run -- --demo 42    # explicit seed (default: 42)
```

## Run (REPL)

```bash
zig build run -- --repl
zig build run -- --repl 42
```

The REPL rolls six stats on start, then accepts creation commands before spawning a player.

**Creation commands:** `roll`, `assign <6 picks>`, `race <1-3>`, `class <1-3>`, `spawn`, `stats`

**Exploration commands:** `look`, `time`, `move <north|south|east|west>`, `help`, `exit`

Races: 1=dragonborn, 2=dwarf (+2 CON), 3=elf (+2 DEX). Classes: 1=barbarian, 2=fighter, 3=bard.

Piped creation script (PowerShell):

```powershell
@(
  "assign 6 5 4 3 2 1",
  "race 2",
  "class 1",
  "spawn",
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
```

- **bootstrap** — stat rolls, spawn, ticks, map render, look (v0.2 compat path)
- **explore** — spawn, look, move east, look, time, exit
- **create** — roll, assign picks, choose dwarf/barbarian, spawn, stats, exit

Two consecutive runs with the same scenario and seed produce byte-identical transcripts.

## Project layout

```
src/
  character.zig  Stat assignment and racial bonus helpers
  choose.zig     1-based pick indexing
  movement.zig   Entity movement on sparse map
  commands.zig   REPL command parse/execute
  repl.zig       REPL loop and scripted driver
  session.zig    Stat rolls and creation draft
  dice.zig       Dice rolling
  rng.zig        Seeded deterministic RNG
  world.zig      World init/spawn/deinit
  dst.zig        DST harness scenarios
  main.zig       CLI entry point
```

## Help

```bash
zig build run -- --help
```