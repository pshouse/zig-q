# zig-q roadmap (v0.6 → v1.0)

**Product:** deterministic, scriptable **dungeon crawl** engine — create a character, descend floors, fight monsters, persist progress. No dialogue trees.

**Current release:** `1.4.0` (foundation, gear, living dungeon AI, survival clock).

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
- **Magic** — no spells, enchanted items, supernatural conditions, or arcane healing
- **Resurrection** — permadeath is final (see below)

---

## Post-1.0 world rules (v1.1+)

| Rule | Policy |
|------|--------|
| **No magic** | Mundane crawl only: physical weapons, armour, traps, poison, food, rest. No spell slots, wands, scrolls, enchantments, or magic-derived conditions (`charmed`, `paralyzed`, `petrified` stay parked). |
| **Permadeath** | Player HP → 0 or `.dead` ends the run. No respawn. Save slots hold **in-progress** crawls only; death invalidates continued play on that slot (clear message + `exit` or read-only tombstone transcript). |
| **Terrain** | Still regen-from-seed on load. **World objects** (floor items, corpses, traps) persist in save v2+. |
| **Conditions** | Applied through a single registry (`apply` / `remove` / `describe`); no ad-hoc `conditions.add` in commands. |
| **Speed** | `entity.movement` is the one speed field; encumbrance, exhaustion, armour, and conditions modify it. |
| **Time** | Successful `move` already ticks the clock; v1.1+ extends explicit action costs (`attack`, `wait`, `rest`, `sleep`, AI steps). |

---

## v1.1 — Foundation: world objects, perception, conditions

**Theme:** Engine contracts that unblock gear, AI, and needs. No inventory yet — lay pipes first.

| Deliver | Notes |
|---------|--------|
| **Action + time spec** | Documented costs per command; explore vs combat phase rules |
| **World objects** | Floor items, corpses, trap state in `WorldSave` schema v2 |
| **Save migration** | Load v1 saves → empty floor objects, default exhaustion 0; DST `save_v2_roundtrip` |
| **LOS v0** | Cardinal Bresenham from viewer tile; `look` and AI perception use same function |
| **Conditions framework** | `conditions.zig` registry; `remove`; `conditions` command; `exhaustion_level` (0–6) per entity |
| **Explore ↔ combat** | Adjacent hostile move or player `attack` enters combat; deterministic RNG order documented |
| **Permadeath** | Player death ends REPL; slot marked dead on save or delete-on-death; DST `permadeath` |
| **REPL help** | New `.repl_v11` profile; `.dst_v08` golden unchanged |

**Conditions activated:** deepen `dead`, `blinded`, `prone`; add `poisoned` (mundane toxin), `restrained` (trap/net), `exhaustion` level field (no sources yet).

**DST scenarios**

| Name | Proves |
|------|--------|
| `save_v2_roundtrip` | schema v2 floor objects + conditions survive load |
| `conditions_brawl` | prone/blinded/poisoned apply → combat modifiers → remove |
| `los_peek` | LOS hides creature behind wall; byte-stable seed 42 |
| `ambush` | monster steps adjacent → combat starts without player attack |
| `permadeath` | player dies; cannot move/attack; slot policy enforced |

**Fuzz:** condition/HP consistency; dead player cannot act; LOS deterministic; no illegal combat under `incapacitated` / `unconscious`.

**Acceptance:** `zig build test`, `fuzz`, all v1.0 DST scenarios unchanged, five new scenarios byte-identical ×2, `evidence-v11` markers.

---

## v1.2 — Items, weapons, armour, encumbrance

**Theme:** Mundane gear changes the sheet. Physical loot loop.

| Deliver | Notes |
|---------|--------|
| Inventory | `inventory`, `get`, `drop`, `examine`; player bag in save v2 |
| Floor loot | Seeded placement per `(seed, floor_index)`; corpses lootable after kill |
| Weapons | Damage die + traits (trip → `prone` on crit); no ranged in 1.2 |
| Armour | Body + shield slots; AC = armour + DEX mod; class proficiency gate |
| Encumbrance | STR-based carry cap; overload reduces `movement`; optional `restrained` at severe overload |
| Consumables | Mundane only: antidote, bandage (no magic healing — flat HP or stop bleed later) |

**Conditions activated:** `prone` stand action; `grappled` (weapon or monster); `incapacitated` / `stunned` (critical hit, not magic).

**DST scenarios**

| Name | Proves |
|------|--------|
| `loot_roundtrip` | pick up, save/load, still owned |
| `geared_brawl` | equip sword/armour; AC and damage in transcript |
| `corpse_loot` | kill goblin; `get` from corpse |
| `encumbered` | overload blocks move or applies exhaustion |

**Acceptance:** new scenarios + `reference_crawl` still byte-identical (unchanged gear path). New `reference_gear` scenario optional.

---

## v1.3 — Monster AI & dungeon interaction

**Theme:** Dungeon alive between fights. Mundane tactics only.

| Deliver | Notes |
|---------|--------|
| AI scheduler | One monster step per player action in explore; same RNG stream order |
| Behaviours | idle → patrol → chase → melee; flee when `frightened` |
| Pathfinding | Cardinal BFS; shared rules with player movement; anti-oscillation tie-break |
| Doors | open/close; optional locked doors (key item from v1.2) |
| Traps | step-trigger; apply `poisoned` / `restrained` via registry |
| Noise (optional) | Move/attack raises alert radius; deterministic decay |

**Conditions activated:** `frightened` (low HP, ally slain in LOS); maintain `grappled` across AI turns.

**DST scenarios**

| Name | Proves |
|------|--------|
| `hunt` | seed 42 patrol → chase path byte-stable |
| `flee` | frightened monster moves away |
| `trap_trigger` | step trap → condition → antidote clears |
| `door_route` | open door changes reachable path |

**Acceptance:** fuzz catches path oscillation; AI + combat handoff in `ambush` still passes.

---

## v1.4 — Needs: hunger, sleep, exhaustion

**Theme:** Time costs something. Survival pressure without magic.

| Deliver | Notes |
|---------|--------|
| Action clock | All major commands cost ticks; `time` shows hunger + fatigue |
| Hunger | Starvation adds `exhaustion` level over time; food items remove it |
| Sleep / rest | `rest` (short), `sleep` (long); `sleep` sets `.unconscious` while resting |
| Exhaustion table | Levels 1–6: speed penalty → disadvantage → HP max reduction → death at 6 |
| Win/loss framing | Optional `you died` / deepest floor reached on permadeath transcript |

**Conditions activated:** full mundane `exhaustion` progression; `poisoned` DoT on clock tick; `unconscious` during sleep.

**DST scenarios**

| Name | Proves |
|------|--------|
| `survive` | walk, eat, rest, save/load; meters + conditions consistent |
| `starve` | hunger → exhaustion → impaired movement |
| `sleep_cycle` | sleep clears fatigue; interrupt rule documented |

**Acceptance:** `reference_survive` byte-identical ×2; `reference_crawl` unchanged.

---

## Conditions roadmap (mundane only)

| Condition | Wave | Source |
|-----------|------|--------|
| `dead` | 1.0 | HP → 0; permadeath |
| `blinded` | 1.0 | torch gone out, trap dust (1.3+) |
| `prone` | 1.0 / 1.2 | trip, knockdown |
| `poisoned` | 1.1 / 1.4 | trap, spoiled food, monster |
| `restrained` | 1.1 / 1.2 | trap, net, severe encumbrance |
| `grappled` | 1.2 / 1.3 | weapon bind, monster hold |
| `frightened` | 1.3 | morale break |
| `incapacitated` / `stunned` | 1.2 | critical hit |
| `unconscious` | 1.4 | sleep, exhaustion 5+ |
| `exhaustion` | 1.1 field / 1.4 rules | hunger, fatigue, overload |
| `invisible` | — | **parked** (magic) |
| `charmed` / `paralyzed` / `petrified` / `deafened` | — | **parked** (magic or unused) |

---

## Backlog (post-1.4)

| Idea | Notes |
|------|--------|
| **Skeleton bones loot** | Skeleton corpses (`skeleton_*`) currently hold no item; goblins drop `short_sword`. Add mundane `bones` (light weight) lootable via `get from corpse` / `loot`. **Defer until a use exists** — junk-without-sink is poor UX. Candidate mundane sinks: trap bait (distraction), `rest` combo with `bandage`, future trade/shrine turn-in. Fits no-magic rules; no implement-before-use. Large corpses (`skeleton_*`) block tiles; small corpses (`goblin_*`) can be walked over. |

---

## Release gate (every v1.x)

1. `zig build` / `zig build test` / `zig build consumer-test`
2. `zig build fuzz` (10k default)
3. All shipped DST scenarios (v0.6–v1.0 goldens + new wave scenarios) byte-identical ×2 on seed 42
4. `evidence-vNN` step with observable markers
5. Save migration test when `schema_version` bumps
6. `fuzz-corpus/` note if new invariant failures published

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

## Version history (planned)

| Version | Theme |
|---------|--------|
| 1.1 | Foundation: world objects, LOS, conditions registry, permadeath, save v2 |
| 1.2 | Mundane items, weapons, armour, encumbrance, corpse loot |
| 1.3 | Monster AI, doors, traps, noise |
| 1.4 | Hunger, sleep, exhaustion, survival clock |