// Persona playtest fleet — the SD5 balance instrument (SPRINT_V1.7.md).
//
// Runs 4 personas x N seeds of agent-driven ironman playthroughs against a zig-q
// build and returns a death-cause/depth summary plus raw per-run metrics.
//
// Invoke from Claude Code by SCRIPT PATH (name-resolution does not pick this file up):
//   Workflow({ scriptPath: '.claude/workflows/survival-fleet.js',
//              args: { label: 'retuned', exe: '<build>/zig-q.exe' } })
// A/B protocol: run once with label 'baseline' on main, once with label '<branch>' on the
// candidate build, HOLDING seeds/turnBudget CONSTANT so navigation friction cancels out
// and the delta isolates the economy change. v1.6.1 baseline lives on issue #40.
//
// NOTE: the balance A/B is navigation-limited — most runs stall finding stairs before the
// deep floors, so it discriminates BUGS well but balance numbers poorly (see #40 / #52).
//
// args (all optional) — passed as a JSON object OR a JSON string (both handled):
//   label      - output subdir + report tag (default 'baseline')
//   seeds      - array of world seeds (default [11, 137, 313])
//   exe        - absolute path to zig-q.exe (default this repo's zig-out build)
//   turnBudget - max gameplay commands after spawn (default 45; DO NOT change between A and B)

export const meta = {
  name: 'survival-fleet',
  description: 'Persona playtest fleet: 4 play-styles x N seeds; reports death-cause and depth distribution',
  whenToUse: 'Balance validation for survival/combat tuning (SPRINT_V1.7 SD5). Run on baseline and candidate builds with identical args and diff the summaries.',
  phases: [{ title: 'Playtest', detail: 'personas x seeds, deterministic REPL runs' }],
}

// args may arrive as a JSON string depending on the invocation path — normalize to an object.
const A = (typeof args === 'string' ? JSON.parse(args) : (args || {}))
const label = A.label || 'baseline'
const seeds = A.seeds || [11, 137, 313]
const EXE = A.exe || 'C:/Users/admin/workspace/zig-q/zig-out/bin/zig-q.exe'
const turnBudget = A.turnBudget || 45
const OUT = `C:/Users/admin/workspace/zig-q/.fleet/${label}`

const HARNESS = `You are playtesting a deterministic Zig roguelike (zig-q) to measure how players DIE. The engine replays deterministically: same seed + same command list = identical output, so you play by maintaining an append-only command file and re-running it.

HARNESS (run these in bash). SESSION is your unique file; SEED is your seed:
  SESSION="<given below>"
  mkdir -p "$(dirname "$SESSION")"; : > "$SESSION"
  # to play a turn, append command(s) then replay and read the tail:
  printf 'CMD\\n' >> "$SESSION"; cat "$SESSION" | ${EXE} --repl SEED --live-ai 2>/dev/null | tail -N
Use tail -20 to -30; the LAST 'look' map and any 'hp='/'exhaustion'/'starvation'/'slain'/'you are dead' lines are what matter.

RULES OF THE WORLD:
- Coordinates: north = x-1, south = x+1, EAST = y+1, WEST = y-1. Map: '@'=you, '#'=wall, '.'=floor, '>'=stairs down, 'g/s/h/w'=monsters, '*'=floor object/trap.
- Creation: 'assign <STR DEX CON INT WIS CHA>' (six pool-slot picks from the printed stat_rolls), 'race <1|2 dwarf +2CON|3 elf +2DEX>', 'class <1 barbarian|2 fighter|3 bard>', 'spawn'.
- Floor 1: small room; the '>' is 1 south + 1 east of spawn; 'descend' on it. Floors 2+ are procedural — LOOK and navigate to the '>'.
- Commands: look (l), move <n/s/e/w> (m <dir>), attack [name], end turn, wait, food, rest, sleep, use bandage, use antidote, get <item>, get from corpse, descend, inventory, stats.
- Survival: every action ticks the clock; deep floors cost extra ticks per move. Starvation and exhaustion deal HP damage; exhaustion 5 = incapacitated. Eat before hunger maxes; rest sheds fatigue (floor 20); only sleep clears fully.

YOUR JOB: play ONE run as your persona from creation until: you DESCEND past floor 5, you DIE, you soft-lock (no legal recovery), or you hit ~${turnBudget} gameplay commands after spawn (a fixed budget — circling = a valid 'stuck' outcome). Then STOP and report. Batch obvious sequences; don't narrate. Note WHAT KILLED YOU. Your final message is consumed as data.`

const SCHEMA = {
  type: 'object',
  required: ['persona', 'seed', 'deepest_floor', 'outcome', 'cause', 'commands_after_spawn'],
  properties: {
    persona: { type: 'string' },
    seed: { type: 'number' },
    deepest_floor: { type: 'number' },
    outcome: { type: 'string', enum: ['survived_past_5', 'died', 'soft_locked', 'stuck_turn_budget'] },
    cause: { type: 'string', enum: ['hunger', 'exhaustion', 'soft_lock', 'monster', 'none', 'trap_poison', 'unknown'] },
    commands_after_spawn: { type: 'number' },
    hp_low_watermark: { type: 'string' },
    monster_damage_taken: { type: 'number', description: 'HP lost to monster attacks, not the clock' },
    notes: { type: 'string', description: '1-3 sentences: how the run went and what killed it' },
  },
}

const personas = {
  speedrunner: 'SPEEDRUNNER: dwarf barbarian (highest roll to STR, next to CON), rush. Each floor: LOOK, head straight for the >, fight only blockers, no looting/resting unless forced. Eat only on a starvation HP tick.',
  cautious: 'CAUTIOUS SURVIVOR: dwarf barbarian, play safe. Rest when exhaustion appears, eat before hunger maxes, grab bandages/rations, fight from chokepoints, clear each floor before descending. Health over speed.',
  hoarder: 'HOARDER: elf barbarian, loot EVERYTHING on every floor before taking the stairs. Fight what you must. Tests whether greed + the clock kills.',
  exploiter: 'EXPLOIT-HUNTER: any build; try to BREAK the game. Probe: (a) attack-spam on floors 1-3 — any counters? (b) step away mid-combat + end turn — does the monster follow, does combat ever end? (c) push exhaustion high — can you recover at level 5? (d) drop equipped gear — slot cleared? Report which exploits work. Death is fine.',
}

phase('Playtest')
const runs = []
for (const [name, policy] of Object.entries(personas)) {
  for (const seed of seeds) {
    const tag = `${name}_s${seed}`
    runs.push(() => agent(
      `${HARNESS}\n\nYOUR SESSION FILE: "${OUT}/${tag}.txt"\nYOUR SEED: ${seed}\nYOUR PERSONA — ${policy}\n\nPlay the run now, then report.`,
      { label: `play:${tag}`, schema: SCHEMA }
    ).then(r => (r ? { ...r, persona: name, seed } : null)))
  }
}
const results = (await parallel(runs)).filter(Boolean)

// Aggregate in-script so a re-run yields the comparison table directly.
const deaths = results.filter(r => r.outcome === 'died' || r.outcome === 'soft_locked')
const byCause = {}
for (const d of deaths) byCause[d.cause] = (byCause[d.cause] || 0) + 1
const clockCauses = ['hunger', 'exhaustion', 'soft_lock', 'trap_poison']
const floors = results.map(r => r.deepest_floor).sort((a, b) => a - b)
const monDmg = results.map(r => r.monster_damage_taken || 0)
const summary = {
  label,
  runs: results.length,
  reached_floor_5_plus: results.filter(r => r.outcome === 'survived_past_5').length,
  deepest_floor: { min: floors[0], median: floors[Math.floor(floors.length / 2)], max: floors[floors.length - 1] },
  deaths: deaths.length,
  deaths_by_cause: byCause,
  clock_or_env_deaths: deaths.filter(d => clockCauses.includes(d.cause)).length,
  monster_deaths: deaths.filter(d => d.cause === 'monster').length,
  monster_damage: { total: monDmg.reduce((a, b) => a + b, 0), max: Math.max(0, ...monDmg) },
}
log(`fleet[${label}]: ${summary.deaths}/${summary.runs} died (${summary.clock_or_env_deaths} clock/env, ${summary.monster_deaths} monster); median floor ${summary.deepest_floor.median}; ${summary.reached_floor_5_plus} reached 5+`)
return { summary, runs: results }
