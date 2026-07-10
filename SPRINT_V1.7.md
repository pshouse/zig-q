# Sprint plan — v1.7 "Fair Danger"

**Backlog:** GitHub issues [#26–#40](https://github.com/pshouse/zig-q/issues), epic [#39](https://github.com/pshouse/zig-q/issues/39).
**State:** v1.6.1 shipped. Danger tier works — monsters counter, elites roam, ambushes bite. But three
live playtests and a 6-reader design-pass audit (35 predicted issues: 17 fixed, 11 partial, 7 open)
exposed two systemic problems this sprint exists to fix.

---

## The two findings that shape the sprint

> **1. The crawl executes instead of threatens.** Across George I→III, total monster damage taken was
> 2, ~2, and 3. Nobody died to a blade. George II *starved* on floor 4; George III *exhausted* into an
> unrecoverable soft-lock two tiles from the stairs. The danger tier gave monsters teeth, but the
> **survival economy overswung from v1.5's slack to v1.6's strangulation** — it now kills *optimal* play
> on a timer, which is the opposite of pressure. ([#40](https://github.com/pshouse/zig-q/issues/40),
> [#26](https://github.com/pshouse/zig-q/issues/26), [#33](https://github.com/pshouse/zig-q/issues/33))

> **2. Predicted-but-unfiled ships broken.** The exhaustion-5 lockout was *predicted* in the last design
> pass, written into SPRINT_V1.6 Track 3 as prose — and shipped unfixed, while neighbouring code was
> reworked and a *misleading* warning added on top of it. The audit found this is the **dominant pattern**:
> 11 "neighbour-fixed-core-open" partials, and the bug class **recurred within the sprint twice**
> (orphaned scenarios; the save-migration mislabel). Everything filed as an actionable task got fixed;
> everything left as prose did not.

Track 1 is a *product* problem. Track 2 is a *process* problem. This sprint fixes both, and the process
fix is load-bearing — without it, v1.8 re-learns this lesson.

## Decisions (made; revisit only with cause)

| # | Decision | Rationale |
|---|----------|-----------|
| SD1 | **Survival is pressure, not a timer.** Retune [#40](https://github.com/pshouse/zig-q/issues/40) so a *provisioned player on a direct stairs route survives a 1→5 descent on every fuzzed seed*; a careless/greedy player still dies. | Restores the intended risk curve; makes the acceptance criterion objective and fuzzable. |
| SD2 | **Collapse gets a recovery path.** Fix [#26](https://github.com/pshouse/zig-q/issues/26) by letting an unconscious (exhaustion-5) player `sleep` (keeping the ambush-interrupt risk), or auto-collapse into forced sleep. No soft-locks — exhaustion punishes, never bricks. | A dead-end state with zero counterplay is never acceptable; the fix is small and self-contained. |
| SD3 | **Danger must land.** Fix [#27](https://github.com/pshouse/zig-q/issues/27) so in-combat monsters step toward the player — disengaging costs something. Floor-1-3 initiative (C1) stays deferred to a dedicated re-bless sprint; note the interaction. | Without monster movement the danger-tier counter is dodgeable by walking one tile away; C1's `reference_crawl` re-bless is out of scope here. |
| SD4 | **Every fix references its issue and adds a test; the class-killers land first.** [#28](https://github.com/pshouse/zig-q/issues/28) (orphan-scenario gate test) and [#29](https://github.com/pshouse/zig-q/issues/29) (pin every migration step) ship in week 1 so the two recurring classes **cannot** recur a third time. | This is the direct process fix for finding #2. A prediction without an owned, tested ticket is just a well-worded way of shipping the bug. |
| SD5 | **Balance is validated with data, not vibes.** Before committing tuning numbers for [#40](https://github.com/pshouse/zig-q/issues/40), run an **agent persona-playtest fleet** (speedrunner / hoarder / cautious / exploit-hunter × many seeds) on `current` vs `retuned` and diff the **death-cause distribution**. Ship when deaths shift from "clock" to "player error / monsters." | The retune is the riskiest change; determinism makes fleet A/B cheap and objective. Realises the parked playtest-fleet idea where it's load-bearing. |
| SD6 | **Add long-horizon coverage.** Harvest the George II and George III sessions as committed regressions, and add an invariant test that drives a full 1→5 descent (past the floor-4 / 95-tick horizon that hid every survival bug). | The whole suite stayed green over two fatal bugs because nothing reached that far. Fix the blind spot, not just the bugs. |

---

## Track A — Survival made fair *(the headline; SD1/SD2/SD5)*

| Issue | Work | Size |
|-------|------|------|
| [#26](https://github.com/pshouse/zig-q/issues/26) | Exhaustion-5 recovery path (let collapsed players sleep / force-collapse). **DST**: cross fatigue 85, assert a recovery action succeeds. | S |
| [#40](https://github.com/pshouse/zig-q/issues/40) | Retune deep-floor move multiplier, rest tick cost, starvation onset/rate. **Fuzz/DST invariant**: provisioned direct-route player survives 1→5 on all seeds. Numbers set by the SD5 fleet A/B, not guesswork. | L |
| [#33](https://github.com/pshouse/zig-q/issues/33) | Retry loot placement on unwalkable tiles so intended food/loot counts are met. | M |

**Validation:** SD5 fleet report attached to the [#40](https://github.com/pshouse/zig-q/issues/40) PR — baseline vs retuned death-cause histograms + median floor reached per persona.

## Track B — Danger lands *(SD3)*

| Issue | Work | Size |
|-------|------|------|
| [#27](https://github.com/pshouse/zig-q/issues/27) | In-combat monsters take one deterministic step toward the player (`firstStepToward`, no RNG) when out of reach. **DST**: player steps away, ends turn, monster closes. Re-bless `combat_reposition` intentionally. | M |

## Track C — Anti-recurrence & coverage *(SD4/SD6; land week 1)*

| Issue | Work | Size |
|-------|------|------|
| [#28](https://github.com/pshouse/zig-q/issues/28) | Wire the orphan v1.6 scenarios into the gate **and** add the test that fails when any `scenarioByName` entry is absent from a wave plan. | M |
| [#29](https://github.com/pshouse/zig-q/issues/29) | Pin every migration step to a fixed target; test the full v2→v3→v4 chain. | S |
| [#34](https://github.com/pshouse/zig-q/issues/34) | Bound in-game descent to the fuzzed depth, or raise `max_floor_depth` — no reachable-but-unfuzzed floors. | S |
| — | Harvest George II + George III sessions as committed regressions; add the 1→5 descent invariant (SD6). | M |

## Track D — Correctness & polish

| Issue | Work | Size |
|-------|------|------|
| [#30](https://github.com/pshouse/zig-q/issues/30) | Validate equipment slots at save-load; drop the masking re-add guard. | S |
| [#31](https://github.com/pshouse/zig-q/issues/31) | Finish the doc-sync pass (help `ai:` lines, README commands + layout, `--live-ai`/`--playtest`). | M |
| [#32](https://github.com/pshouse/zig-q/issues/32) | INT/CHA decision **memo** (recommend: move dragonborn's +2 to a live stat + document as cosmetic; defer removal). | S |
| [#35](https://github.com/pshouse/zig-q/issues/35) | Chase-memory so chokepoint baiting works (last-seen-tile pathing for N turns). | M |
| [#36](https://github.com/pshouse/zig-q/issues/36) · [#37](https://github.com/pshouse/zig-q/issues/37) · [#38](https://github.com/pshouse/zig-q/issues/38) | Encumbrance dead tiers · `version.wave()` guard · ROADMAP stale row. | S each |

## Explicitly out of scope

- **C1** (floor-1-3 initiative counter) — needs a `reference_crawl` re-bless (Option B); its own sprint.
- **INT/CHA removal** (#32 option A) — Option-B-scale golden churn; this sprint only decides + documents.
- New v1.7 *content* (locked doors, bones sink, permadeath summary — the old ROADMAP 1.6+ row): parked
  until the danger is *fair*. A crawl that executes optimal play isn't ready for more content.

---

## Sequencing & merge protocol

1. **Week 1, parallel:** [#26](https://github.com/pshouse/zig-q/issues/26) (unblocks safe deep-floor testing), [#28](https://github.com/pshouse/zig-q/issues/28) + [#29](https://github.com/pshouse/zig-q/issues/29) (class-killers — stop recurrence *before* more code lands), the II/III harvests.
2. **Then:** Track A [#40](https://github.com/pshouse/zig-q/issues/40) retune on a branch → SD5 fleet A/B → tune → merge. Track B [#27](https://github.com/pshouse/zig-q/issues/27) in parallel (disjoint file from the survival work).
3. **Then:** Track D cleanup.
4. **One re-bless batch** for every transcript-affecting change (`combat_reposition`, any survival-retune goldens, `deep_floor` counts if loot changes) — committed atomically with its code, frozen `reference_crawl` untouched (the guardrail proof).

**Ticket discipline (the point of the sprint):** every PR closes its `#issue` and adds a test; no issue
closes green without one. If new work surfaces a defect, it becomes a filed issue *before* the PR merges —
never a paragraph.

**Acceptance (extends the standing release gate):**
`zig build test` / `consumer-test` / `fuzz` green; all pre-1.7 goldens byte-identical ×2 except documented
deltas; frozen `reference_crawl` untouched; **the 1→5 provisioned-survival invariant passes on all fuzzed
seeds**; the two class-killer tests are live (a new orphan scenario or mislabeled migration fails the
suite); George II + III regressions committed; the SD5 fleet report shows deaths shifted off the clock.
