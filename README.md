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

Runs unit tests for dice/RNG determinism, world lifecycle, movement/map occupancy, command handlers, REPL scripts, and DST scenarios.

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

Commands: `look`, `time`, `move <north|south|east|west>`, `help`, `exit`.

Piped input example (PowerShell):

```powershell
"look","move east","look","time","exit" | .\zig-out\bin\zig-q.exe --repl 42
```

## DST harness (deterministic simulation testing)

```bash
zig build dst -- bootstrap
zig build dst -- bootstrap 42
zig build dst -- explore
zig build dst -- explore 42
```

- **bootstrap** — stat rolls, spawn, ticks, map render, look
- **explore** — spawn, look, move east, look, time, exit

Two consecutive runs with the same scenario and seed produce byte-identical transcripts.

## Project layout

```
src/
  movement.zig   Entity movement on sparse map
  commands.zig   REPL command parse/execute
  repl.zig       REPL loop and scripted driver
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