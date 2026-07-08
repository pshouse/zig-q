# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`zig-q` is a **deterministic, scriptable dungeon-crawl engine** in Zig 0.15+ (tested on 0.15.2): character creation → descend floors → fight monsters → survival needs → SQLite persistence. It is a library (`src/root.zig`, module name `zig_q`) plus a thin CLI (`src/main.zig`). SQLite is bundled from the amalgamation in `deps/sqlite3/` and compiled into the module — no system SQLite needed.

The product is scoped tightly. Read `ROADMAP.md` before adding features — several things are **permanently parked**: no magic (spells, wands, scrolls, enchantments, magic-derived conditions like `charmed`/`paralyzed`/`petrified`), no dialogue/NPC chat, no multiplayer, no non-SQLite persistence, no overworld. Permadeath is final. Stay inside the mundane crawl.

## Commands

```bash
zig build                 # build all artifacts into zig-out/bin/
zig build test            # unit tests (root.zig module — refAllDecls over every src file)
zig build consumer-test   # integration tests against the public zig_q API surface only
zig build run -- --repl 42 --record   # interactive/piped REPL, seed 42, transcript
zig build run -- --demo 42            # non-interactive demo
zig build fuzz -- 10000 0 42          # deterministic REPL fuzzer: iterations, fuzz_seed, world_seed
zig build dst -- <scenario> 42        # deterministic simulation scenario (see below)
zig build dst -- @scenarios/reference_crawl.txt 42   # data-driven scenario file
```

There is no single-test filter wired into `build.zig`; `zig build test` runs the whole suite (fast — ~12k LOC). To exercise one area, run its DST scenario or add/point a test.

DST scenario names: `bootstrap`, `explore`, `create`, `crawl_start`, `brawl`, `save_roundtrip`, `playthrough`, `descend_crawl`, `reference_crawl`, plus `@scenarios/*.txt` step files. Full descriptions are in `README.md`.

### Release gate — run before shipping any version

Every version must pass, in order: `zig build` / `zig build test` / `zig build consumer-test`, then `zig build fuzz` (10k default), then **all** shipped DST scenarios byte-identical across two runs on seed 42, then the matching `evidence-vNN` step. There is per-wave gate tooling: `zig build gate-v15` (and `-v11`..`-v14`) chains the build-log capture and scenario captures. Note `build.zig` hard-codes a Windows scratch path in `gate_scratch` for gate log output.

## The determinism contract (the core invariant)

**Same seed + same script → byte-identical transcript, every run.** This is the property the entire test strategy defends, and the most common way to break the codebase is to violate it. Practical rules:

- All randomness flows through `rng.SeededRng` (`src/rng.zig`, xorshift64*). Never call `std.crypto.random`, wall-clock time, or any unseeded source in engine logic. Seed 0 is remapped to a fixed constant.
- The **RNG draw order is part of the observable contract.** Reordering draws (e.g. rolling monster AI before player action, or swapping the sequence of dice within a fight) changes downstream output for the same seed and breaks golden transcripts even when the logic is "equivalent."
- Floors 2+ are **regenerated from `(seed, floor_index)`**, not persisted. Terrain layout is regen-only across save/load by design; only *world objects* (floor items, corpses, traps) persist in the SQLite save. Don't try to serialize terrain.
- Do not retroactively change existing golden DST transcripts (v0.6+) to make a change pass. A changed golden means you altered observable behavior — that needs to be intentional and version-gated, and new evidence captured.

Iteration over hash maps in a way that affects output is a determinism hazard — prefer stable ordering (sorted keys / arrays) anywhere the result reaches a transcript.

## Architecture

The library is layered; `src/root.zig` documents the intended **public** surface (World lifecycle, character setup, movement, combat, persistence, scripted testing, version). Everything else in `root.zig` is re-exported only so in-repo tests can reach it — treat non-documented symbols as internal.

**Ownership.** `world.World` (`src/world.zig`) owns all entities and characters; a single `World.deinit` tears everything down. Don't introduce parallel ownership or per-entity frees — allocate through the World and let it own lifetime.

**Command flow (one path for REPL, DST, and fuzz).** Raw input → `expandInput()` / `executeLine()` expand roguelike shorthands (`l`→`look`, `m n`→`move n`, `move nw`→two steps, `;` chains) → `commands.parseLine` → handler in `src/commands.zig`. REPL (`src/repl.zig`), DST (`src/dst.zig`), and fuzz (`src/fuzz.zig`) all drive this *same* path, which is why a scenario reproduces interactive behavior exactly. Add new commands in `commands.zig` and they light up in all three harnesses.

**Turn/phase model.** Create phase (roll/assign/race/class/spawn) locks after `spawn`. Then explore vs combat: an adjacent hostile or player `attack` enters combat (`combat.isInCombat`), monsters counter on their turn. Every major action costs clock ticks (`src/clock.zig`, `src/survival.zig`) which drive hunger/fatigue/exhaustion and poison DoT.

**Subsystems** (roughly by roadmap wave): `terrain.zig`/`dungeon.zig` (tiles + floor-1 handcrafted layout, floors 2+ generated), `character.zig`/`session.zig` (stat rolls, racial bonus, HP/AC sheet), `movement.zig`/`pathfinding.zig` (cardinal BFS, shared player+AI rules), `combat.zig`, `monsters.zig`, `conditions.zig` (single registry — apply/remove/describe; never mutate conditions ad-hoc in command handlers), `perception.zig` (WIS-gated LOS/trap spotting), `world_objects.zig`/`items.zig`/`inventory.zig` (gear + encumbrance), `doors.zig`, `explore.zig`, `survival.zig`.

**Persistence.** `sqlite_store.zig` (saveSlot/loadSlot/deleteDb, slots 1–9) over `save_state.zig` (schema, `WorldSave` v2). SQLite is the only persistence format from v0.8 on. When `schema_version` bumps, add a migration and a roundtrip DST scenario. The working-dir DB file is `zig-q.sqlite` (gitignored, along with all `*.sqlite`).

**Version.** Semver lives in `src/version.zig` (`version.semver`). Transcripts record `# version=<semver>`; `--semver` overrides per run. Bump it as part of shipping a version.

**Evidence + gate harnesses.** `evidence_vNN.zig` / `evidence_vNN_main.zig` emit per-version verification transcripts (markers proving a wave's features work); `wave_gate.zig` orchestrates the release-gate captures. These are numerous by design — one per shipped wave — and each has its own `build.zig` step and executable.

## Conventions

- **Scripted-first.** New behavior lands as a DST scenario / fuzz template before (or alongside) any interactive UX. New subsystems must add fuzz invariants (`src/fuzz.zig` checks world/map/terrain consistency after every step).
- Output goes through `io_out.zig` / writer params, not `std.debug.print`, so transcripts capture it.
- Platform is Windows (PowerShell primary); a Bash tool is also available. Zig's built-in `--fuzz` UI isn't available on Windows, which is why the repo ships its own deterministic fuzzer.
