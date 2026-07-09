//! Public `zig_q` library surface for deterministic dungeon crawl simulation.
//!
//! **World lifecycle:** `world.World.init` / `deinit`, `loadFloor`, `descend`, `spawnStagedPlayer`,
//! `stageCharacter`, `spawnMonster`, `snapshot` (includes `floor_index` and `entity_count`).
//! **Character setup:** `session.bootstrapCharacter` (rolls stats and builds a draft character).
//! **Dungeon crawl:** `dungeon.floor1_spawn`, `dungeon.walkSpawnToFloor1Stairs`.
//! **Movement:** `movement.moveEntity`.
//! **Combat:** `combat.attack`, `combat.endTurn`, `combat.flee`, `combat.catchBreath`, `combat.isInCombat`.
//! **Persistence:** `sqlite_store.saveSlot`, `sqlite_store.loadSlot`, `sqlite_store.deleteDb`.
//! **Scripted testing:** `dst.runNamedScenario`, `repl.runScripted`, `fuzz.run`.
//! **Release identity:** `version.semver` (also recorded as `# version=<semver>` in REPL/DST transcripts).
//!
//! Internal modules are re-exported for in-repo tests; external consumers should depend on
//! the documented symbols above and treat other exports as implementation details.

const std = @import("std");

pub const rng = @import("rng.zig");
pub const dice = @import("dice.zig");
pub const types = @import("types.zig");
pub const loc = @import("loc.zig");
pub const clock = @import("clock.zig");
pub const entity = @import("entity.zig");
pub const map = @import("map.zig");
pub const terrain = @import("terrain.zig");
pub const dungeon = @import("dungeon.zig");
pub const world = @import("world.zig");
pub const movement = @import("movement.zig");
pub const commands = @import("commands.zig");
pub const map_render = @import("map_render.zig");
pub const session = @import("session.zig");
pub const character = @import("character.zig");
pub const monsters = @import("monsters.zig");
pub const combat = @import("combat.zig");
pub const choose = @import("choose.zig");
pub const demo = @import("demo.zig");
pub const repl = @import("repl.zig");
pub const transcript = @import("transcript.zig");
pub const fuzz = @import("fuzz.zig");
pub const version = @import("version.zig");
pub const dst = @import("dst.zig");
pub const evidence_v07 = @import("evidence_v07.zig");
pub const save_state = @import("save_state.zig");
pub const sqlite_store = @import("sqlite_store.zig");
pub const evidence_v08 = @import("evidence_v08.zig");
pub const evidence_v09 = @import("evidence_v09.zig");
pub const evidence_v10 = @import("evidence_v10.zig");
pub const evidence_v11 = @import("evidence_v11.zig");
pub const evidence_v12 = @import("evidence_v12.zig");
pub const evidence_v13 = @import("evidence_v13.zig");
pub const pathfinding = @import("pathfinding.zig");
pub const doors = @import("doors.zig");
pub const evidence_v14 = @import("evidence_v14.zig");
pub const evidence_v15 = @import("evidence_v15.zig");
pub const evidence_v16 = @import("evidence_v16.zig");
pub const wave_gate = @import("wave_gate.zig");
pub const help_text = @import("help_text.zig");
pub const evidence_format = @import("evidence_format.zig");
pub const scenario_file = @import("scenario_file.zig");
pub const conditions = @import("conditions.zig");
pub const perception = @import("perception.zig");
pub const world_objects = @import("world_objects.zig");
pub const explore = @import("explore.zig");
pub const items = @import("items.zig");
pub const inventory = @import("inventory.zig");
pub const survival = @import("survival.zig");

test {
    std.testing.refAllDecls(@This());
    _ = @import("rng.zig");
    _ = @import("dice.zig");
    _ = @import("types.zig");
    _ = @import("loc.zig");
    _ = @import("clock.zig");
    _ = @import("entity.zig");
    _ = @import("map.zig");
    _ = @import("terrain.zig");
    _ = @import("dungeon.zig");
    _ = @import("world.zig");
    _ = @import("movement.zig");
    _ = @import("commands.zig");
    _ = @import("map_render.zig");
    _ = @import("session.zig");
    _ = @import("character.zig");
    _ = @import("monsters.zig");
    _ = @import("combat.zig");
    _ = @import("choose.zig");
    _ = @import("demo.zig");
    _ = @import("repl.zig");
    _ = @import("transcript.zig");
    _ = @import("fuzz.zig");
    _ = @import("version.zig");
    _ = @import("dst.zig");
    _ = @import("evidence_v07.zig");
    _ = @import("save_state.zig");
    _ = @import("sqlite_store.zig");
    _ = @import("evidence_v08.zig");
    _ = @import("evidence_v09.zig");
    _ = @import("evidence_v10.zig");
    _ = @import("evidence_v11.zig");
    _ = @import("evidence_v12.zig");
    _ = @import("evidence_v13.zig");
    _ = @import("pathfinding.zig");
    _ = @import("doors.zig");
    _ = @import("evidence_v14.zig");
    _ = @import("evidence_v15.zig");
    _ = @import("wave_gate.zig");
    _ = @import("help_text.zig");
    _ = @import("evidence_format.zig");
    _ = @import("scenario_file.zig");
    _ = @import("conditions.zig");
    _ = @import("perception.zig");
    _ = @import("world_objects.zig");
    _ = @import("explore.zig");
    _ = @import("items.zig");
    _ = @import("inventory.zig");
    _ = @import("survival.zig");
}
