# zig-q roadmap (v0.6 → v1.0)

**Product:** deterministic, scriptable **dungeon crawl** engine — create a character, descend floors, fight monsters, persist progress. No dialogue trees.

**Current release:** `1.0.0` (stable crawl engine, public API, reference crawl regression).

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

## v0.7 — Combat & monsters (shipped)

**Theme:** Turn-based fights in the dungeon.

---

## v0.8 — SQLite persistence (shipped)

**Theme:** Save the crawl; resume later.

---

## v0.9 — Dungeon generation & scenarios (shipped)

**Theme:** Seed-fixed floors; authored crawl scripts.

| Deliver | Notes |
|---------|--------|
| Room + corridor generator | seeded from `(seed, floor_index)`; deterministic monster placement |
| Stairs down | `descend` on door (floor 1) or `>` stairs (floor 2+); regen terrain on save/load |
| Scenario files | `scenarios/*.txt` loaded via `zig build dst -- @path seed` |
| DST `descend_crawl` | creation, floor-1 explore, descend, floor-2 look/stats |
| **Fuzz** | `descend` templates; floor depth cap 5; one player invariant |

Terrain regenerates from seed on load (documented regen-only persistence for layout).

---

## v1.0 — Crawl engine release (shipped)

**Theme:** Stable library + CLI for a full descent.

| Deliver | Notes |
|---------|--------|
| Public `zig_q` API | documented World, crawl, combat, SQLite; `zig build consumer-test` |
| Reference crawl | DST `reference_crawl` floor 1→3, fight + save mid-run (seed 42) |
| Semver policy | `1.0.0`; transcript records `# version=1.0.0` |
| Release gate | `build`, `test`, `dst *`, `fuzz`, reference-crawl determinism |
| **Fuzz** | 10k+ default; repro procedure in `fuzz-corpus/` |

**Non-goals:** 1.0 ≠ content-complete bestiary; 1.0 = stable crawl engine.

---

## Shipped — REPL UX from playthrough harvest (v0.8+)

Source: `transcripts/session-1783208416-seed42.txt` (seed 42). `expandInput()` / `executeLine()` expand shorthands before `parseLine`; REPL, DST, and fuzz use the real path.

| Input (as typed) | Expansion |
|------------------|-----------|
| `l` | `look` |
| `m n` | `move n` |
| `move nw` | `move n` then `move w` |
| `move w w` | two `move w` steps |
| `move w; move w` | semicolon chain |

DST `playthrough` runs without `unknown command` for these inputs. Harvested transcripts stay byte-stable (raw `> command` lines unchanged).

**Non-goals:** fuzzy NLP, aliases outside roguelike conventions, changing v0.6 golden DST transcripts retroactively.

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
| 0.7 | Turn combat, monsters, attack/end turn, DST brawl |
| 0.8 | SQLite save/load, DST save_roundtrip |
| 0.9 | Seeded floor generation, descend, scenario files |
| 1.0 | Public API, reference crawl 1→3, evidence-v10, fuzz-corpus |