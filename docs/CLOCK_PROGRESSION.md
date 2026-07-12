# Design memo — Survival-clock easing + descend-milestone HP growth

**Status:** approved direction, phased implementation pending
**Target:** version-gated wave, **v1.9.0** — the first wave to *deliberately re-bless* the frozen `reference_crawl` golden (HP lines only)
**Motivation:** live playthrough + the v1.8 survival-fleet A/B both show the **survival clock (exhaustion from deep-floor navigation), not monsters, is the dominant killer** (0/12 fleet runs reached floor 5; most stalled in floor 2–4 mazes, driving exhaustion into tiers 4–6 just crossing to the stairs).

## Core insight

**HP growth cannot fix the actual killer.** The tier-6 *collapse* death is a fatigue threshold, not HP damage — so the **clock levers** defend against exhaustion, and **HP growth** defends against the danger/elite curve. They are complementary. This is why both are needed and why the clock softening (not the HP ramp) is what stops the exhaustion death.

## 1. Clock — three surgical, RNG-free levers

- **A. Gate the deep-floor move-tax one tier later** — `src/movement.zig:82`, `ex >= 1` → `ex >= 2`. Today `rest` floors fatigue at 20 = tier 1, so the deep-floor surcharge was *permanently on*. (All three design lenses called this "ship regardless.")
- **B. Clamp the deep-floor tick stack to +1** — insert `if (w.floor_index >= 4 and extra > 1) extra = 1;` before the existing `extra < 0` clamp (`src/movement.zig` ~95). The race surcharge (`movement.zig` ~86–93) was **ungated by exhaustion**, so a slow race (dwarf, speed 25) paid it from move 1 and spiraled to +3/+4 ticks/move. After A+B: **dwarf a flat 2 ticks/move** (was 3–4), **elf/human 1**.
- **C. Push the penalty tiers up** — `src/survival.zig` `fatigueExhaustion`: `55/70/85/95` → **`62/78/90/97`**. Concentrate the biggest jump (**+8**) on the **tier-4 HP-halving onset (70→78)**, the catastrophic step. **Keep tiers 0/1 (20/40) frozen** so `reference_crawl`'s `fatigue=26 → tier 1` reading does not move. Collapse stays reachable at 97 (< the 100 fatigue cap), so pure-exhaustion death — which HP can't defend — remains a real threat.

Preserved unchanged: starvation (hunger +1/tick, threshold 75, DoT), in-combat pressure, rest/sleep economy.

## 2. Progression — descend-milestone HP growth (mundane grit; no XP/level/magic)

CON-scaled toughening, capped so a high-CON tank can't outrun the danger curve. New pure helper next to `maxHpLevel1`:

```zig
// src/character.zig
pub fn descendHpGrowth(char: *const types.Character) u32 {
    const con_mod = abilityModifier(statByAbbr(char, "CON"));
    const capped: i32 = @min(con_mod, 2);   // CON contribution capped at +2
    return @intCast(@max(2 + capped, 1));    // floor of 1 so low-CON still grows
}
```

Per new deepest floor: CON ≤11 → **+2**, CON 12–13 → **+3**, CON 14+ → **+4**. Max depth 5 → ≤4 events → **total growth caps at +16**.

Applied in `descend()` (`src/world.zig`, after the second-wind reset ~line 173, before `self.tick()`). `floor_index` is monotonic and there is no ascend command, so **every descend is a new deepest floor** — a pure `+=` needs no `deepest_floor` field and no schema change:

```zig
if (self.store.get(player_id)) |p| {
    const g = character.descendHpGrowth(p.char);
    p.max_hp += g;
    p.current_hp = @min(p.current_hp + g, survival.effectiveMaxHp(p)); // heal clamped to tier-4 cap
    try self.out.print("descend growth: max_hp +{d} ({d})\n", .{ g, p.max_hp });
}
```

**No stat bump** in v1.9.0 (deferred — a STR/CON bump ripples into AC/to-hit/damage/`maxHpLevel1` and would move every combat golden). Zero new RNG draws.

### Fairness (reference dwarf/barbarian, CON +1, base 13, +3/floor)
| deepest floor | max HP | tier-4 halved cap | net |
|---|---|---|---|
| 1 | 13 | 6 | 1.0× |
| 3 | 19 | 9 | 1.5× |
| 5 | 25 | **12** | 1.9× |

The tier-4 HP-halving flips from a **6-HP death sentence → a 12-HP survivable buffer** exactly where floor-4 elites appear. Difficulty **moves from navigation to combat**; it is not removed.

## Golden + save plan

- **NO save-schema bump.** `max_hp`/`current_hp` already persist (`save_state.zig:166-167`) and restore verbatim (`:319-320`); grown HP round-trips exactly. Extend the multi-floor roundtrip test to assert a descended player's grown `max_hp` survives capture→apply.
- **Deliberate `reference_crawl` re-bless** (version-gated to v1.9.0, regenerated via `zig build update-reference-golden`, **never hand-edited**, fresh evidence): it descends F1→F2→F3, so it moves on **HP-value lines only** (combat `hp=…`, the `stats` HP line) **plus the new `descend growth:` notices**. It **stays byte-identical** on `ticks=26 / hunger=26 / fatigue=26 / exhaustion=1 / rng_offset` (clock levers are floor≥4 / penalty-tier only; tiers 0/1 frozen; zero new draws). Header stays `# version=1.1.0` (pinned).
- Also re-bless `descend_crawl`, `playthrough`, and any descending HP-printing scenario. Add `evidence_v19.zig` + `gate-v19` and a floor-4 dwarf-crossing witness scenario (assert exhaustion stays < tier 4 across ~30 moves). Bump `src/version.zig` → 1.9.0.

## Fleet A/B (the referee — numbers are hypotheses, not final)

Run baseline (v1.8.0) vs candidate (v1.9.0), identical args, all personas × ≥3 seeds. **Efficacy** (all must hold): clock/env deaths at least halved; `deepest_floor.median` +≥1; `reached_floor_5_plus` 0 → ≥2/12. **Not-trivial guards** (dial back if any trips): total deaths stay ≥4/12; **the crossover** — `monster_deaths` rises above `clock_or_env_deaths` (the dominant killer must *shift* to combat, not vanish); a monster hit still drops someone below 25% HP; floor 5 not universally reached; clock deaths not zero everywhere.

## Phased plan (for the implementation agent)

Bump semver → 1.9.0 first.
1. **Core:** `survival.zig` tiers 62/78/90/97; `movement.zig` gate + clamp; `character.zig` `descendHpGrowth`; `world.zig` growth+clamped-heal+print. Unit tests (growth per class, cap +16, monotonic, heal clamp, tier boundaries, floor-4 dwarf = 2 ticks/move); fuzz invariant (`max_hp` never decreases across descend).
2. **Persistence guard:** extend the multi-floor roundtrip test; keep schema v4.
3. **Evidence + re-bless:** `evidence_v19` + witness scenario + `gate-v19`; `update-reference-golden`; re-capture descending scenarios in one commit, noting each moved golden.
4. **Release gate:** build/test/consumer-test → fuzz 10k → all DST byte-identical ×2 seed 42 → evidence-v19.
5. **Validate:** survival-fleet A/B per the criteria; single-lever tuning if a guard trips.

## Decisions locked (defaults; fleet A/B tunes)

Growth base **2** (+CON capped, total ≤+16); tier-4 onset **78**; collapse **97**; deep-floor clamp **to 1**; **heal = growth amount** (wounds carry); **no stat bump**. The growth magnitude is the primary tuning knob — bias adjustments there, keep the clock light.
