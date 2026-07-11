# Design memo — Character-system rework ("Three Axes")

**Status:** approved direction, phased implementation pending
**Supersedes the deferral in:** [`INT_CHA_DECISION.md`](INT_CHA_DECISION.md) (#32, option C → now doing option B)
**Target:** a version-gated wave, ~v1.8.0 (`reference_crawl` stays pinned at 1.1.0)

## Problem (confirmed against the code)

- Only **4 of 6** attributes drive any mechanic. **STR** is overloaded (to-hit + damage + carry); **DEX** = AC only; **CON** = HP only; **WIS** = trap-spotting only; **INT** and **CHA** are rolled/shown/saved but **never read**.
- **Classes are a scalar**, not a set of tradeoffs: `Class` carries only `{name, hit_die}`, and `hit_die` drives *both* HP and the innate damage die (`world.zig:231`). So barbarian(d12) ≥ fighter(d10) ≥ bard(d8) is a total order. Bard is further **strictly dominated** — it's the only class not leather-proficient, so its AC collapses to 10 (`items.zig:80`, `inventory.zig:177`). No reason to ever pick it.
- Result: optimization collapses to one build (Elf +2 DEX for AC × Barbarian d12 for HP+damage). Nothing creates competing optima.
- Bonus: `Race.speed` (30/25/30) and the `movement:` sheet field are **dead code** — every character moves identically.

**Hard scope (permanently parked):** no magic, no magic-derived conditions (charmed/paralyzed/petrified), no dialogue/NPC chat. Every mechanic here is mundane and physical. This is *why* INT/CHA/Bard are hard, and it shapes every choice below.

## Thesis

One **keystone** + small, per-path-gated systems make all six stats live and produce a rock-paper-scissors class triangle **at zero golden cost** — the frozen `reference_crawl` (dwarf/barbarian, floors 1–3) stays byte-identical.

**Keystone — class-routed attack stat.** A pure helper `attackAbbr(ent)`/`damageAbbr(ent)` returns `"DEX"` iff `class.name == "rogue"` **and** the wielded weapon is light/unarmed; else `"STR"`. `combat.zig:89` (to-hit) and `combat.zig:103` (damage) route through it. Barbarians and monsters (`class.name == "monster"`) both resolve to STR, so every existing `roll=… mod=…` line is bit-identical. This is the one lever that gives DEX an offensive home and dissolves the Elf/Barbarian monopoly.

## Six stat hooks (all live)

| Stat | Hook | Notes |
|---|---|---|
| **STR** | class-routed to-hit + damage (STR classes) **+ carry** | de-loaded from 3 jobs → 2 |
| **DEX** | AC (all) **+ Rogue finesse to-hit/damage + backstab gate + sneak check** | pulls weight for one class |
| **CON** | max HP (all) **+ shortens poison DoT duration** (deterministic clamp, no draw) | tank stat gains weight |
| **INT** | `disarm` + `pick` commands — `d20 + INT mod ≥ DC` | one draw, new command paths |
| **WIS** | trap **spotting** (unchanged) — now a **prerequisite** for INT `disarm` | two-stat synergy: WIS notices, INT defeats |
| **CHA** | `intimidate <target>` — `d20 + CHA mod ≥ moraleDC` → mundane `frightened` | active-only; pool-bought (no racial patron) |

## Three classes (tradeoff triangle)

`Class` struct unchanged (`{name, hit_die}`) — no schema change; bard→rogue is a name lookup.

| Class | Attacks with | hit_die | Armour | Signature | Real downside |
|---|---|---|---|---|---|
| **Barbarian** (STR brute) | STR | 12 | leather (kept) | `reckless` toggle: **advantage** on attack rolls, **−4 AC** until next turn (default OFF) | AC-soft while raging; no skills (eats traps); loses to attrition |
| **Fighter** (STR/CON discipline) | STR | 10 | leather **+ exclusive shield** + retains DEX-to-AC-in-armour | `guard` stance (+2 AC, skip attack); `discipline` (damage-die 1→2 no-fumble clamp); CON-scaled second wind | lowest burst; slow if Dwarf; weak utility |
| **Rogue** (DEX finesse — replaces Bard) | DEX (light/unarmed only) | 8 | leather (**now proficient** — fixes AC-collapse) | `backstab` (+1 weapon die) vs a target you're **hidden** from, or first-strike-unaware, or frightened; owns INT skills at −2 DC | lowest HP + innate die; backstab needs setup (see sneak) |

**`reckless` = advantage-based** (decided): advantage on the attack roll + −4 AC, no flat damage bonus. Advantage machinery already half-exists (`attackModifier` advantage path; disadvantage = min-of-2d20 is live). Adds one d20 on the reckless-ON branch only — never in existing goldens. Thematically fixes the low-STR-accuracy grind.

**Backstab requires `sneak`** (decided): backstab is not free on every initiated fight. It fires only against a target you're **`hidden`** from (via a successful `sneak`), a genuine first-strike-while-unaware, or a `frightened` target — a repeatable-but-fallible tempo action, not guaranteed alpha.

**Weapon-die loophole closed:** a static `heavy: bool` weapon trait. Rogue DEX-routing + backstab apply **only** with a light/finesse/unarmed weapon; equipping a heavy weapon (war_axe/greatsword) reverts the Rogue to STR with no backstab. Severs the `weaponDamageDie = max(weapon, baseline)` exploit (`inventory.zig:212`). Static field → zero new draws, not persisted.

**Backstab ordering fix (mandatory):** `enterCombat` flips the target to `.fighting` (`combat.zig:286`) *before* damage resolves, so the handler must **snapshot `target.char.status == .exploring` BEFORE `enterCombat`** and pass a `was_unaware` flag into damage resolution.

## New stealth model — `sneak` / `hidden`

- New `sneak` command (explore phase, out of combat): `d20 + DEX mod ≥ DC`, DC scaling with the nearest monster's distance/LOS. Success sets a transient **`hidden`** flag on the player.
- While `hidden`, a Rogue's next initiated attack qualifies for `backstab`.
- `hidden` breaks on: attacking, or a monster spotting the player (LOS + distance check on the monster's turn).
- **Golden-safe:** the monster spot-check fires **only when `player.hidden` is true** — a state no shipped scenario ever enters — so existing combat transcripts keep their exact draw order.
- **Transient state → no schema bump** (cleared on save/load, like `frightened`/`reckless`).

## Mundane fear — provably distinct from parked `charmed`

A `frightened` monster (`conditions.zig:55`, already grants attack-disadvantage) on its turn (`processMonsterTurns`, `combat.zig:449`) does **not** attack; it steps **away** (existing `firstStepToward`, inverted) or cowers if boxed in. Structural distinctness from `charmed`: (a) cause is a physical menacing display resolved by a CHA-vs-HP/tier check — no mind-effect; (b) it never makes the creature approach, aid, or fight *for* the player — only hesitate/flee; (c) full-HP/elite targets resist (toughness, not a magic save); (d) transient/self-clearing. This is DCSS/Brogue "afraid," never "charmed" (which is parked and used nowhere). `intimidate` is **active-only** so no existing combat transcript gains a draw.

## Races (second axis: speed)

| Race | Bonus | speed | Patron / pairing |
|---|---|---|---|
| dragonborn | +2 STR | 30 | STR → Barbarian |
| dwarf | +2 CON | 25 (slow) | CON → Fighter |
| elf | +2 DEX | 35 (fast, 30→35) | DEX → Rogue |
| **human (NEW, idx 4)** | **+2 INT** | 30 | INT → Rogue-skills / Fighter trap-breaker |

CHA gets **no racial patron** — it stays a pool-bought utility stat so it can't become the new dead pick.

**Speed — golden-safe realization.** Do **NOT** copy `race.speed` into `ent.movement` (that field prints `movement: 30` at `reference_crawl.txt:107`; writing 25 there re-blesses the frozen golden with zero dice). Instead **read `ent.char.race.speed` directly** inside the existing `movement.zig:69` deep-floor branch (`floor_index >= 4`, already the gate that keeps floors 1–3 frozen): slow (<30) pays +1 tick/move on floors ≥4; fast (>30) suppresses one deep-floor extra-tick; neutral unchanged. Stateless, no schema bump, floors 1–3 untouched. On danger floors the fast Elf kites the survival clock; the slow Dwarf pays attrition for its bulk. `stats` still prints `movement: 30` at base — an honest legibility limitation, not a bug.

## Dominance analysis (≥3 non-dominated optima)

A **3-cycle** across {burst, durability, skirmish}: Barbarian > Fighter on burst, Fighter > Barbarian on durability; Fighter > Rogue on durability, Rogue > Fighter on mobility+utility; Rogue > Barbarian on utility+mobility+AC, Barbarian > Rogue on HP+per-hit. Incomparable in all three directions ⇒ no strict dominance.

1. **Dragonborn/Barbarian** (STR burst) — best per-hit + sustained DPR; worst AC (reckless), eats traps, loses to attrition.
2. **Dwarf/Fighter** (CON tank) — best AC+HP+consistency; lowest burst, slow, weak utility.
3. **Elf/Rogue** (DEX skirmisher) — best alpha (backstab), AC-without-armour, skills, fast; lowest HP, conditional burst.
4. **Human/Rogue or Human/Fighter** (INT specialist) — best trap-disarm/lockpick; a real niche.

**Anti-dominance guards:** hit_die 8 couples Rogue's lowest HP *and* innate die; light-weapon-only finesse closes the loot loophole; backstab gated behind sneak (fallible, costs tempo). Elf's +2 DEX is **offensively inert for STR classes** (they route through STR). Fighter's dead-middle avoided by exclusive shield + retained DEX-to-AC + RNG-free consistency.

**Watch item:** sneak makes DEX do five Rogue jobs (AC + finesse to-hit + finesse damage + backstab gate + sneak check). The survival-fleet A/B is the referee on whether Rogue is oppressive.

## Determinism + golden plan

**Frozen `reference_crawl` stays byte-identical** — the primary constraint the whole plan is built around.

- New d20 draws (`disarm`/`pick`/`intimidate`/`sneak`) live in brand-new command handlers `reference_crawl` never issues.
- `backstab` extra die is appended after the existing `rollDamage` die, on the rogue-qualifying branch only (no shipped golden selects a rogue).
- `reckless` advantage die fires only on the reckless-ON branch (new toggle).
- Monster spot-check for `hidden` fires only when the player is hidden (a state no golden reaches).
- `reckless`/`guard`/`discipline`/CON-poison-resist/speed-tick are flat/deterministic — zero draws.
- `attackAbbr`/`damageAbbr` swap reads a different stat's mod but draws nothing; barbarian→STR and monster→STR ⇒ every existing draw preserved.

**No save-schema bump** for the core wave (bard→rogue is a name lookup; `.locked` doors already persist; `frightened`/`reckless`/`guard`/`hidden` are combat/explore-transient and saves occur out of combat; `heavy` is a compile-time item def).

**Deferred (separate later wave, real cost):** `search`/hidden-caches — needs world-gen seeded placement + a v4→v5 schema bump + migration + roundtrip DST. Kept out so the core stays schema-free; INT rides on `disarm`+`pick` in v1.

## Phased plan (each phase byte-diffs `reference_crawl`)

- **Phase 0 — attack seam** (zero draws, zero golden impact): add `attackAbbr`/`damageAbbr`, route `combat.zig:89`/`:103`. Gate: build/test/consumer-test + `reference_crawl` byte-identical.
- **Phase 1 — classes** (draw-free specials): bard→rogue rename (idx 3 preserved); rogue leather-proficient; Fighter exclusive shield; static `heavy` weapon trait; `reckless` (advantage, −4 AC); `guard`; `discipline`; CON second-wind. Update bard→rogue tests.
- **Phase 2 — races + speed:** elf 30→35; append human {+2 INT, 30} at idx 4; widen race picker; `findRace` learns "human"; read `race.speed` in the floor-≥4 branch (never write `ent.movement`).
- **Phase 3 — INT/CHA commands:** `disarm`, `pick`, `intimidate` + the `frightened` flee/hesitate branch; CON→poison-duration.
- **Phase 4 — stealth/backstab:** `sneak`/`hidden` model; monster spot-check gated behind `hidden`; `backstab` with the pre-combat `.exploring` snapshot; `reckless`/`guard`/`sneak`/`backstab` command wiring.
- **Phase 5 — evidence + release gate:** evidence-vNN + gate chain; full gate (build/test/consumer-test → fuzz 10k → all DST byte-identical ×2 seed 42 → new evidence); survival-fleet A/B baseline vs candidate to confirm no dominant build.

New DST scenarios: `rogue_backstab`, `disarm_pick`, `intimidate_flee`, `sneak_hidden`, `elf_speed_deepfloor`, `human_int_trapbreaker`. New fuzz invariants: disarmed trap removed; a frightened monster never both attacks and flees in one turn; picked door reaches `.open`; `race.speed ∈ {25,30,35}`; backstab die fires only when (hidden|unaware|frightened) AND light weapon; `hidden` clears on attack.

## Decisions locked (this memo)

1. **4th race = Human (+2 INT).** CHA stays pool-bought (no patron).
2. **Backstab requires `sneak`** (fallible stealth), not free-on-initiation.
3. **`reckless` = advantage-based** (advantage on to-hit, −4 AC, no flat damage).
4. **`search`/hidden-caches deferred** to a later schema-bumping wave; INT = disarm+pick for v1.

## Open balance knobs (validate via survival-fleet A/B, not guesswork)

reckless AC penalty magnitude; intimidate `moraleDC` curve (must stay hesitate/flee, never a reliable turn-skip lock); speed tick magnitude on floors 4–5; CON→poison scaling; sneak DC curve; whether Human/Rogue is genuinely non-dominated by Elf/Rogue or needs a small skill-DC edge.
