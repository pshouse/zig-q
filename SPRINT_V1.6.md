# Sprint plan — v1.6 "Depth danger, for real"

**Input:** design pass over merged v1.5.4 (6 parallel subsystem reviews) + [V1.6_PLAN.md](V1.6_PLAN.md).
**State of main:** 223/223 tests, fuzz clean, frozen golden intact. The 8 playtest fixes merged cleanly
in isolation — but composed, they left 3 new HIGH issues and one finding that reframes the sprint.

---

## The reframing finding

> **Monster damage is opt-in.** Player `attack` never advances the combat turn
> ([combat.zig:396](src/combat.zig:396)); monsters swing only inside `passTurnToOpponents`
> (`end turn` / `catch breath`) or as flee opportunity attacks. An attack-spamming player kills
> anything with **zero counterattacks** — empirically verified (8 consecutive attacks vs a goblin,
> 0 swings taken). Ambush compounds it: `enterCombat` always seats the player at turn 0, so even a
> monster that initiates concedes first strike ([combat.zig:233](src/combat.zig:233)).

Every lethality lever in V1.6_PLAN.md (danger-tier stats, elites, loot scarcity) is downstream of
monsters *getting a turn*. A stat-boosted floor-6 elite still deals zero damage to a player who
never passes the turn. **Initiative is the sprint's centerpiece; the plan's tracks are built on it.**

## Sprint decisions (made; revisit only with cause)

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Monsters counter after every player attack on danger floors (`danger_tier > 0`, i.e. floor ≥ 4).** Floors 1–3 keep the legacy alternation. | One gate (`dangerTier`) drives all v1.6 behavior; zero re-bless of the frozen golden; reads as designed ramp. Globalizing (Option B: re-bless `reference_crawl` at 1.6.0) is deferred — reopen only if playtest shows floors 1–3 feel broken. |
| D2 | **Ambusher acts first when a monster initiates combat** — globally, not floor-gated. | Zero golden exposure (`reference_crawl` runs with explore AI off). Makes sleep interruption meaningful once Track 3 lands. |
| D3 | **Cap `dangerTier` at 2 (floors 4–5); cut ogre/floor-6 content.** | Product scope and fuzz `max_floor_depth` are both 5 ([fuzz.zig:255](src/fuzz.zig:255)); tier-3 content would ship untested but player-reachable. Ogre moves to backlog. |
| D4 | **Own the `deep_floor` delta.** V1.6_PLAN's "no pre-1.6 golden descends that deep" is false — `deep_floor` asserts floor-5 `plan_loot=8` ([dst.zig:1522](src/dst.zig:1522)). Track 3 changes it; update those assertions + evidence markers in the same commit as the loot cut, documented as intentional. | Honest accounting beats a false guardrail (we removed one of those last sprint). |
| D5 | **All transcript-affecting changes land in one coordinated re-bless batch** (see protocol below). | Eight parallel worktrees worked for isolated fixes; balance work shares files and goldens — serialize it. |

---

## Track 0 — Stabilize (land first; small, independent, golden-safe) ✅ filed as chips

| Item | Anchor | Size |
|------|--------|------|
| Fix `error.NotAdjacent` process crash (move away mid-combat → `end turn`) | [combat.zig:389](src/combat.zig:389) | S |
| Fix walking-dead permadeath (out-of-combat starvation death never sets `player_dead`) | [survival.zig:203](src/survival.zig:203) | S |
| Clamp `catch breath` to `rest_fatigue_floor` (cross-PR regression vs 0444991) | [combat.zig:510](src/combat.zig:510) | S |
| Golden-drift unit test in `zig build test` (compare live crawl vs committed golden) | wave_gate.zig | S |

## Track 1 — Initiative (the enabler; do before Track 2 tuning)

| Item | Detail | Size |
|------|--------|------|
| Danger-floor counters (D1) | After a player `attack` resolves and combat continues, run `passTurnToOpponents` iff the target/any participant has `danger_tier > 0`. No new RNG on floors 1–3 paths. | M |
| Ambush first strike (D2) | `enterCombat` takes a first-actor param; `tryAmbushOnAdjacent` and sleep-interrupt pass the monster. | S |
| Wire `conditions.blocksAttack` | Zero call sites today ([conditions.zig:49](src/conditions.zig:49)): gate player attack/flee/catch-breath and monster swings in `processMonsterTurns`. | S |

## Track 2 — Danger tier, elites, scarcity (V1.6_PLAN Tracks 1–3, amended)

| Item | Amendments vs the plan | Size |
|------|------------------------|------|
| `dangerTier` stats, floor ≥ 4 | As planned (+tier attack, +tier dmg min-1, +3·tier HP, +tier/2 AC) but **cap 2** (D3). Fuzz invariants: tier ∈ [0,2]; player `danger_tier == 0` always (shared `attackModifier`/`targetAc` code paths). | M |
| Schema v4 | **First** pin the mislabeled migration: add `schema_version_v3 = 3` const ([save_state.zig:361](src/save_state.zig:361) currently jumps to the live constant), then add `EntitySave.danger_tier`, v3→v4 migration, `save_v4_roundtrip` loading both v2 and v3 saves. | M |
| Elites: `hobgoblin`, `skeleton_warrior` | Draw from a **new** `eliteRng(seed, floor)` stream only when floor ≥ 4 (floor-3 `depthBonusRng` positions must not shift). No ogre. | M |
| Loot scarcity, floor ≥ 4 | Bias away from **bandage AND cap rations** (survival reader: depth tiers add ~+1 ration/floor/tier, erasing hunger pressure exactly where danger starts). Update `deep_floor` assertions + `evidence_v15` markers in the same commit (D4). Strengthen `scarce_heals` to a bandage-share assertion (floor-2 baseline is exactly 1 bandage — "fewer than baseline" only distinguishes 0 from 1). | M |
| New DST scenarios | `deadly_floor` (danger-tier hit lands, `mod ≥ 0`, `damage ≥ 1`), `elite_brawl`, `scarce_heals`, `save_v4_roundtrip`, plus a `deadly_floor` step proving **flee works under danger-tier pressure** (ties the escape valve to the new teeth). | M |

## Track 3 — Survival economy becomes real

| Item | Detail | Size |
|------|--------|------|
| Live sleep/rest interruption | Run gated explore AI inside `cmdRest`/`cmdSleep` tick loops so the dead "interrupted by combat" branches ([commands.zig:693](src/commands.zig:693)) become reachable. Today `wait` (1 tick) risks ambush while `sleep` (24 ticks, unconscious) is perfectly safe — inverted. With D2, being ambushed asleep finally costs something. | M |
| Unconscious blocks action | Unconscious player can currently still `move`/`eat` (move path checks only encumbrance `blocksMove`, [commands.zig:1004](src/commands.zig:1004)). Also add a warning at exhaustion 4 — the real lockout death threshold is fatigue 85, not 95, with no counterplay message. | S |
| Tier 1–2 gets a cost | Rest floor at 20 is cosmetic while tiers 1–2 carry zero penalty. Minimum viable: implement the already-promised movement penalty for real (stats hint says "movement −1" but only the display uses it, [inventory.zig:167](src/inventory.zig:167)). | M |

## Track 4 — Gear matters again

The weapon-die fix overshot: with a one-weapon catalog (short sword d6) and class baselines d8–d12,
**no weapon in the game can raise anyone's damage** — loot is damage-inert.

| Item | Detail | Size |
|------|--------|------|
| Weapon roster, floor ≥ 4 loot | `war_axe` d10, `greatsword` d12 (mundane), spawning only in the danger-floor branch. Gives d8/d10 classes a real progression through the upgrade-only `max()`. | M |
| Mundane quality bonuses | Flat `damage_bonus` on items ("fine" +1) so even the d12 barbarian has a progression path. Modifier-only: zero RNG-draw changes. | M |
| Equip advisory | "you keep your innate d12; the short sword adds its trip trait" — lands in the re-bless batch (touches `geared_brawl`). | S |
| Combat action economy | `equip`/`unequip` are currently free mid-combat while `get`/`drop` are blocked — gate or cost them; add explore-path tick. | S |

## Track 5 — Gate, tests, docs (close the loop)

| Item | Detail | Size |
|------|--------|------|
| v16 wave-gate plumbing | `version.zig` v16 + semver 1.6.0; wave-16 plan entry incl. the **orphaned** `rest_floor`/`combat_flee`/`catch_breath` scenarios (in no gate plan today, [wave_gate.zig:84](src/wave_gate.zig:84)) + Track 2's four; `run_migration` for v4; `evidence-v16` + `gate-v16` build steps. | M |
| Portable gate scratch | Replace the dead hard-coded temp dirs ([wave_gate.zig:6](src/wave_gate.zig:6), [build.zig:268](build.zig:268)) with repo-relative `.gate-scratch/` (+ `ZIG_Q_SCRATCH` override) so `gate-v16` runs on a clean checkout. *(automate-when-possible)* | S |
| Backfill DST scenarios | 5 of the 7 merged fixes are unit-test-only against the scripted-first contract: unequip cycle, drop-clears-slot, bare-`loot` corpse preference, weaker-weapon baseline. | M |
| Doc-sync pass | README combat line (flee/catch-breath missing), both help `ai:` lines (wrong post-merge), delete dead `.repl` profile, CLI `--help` (+`--playtest`, stale roadmap ref), version-table order. | M |
| Floor-1 AI gate symmetry | `wait` on floor 1 runs monster AI but `move` doesn't — hoist the `floor_index < 2` exemption into `finishExploreAction`. | S |
| Fuzz gaps | Add `retreat` template; danger-tier invariants; walking-dead invariant. | S |
| ROADMAP | Insert v1.6 entry (plan §9); re-slot bones sink / locked doors / permadeath summary to an explicit 1.7+ row. | S |

## Harvested ironman regression (wired)

`transcripts/session-george2-ironman-seed7.txt` — a 177-command ironman playtest (seed 7, played
against pre-fix v1.6.0) that exposed monster mass-starvation, the walking-dead permadeath hole, the
deep-floor food-economy spiral, and the `*`-glyph ambiguity. Re-recorded against v1.6.1 and wired as
the suite's first **long-horizon** test (`harvested george2 ironman transcript is deterministic and
permadeath-locked`, [repl.zig](src/repl.zig)): replay byte-identical ×2, and the player's starvation
death now ends in a permadeath lockout — same input that found the bugs, asserting the fixes. If
survival tuning changes this route's outcome, re-bless the transcript deliberately in that change.

## Explicitly cut from this sprint

- Ogre / floor-6 / tier-3 content (D3) — backlog.
- Global initiative rework + `reference_crawl` re-bless (D1 Option B) — v1.7 candidate.
- Encumbrance graduated-vs-binary rationalization (dead `isOverloaded` code) — becomes interesting
  once heavier gear exists; revisit at v1.7 with the roster in hand.
- Parser error-style standardization, equip alias symmetry (`wield`/`wear`) — fold into a future
  doc/UX pass; not gameplay-blocking.

## Sequencing & merge protocol (lesson from the 8-way parallel merge)

1. **Track 0 chips in parallel** — independent files, golden-safe. Merge before anything else.
2. **Track 1 serially** (one branch): combat.zig is the hot file; initiative semantics must settle first.
3. **Track 2 + Track 4 roster** next — dungeon/monsters/items/save_state; mostly disjoint from Track 1's diff but rebase on it.
4. **Track 3** after Track 1 (needs D2's first-actor plumbing for sleep ambush).
5. **Track 5 last** — gate/doc files reference everything; land after code settles.
6. **One re-bless batch commit**: `deep_floor` assertions + `evidence_v15` markers + equip-advisory
   golden updates + any transcript-shape changes, together with their code, `zig build
   update-reference-golden` **not run** (frozen golden must stay byte-identical — that's the proof),
   full gate green before merge.

**Sprint acceptance** (extends the standing release gate):
`zig build test` / `consumer-test` / `fuzz` green; all pre-1.6 goldens byte-identical ×2 **except the
documented `deep_floor` floor-5 delta**; frozen `reference_crawl` untouched; new scenarios
byte-identical ×2; `evidence-v16` markers; a floor-4 monster **lands unavoidable damage on an
attack-spamming player** (the anti-regression test for the initiative hole); `gate-v16` runs on a
clean checkout.
