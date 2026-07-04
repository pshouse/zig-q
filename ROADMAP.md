# zig-q roadmap (v0.6 → v1.0)

**Product:** deterministic, scriptable **dungeon crawl** engine — create a character, descend floors, fight monsters, persist progress. No dialogue trees.

**Current release:** `0.6.0` (session phases, floor-1 dungeon tiles, HP/AC sheet, DST `crawl_start`).

---

## Engine rules (every version)

| Rule | Requirement |
|------|-------------|
| **Determinism** | Same seed + same script → byte-identical DST/scenario transcripts |
| **Fuzzing** | `zig build fuzz` must pass before a version ships; new subsystems add fuzz templates and invariants |
| **Teardown** | Single `World.deinit` owns all entities and characters |
| **Scripted-first** | Piped REPL and DST scenarios before interactive menus |
| **Semver** | `zig-q version` / `--version`; transcripts record `# version=<semver>`; optional `--semver` override per run |
| **Persistence** | SQLite only (from v0.8 onward) — no ad-hoc snapshot formats |
| **Scope** | Dungeon crawl only — no dialogue, quests with NPC chat, or overworld sim |

---

## v0.6 — Session model & dungeon map v1 (shipped)

**Theme:** Clear create → crawl phases; walkable dungeon geometry.

---

## v0.7 — Combat & monsters

**Theme:** Turn-based fights in the dungeon.

| Deliver | Notes |
|---------|--------|
| Turn state | exploring ↔ fighting |
| Melee pipeline | d20 + mod vs AC, damage, HP → 0 |
| Conditions | prone, blinded, etc. affect rolls |
| Monster entities | goblin, skeleton — static stat blocks |
| REPL | `attack`, `end turn` |
| DST `brawl` | fixed seed combat transcript |
| **Fuzz** | combat command sequences; invariant: HP ≥ 0, valid turn owner |

**Non-goals:** spells, inventory, death saves, AI pathing.

---

## v0.8 — SQLite persistence

**Theme:** Save the crawl; resume later.

| Deliver | Notes |
|---------|--------|
| `zig-q.sqlite` schema | `schema_version`, `save_slot`, world blob or normalized rows |
| Persist | seed, rng offset, floor, entities, HP, map cell state, clock |
| REPL | `save`, `load [slot]` |
| DST `save_roundtrip` | play → save → load → continue; transcript tail identical |
| **Fuzz** | save/load between random command bursts; invariant: snapshot ≡ restored world |

**Non-goals:** dialogue flags, quest journal, cloud sync.

---

## v0.9 — Dungeon generation & scenarios

**Theme:** Seed-fixed floors; authored crawl scripts.

| Deliver | Notes |
|---------|--------|
| Room + corridor generator | seeded; placed monsters and loot tables |
| Stairs down | `descend` → floor N+1, new layout |
| Scenario files | data-driven steps (extends DST) |
| Transcript → regression | tool extracts `> cmd` lines into DST/REPL tests |
| **Fuzz** | random descend depth cap; invariant: one player, valid floor index |

**Non-goals:** dialogue nodes, shop UI, overworld map.

---

## v1.0 — Crawl engine release

**Theme:** Stable library + CLI for a full descent.

| Deliver | Notes |
|---------|--------|
| Public `zig_q` API | documented World, crawl, combat, SQLite |
| Reference crawl | scripted floor 1→3 with fight + save mid-run |
| Semver policy | MAJOR.MINOR.PATCH tags; transcript records version |
| Release gate | `build`, `test`, `dst *`, `fuzz`, one transcript regression |
| **Fuzz** | 10k+ default; published failure repro seeds in `fuzz-corpus/` |

**Non-goals:** 1.0 ≠ content-complete bestiary; 1.0 = stable crawl engine.

---

## Explicitly parked (post-1.0)

- Dialogue / NPC conversation
- Multiplayer
- Non-SQLite persistence
- Rich TUI / graphics
- Procedural overworld

---

## Version history (shipped)

| Version | Theme |
|---------|--------|
| 0.2 | Modular world, DST bootstrap |
| 0.3 | REPL, movement, explore |
| 0.4 | Character creation, bonuses, stats |
| 0.5 | Transcripts, fuzz harness, creation UX hints |
| 0.6 | Session phases, dungeon tiles, HP/AC sheet, DST crawl_start |