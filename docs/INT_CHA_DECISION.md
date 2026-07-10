# Decision memo — INT and CHA (#32)

**Sprint:** v1.7 Fair Danger  
**Status:** decided (option C)  
**Date:** 2026-07-10

## Problem

Only four ability scores drive mechanics today:

| Score | Used for |
|-------|----------|
| STR | attack mod, damage, carry capacity |
| CON | HP |
| DEX | AC only |
| WIS | trap perception (d20 + mod) |

**INT** and **CHA** are rolled, assignable, shown on the sheet, and persisted — but never read by combat, survival, or perception. Dragonborn's racial **+2 CHA** therefore buffed a dead stat.

## Options and golden impact

| Option | Change | Golden blast radius |
|--------|--------|---------------------|
| **A — Remove** | Drop INT/CHA from assign (4 picks), pool, sheet, save schema + migration; move dragonborn bonus | **Huge.** Frozen `reference_crawl` prints the 6-line ability block and uses a 6-pick `assign`. Option-B-scale re-bless of every creation transcript. Version-gated only. |
| **B — Give a mundane use** | INT → trap-disarm / map-memory; CHA → future merchant/shrine | Medium design + new systems; not a sprint-polish item. No removal churn. |
| **C — Cosmetic + live racial** | Keep INT/CHA as cosmetic sheet stats; move dragonborn's +2 onto a live stat; document | **Small.** Playthrough / dragonborn paths show different STR/CHA numbers. `reference_crawl` uses dwarf (race 2) — **untouched**. |

## Decision

**Ship option C now; defer A (and any B design) to a dedicated re-bless sprint.**

### Implemented in v1.7

1. Dragonborn racial bonus: **+2 STR** (was +2 CHA).
2. Docs (README + this memo) state INT/CHA are **cosmetic** until a mundane use lands.
3. Stats remain rolled/assigned/shown/persisted — no schema change.

### Explicit non-goals this sprint

- Do **not** remove INT/CHA (option A) — golden blast radius is out of scope.
- Do **not** invent a half-baked INT/CHA mechanic just to "use" them (option B) without design.

## Revisit triggers

- A content wave that needs trap-disarm / social / lore checks (option B).
- A deliberate reference_crawl re-bless sprint that can absorb option A.
