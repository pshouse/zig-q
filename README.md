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

Runs unit tests for dice/RNG determinism, world init/place/deinit, demo replay, and the DST harness.

## Run (non-interactive demo)

```bash
zig build run -- --demo
zig build run -- --demo 42    # explicit seed (default: 42)
```

Prints stat rolls, spawn info, clock ticks, and an ASCII map viewport. Two runs with the same seed produce identical output.

## DST harness (deterministic simulation testing)

```bash
zig build dst -- bootstrap
zig build dst -- bootstrap 42
```

Runs a scripted, seed-fixed scenario (stat rolls → spawn → ticks → time → map render → look) and prints a transcript to stdout. Two consecutive runs with the same scenario and seed are byte-identical.

## Project layout

```
src/
  dice.zig       Dice rolling (4d6 drop-low, etc.)
  rng.zig        Seeded deterministic RNG
  types.zig      Attributes, races, classes, conditions
  world.zig      World init/spawn/deinit
  map.zig        Sparse tile map (entity IDs only)
  entity.zig     Entity store
  session.zig    Character bootstrap
  demo.zig       Non-interactive demo runner
  dst.zig        DST harness scenarios
  main.zig       CLI entry point
  dst_main.zig   DST harness entry point
```

## Help

```bash
zig build run -- --help
```