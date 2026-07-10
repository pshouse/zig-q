# v1.7 Fair Danger — implementation summary

Shipped to `main` as **1.7.0** (semver bump + wave-17 gate). Survival retune **#40 remains open** awaiting maintainer persona-fleet A/B (PR #50).

## Per-issue disposition

| Issue | Status | Branch / PR | Test added |
|------:|--------|-------------|------------|
| #26 exhaustion-5 recovery | **Merged** | `v17/track-a-exhaustion-26` → PR #46 | DST `collapse_sleep` |
| #27 in-combat step-toward | **Merged** | `v17/track-b-combat` → PR #48 | unit: advances; DST `combat_reposition` re-bless |
| #28 orphan-scenario gate | **Merged** | `v17/track-c-anti-recurrence` → PR #45 | `no orphan scenarios` in wave_gate |
| #29 migration pin | **Merged** | PR #45 | `migration chain v2 to v3 to v4 pins every step` |
| #30 load-time slot validation | **Merged** | `v17/track-d-polish` → PR #49 | `fromSave clears phantom equipment slots` |
| #31 doc-sync | **Merged** | PR #49 | help/README unit checks |
| #32 INT/CHA decision | **Merged** | PR #49 | `docs/INT_CHA_DECISION.md` + dragonborn +2 STR |
| #33 loot placement retry | **Merged** | `v17/track-a-loot-traps` → PR #47 | loot retry test; danger-floor only |
| #34 fuzz depth bound | **Merged** | PR #45 | `descend refuses past max_floor_depth` |
| #35 chase-memory | **Merged** | PR #49 | `chase memory pathing continues after LOS breaks` |
| #36 encumbrance dead tiers | **Merged** | PR #49 | binary model (penalty always 0) |
| #37 version.wave() guard | **Merged** | PR #49 | `wave and forGate reject unknown waves` |
| #38 ROADMAP stale row | **Merged** | PR #49 | docs only |
| #40 survival retune | **Open PR (do not merge)** | `v17/track-a-survival-retune-40` → **PR #50** | named knobs; george2 re-bless; 1→5 invariant retained |
| #42 combat lost-contact soft-lock | **Merged** | PR #48 | `lost contact ends combat so descend is not soft-locked` |
| #43 trap cut-vertex | **Merged** | PR #47 | `no trap on a spawn-to-stairs cut-vertex` |
| #39 epic | tracking | — | ledger updated by PR closes |

## Re-bless deltas

| Artifact | Change | Why |
|----------|--------|-----|
| `combat_reposition` DST assertions | Expect `goblin_0 advances to` instead of free forfeit | #27 intentional |
| `scarce_heals` plan_loot assert | Loosened exact `plan_loot=3` (bandages still scarce) | #33 danger-floor retry |
| deep-floor loot count inequality | Scarcity via bandages, not total count | #33 |
| trap seed-42 position pin | Determinism-only (cut-vertex skip may shift) | #43 |
| George II ironman (on #40 PR only) | Alive on floor 4, no permadeath | #40 retune (PR #50 only) |
| Frozen `reference_crawl` | **Untouched** | Guardrail |

## SD6 long-horizon

- George II: committed transcript + repl test (re-blessed on #40 branch)
- George III: **command log not recoverable** in repo → 1→5 provisioned descent invariant in `dst.zig` remains the long-horizon survival guard

## New issues filed

None discovered as separate defects during implementation (fleet-found #42/#43 already filed and fixed).

## PRs

| PR | Track | State |
|----|-------|-------|
| #45 | Track C anti-recurrence | Merged |
| #46 | Track A #26 | Merged |
| #47 | Track A #33+#43 | Merged |
| #48 | Track B #27+#42 | Merged |
| #49 | Track D polish | Merged |
| #50 | Track A #40 retune | **Open — awaits fleet** |
| (ship) | 1.7.0 wave-17 packaging | This branch |

## Named knobs on #40 (PR #50)

- `movement.deep_floor_extra_tick_exhaustion_min` = 2
- `survival.rest_ticks` = 4
- `survival.starving_threshold` = 85
- `survival.starvation_out_of_combat_period` = 3
- `dungeon.deep_floor_guaranteed_rations` = 2
