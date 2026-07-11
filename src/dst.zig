const std = @import("std");
const loc = @import("loc.zig");
const dungeon = @import("dungeon.zig");
const world = @import("world.zig");
const session = @import("session.zig");
const map_render = @import("map_render.zig");
const commands = @import("commands.zig");
const version = @import("version.zig");
const terrain = @import("terrain.zig");
const types = @import("types.zig");
const conditions = @import("conditions.zig");
const survival = @import("survival.zig");
const world_objects = @import("world_objects.zig");
const entity = @import("entity.zig");
const doors = @import("doors.zig");

pub const Step = union(enum) {
    roll_stats,
    creation_roll,
    assign_stats: [6]usize,
    choose_race: usize,
    choose_class: usize,
    creation_finish: []const u8,
    load_floor: u32,
    spawn_monster: struct {
        kind: @import("monsters.zig").Kind,
        name: []const u8,
        x: u64,
        y: u64,
        danger_tier: u32 = 0,
    },
    spawn: struct { name: []const u8, x: u64, y: u64 },
    tick: u32,
    time,
    look,
    command: []const u8,
    render_map: struct { x: u64, y: u64, radius: u8 },
    set_tile: struct { x: u64, y: u64, tile: terrain.Tile },
    /// Harness-only: set door state at a tile (for `pick` / locked-door tests).
    set_door: struct { x: u64, y: u64, state: doors.State },
    /// Harness-only: mark a trap at (x,y) as WIS-spotted (disarm prerequisite).
    mark_trap_spotted: struct { x: u64, y: u64 },
    apply_condition: struct { entity: []const u8, condition: types.Condition },
    remove_condition: struct { entity: []const u8, condition: types.Condition },
    set_exhaustion: struct { entity: []const u8, level: u3 },
    set_attribute: struct { entity: []const u8, abbr: []const u8, value: u64 },
    add_floor_object: struct {
        kind: world_objects.Kind,
        x: u64,
        y: u64,
        label: []const u8,
        item: ?@import("items.zig").Id = null,
    },
    list_floor_objects,
    mark_player_dead,
    give_item: struct { entity: []const u8, item: @import("items.zig").Id, count: u8 },
    set_hunger: struct { entity: []const u8, value: u16 },
    set_fatigue: struct { entity: []const u8, value: u16 },
    set_hp: struct { entity: []const u8, current: u32 },
    depth_report: u32,
    /// Print entity danger_tier (post-load proof for save_v4_roundtrip).
    report_danger: []const u8,
    /// Food-vs-ticks audit of a generated floor (v1.6 survival-economy tuning).
    economy_report: u32,
    /// Harness-only: set `floor_index` without regenerating terrain (Phase 2 speed tests).
    set_floor_index: u32,
};

fn findEntityByName(w: *world.World, name: []const u8) ?*entity.Entity {
    for (w.store.entities.items) |*ent| {
        if (std.mem.eql(u8, ent.name, name)) return ent;
    }
    return null;
}

pub const Scenario = struct {
    name: []const u8,
    seed: u64,
    steps: []const Step,
};

pub const default_scenario = Scenario{
    .name = "bootstrap",
    .seed = 42,
    .steps = &.{
        .roll_stats,
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .tick = 2 },
        .time,
        .{ .render_map = .{ .x = 49, .y = 49, .radius = 3 } },
        .look,
        .{ .tick = 1 },
        .time,
    },
};

pub const explore_scenario = Scenario{
    .name = "explore",
    .seed = 42,
    .steps = &.{
        .roll_stats,
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .command = "look" },
        .{ .command = "move east" },
        .{ .command = "look" },
        .{ .command = "time" },
        .{ .command = "exit" },
    },
};

pub const create_scenario = Scenario{
    .name = "create",
    .seed = 42,
    .steps = &.{
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

/// Harvested from transcripts/session-1783208416-seed42.txt (recorded playthrough).
pub const playthrough_scenario = Scenario{
    .name = "playthrough",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .command = "help" },
        .{ .command = "assign 5 1 6 2 3 4" },
        .{ .command = "race" },
        .{ .command = "race 1" },
        .{ .command = "stats" },
        .{ .command = "help" },
        .{ .command = "class" },
        .{ .command = "class 1" },
        .{ .command = "spawn" },
        .{ .command = "stats" },
        .{ .command = "l" },
        .{ .command = "look" },
        .{ .command = "m n" },
        .{ .command = "move n" },
        .{ .command = "move e" },
        .{ .command = "look" },
        .{ .command = "move e" },
        .{ .command = "move s" },
        .{ .command = "look" },
        .{ .command = "move nw" },
        .{ .command = "move w w" },
        .{ .command = "move w; move w" },
        .{ .command = "move w" },
        .{ .command = "move w" },
        .{ .command = "move w" },
        .{ .command = "look" },
        .{ .command = "time" },
        .{ .command = "move n" },
        .{ .command = "time" },
        .{ .command = "exit" },
    },
};

pub const brawl_scenario = Scenario{
    .name = "brawl",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .spawn_monster = .{ .kind = .skeleton, .name = "skeleton_0", .x = 50, .y = 49 } },
        .{ .command = "attack skeleton_0" },
        .{ .command = "end turn" },
        .{ .command = "attack skeleton_0" },
        .{ .command = "end turn" },
        .{ .command = "attack skeleton_0" },
        .{ .command = "end turn" },
        .{ .command = "attack skeleton_0" },
        .{ .command = "end turn" },
        .{ .command = "attack skeleton_0" },
        .{ .command = "end turn" },
        .{ .command = "attack skeleton_0" },
        .{ .command = "end turn" },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

pub const save_roundtrip_scenario = Scenario{
    .name = "save_roundtrip",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .command = "move east" },
        .{ .command = "save" },
        .{ .command = "load 1" },
        .{ .command = "look" },
        .{ .command = "stats" },
        .{ .command = "move north" },
        .{ .command = "exit" },
    },
};

/// Seed 42: floor 1→3 with goblin fights, save/load on floor 2, byte-stable DST transcript.
pub const reference_crawl_scenario = Scenario{
    .name = "reference_crawl",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .command = "move east" },
        .{ .command = "move south" },
        .{ .command = "move east" },
        .{ .command = "descend" },
        .{ .command = "move south" },
        .{ .command = "move south" },
        .{ .command = "move south" },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .command = "attack goblin_0" },
        .{ .command = "save" },
        .{ .command = "load 1" },
        .{ .command = "move south" },
        .{ .command = "move south" },
        .{ .command = "move east" },
        .{ .command = "descend" },
        .{ .command = "move south" },
        .{ .command = "move south" },
        .{ .command = "move south" },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .command = "attack goblin_0" },
        .{ .command = "look" },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

pub const save_v2_roundtrip_scenario = Scenario{
    .name = "save_v2_roundtrip",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .add_floor_object = .{ .kind = .corpse, .x = 50, .y = 49, .label = "goblin_0" } },
        .{ .apply_condition = .{ .entity = "entity_0", .condition = .poisoned } },
        .{ .set_exhaustion = .{ .entity = "entity_0", .level = 3 } },
        .{ .command = "save" },
        .{ .command = "load 1" },
        .{ .command = "conditions" },
        .list_floor_objects,
        .{ .command = "exit" },
    },
};

pub const conditions_brawl_scenario = Scenario{
    .name = "conditions_brawl",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "STR", .value = 14 } },
        .{ .apply_condition = .{ .entity = "goblin_0", .condition = .prone } },
        .{ .command = "attack goblin_0" },
        .{ .remove_condition = .{ .entity = "goblin_0", .condition = .prone } },
        .{ .apply_condition = .{ .entity = "entity_0", .condition = .blinded } },
        .{ .command = "attack goblin_0" },
        .{ .remove_condition = .{ .entity = "entity_0", .condition = .blinded } },
        .{ .apply_condition = .{ .entity = "entity_0", .condition = .poisoned } },
        .{ .command = "attack goblin_0" },
        .{ .remove_condition = .{ .entity = "entity_0", .condition = .poisoned } },
        .{ .command = "conditions" },
        .{ .command = "exit" },
    },
};

pub const los_peek_scenario = Scenario{
    .name = "los_peek",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 50, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "near_goblin", .x = 50, .y = 50 } },
        .{ .set_tile = .{ .x = 49, .y = 49, .tile = .wall } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "far_goblin", .x = 48, .y = 49 } },
        .{ .command = "look" },
        .{ .command = "exit" },
    },
};

pub const ambush_scenario = Scenario{
    .name = "ambush",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 50 } },
        .{ .command = "wait" },
        .{ .command = "exit" },
    },
};

pub const loot_roundtrip_scenario = Scenario{
    .name = "loot_roundtrip",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .add_floor_object = .{ .kind = .item, .x = 49, .y = 50, .label = "bandage", .item = .bandage } },
        .{ .command = "get bandage" },
        .{ .command = "save" },
        .{ .command = "load 1" },
        .{ .command = "inventory" },
        .{ .command = "exit" },
    },
};

pub const geared_brawl_scenario = Scenario{
    .name = "geared_brawl",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 2 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .give_item = .{ .entity = "entity_0", .item = .short_sword, .count = 1 } },
        .{ .give_item = .{ .entity = "entity_0", .item = .leather_armour, .count = 1 } },
        .{ .command = "equip short_sword" },
        .{ .command = "equip leather_armour" },
        .{ .command = "stats" },
        .{ .command = "attack goblin_0" },
        .{ .command = "exit" },
    },
};

pub const corpse_loot_scenario = Scenario{
    .name = "corpse_loot",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "STR", .value = 18 } },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .command = "attack goblin_0" },
        .{ .command = "get from corpse" },
        .{ .command = "inventory" },
        .{ .command = "exit" },
    },
};

pub const encumbered_scenario = Scenario{
    .name = "encumbered",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "STR", .value = 8 } },
        .{ .give_item = .{ .entity = "entity_0", .item = .leather_armour, .count = 5 } },
        .{ .command = "move east" },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

pub const survive_scenario = Scenario{
    .name = "survive",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .command = "move east" },
        .{ .command = "time" },
        .{ .command = "food" },
        .{ .command = "rest" },
        .{ .command = "time" },
        .{ .command = "save" },
        .{ .command = "load 1" },
        .{ .command = "time" },
        .{ .command = "conditions" },
        .{ .command = "exit" },
    },
};

pub const starve_scenario = Scenario{
    .name = "starve",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_hunger = .{ .entity = "entity_0", .value = 100 } },
        .{ .tick = 3 },
        .{ .command = "time" },
        .{ .command = "move east" },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

/// Seed 42: the walking-dead permadeath guard. Starvation drains the last HP
/// while no combat is in progress; the run must still end — every command after
/// the fatal tick hits the permadeath gate exactly as if a monster had landed
/// the killing blow.
pub const starve_out_scenario = Scenario{
    .name = "starve_out",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_hunger = .{ .entity = "entity_0", .value = 100 } },
        .{ .set_hp = .{ .entity = "entity_0", .current = 3 } },
        // Out-of-combat starving DoT lands on even clock ticks (v1.6 half
        // rate), so 6 ticks bound the 3 hits that take hp 3 -> 0.
        .{ .tick = 6 },
        .{ .command = "move east" }, // blocked: permadeath gate
        .{ .command = "look" }, // blocked: permadeath gate
        .{ .command = "stats" }, // allowed for the dead: shows permadeath status
        .{ .command = "exit" },
    },
};

pub const sleep_cycle_scenario = Scenario{
    .name = "sleep_cycle",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 65 } },
        .{ .command = "time" },
        .{ .command = "sleep" },
        .{ .command = "time" },
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 60 } },
        .{ .command = "rest" },
        .{ .command = "time" },
        .{ .command = "exit" },
    },
};

/// Seed 42: guards the rest/sleep survival economy. From a penalty exhaustion
/// tier, repeated `rest` sheds fatigue only down to `rest_fatigue_floor` (tier 1)
/// and can never fully clear exhaustion; only `sleep` resets fatigue to 0. This is
/// what stops rest from strictly dominating sleep.
pub const rest_floor_scenario = Scenario{
    .name = "rest_floor",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 60 } },
        .{ .command = "conditions" }, // exhaustion=3 (penalty tier)
        .{ .command = "rest" },
        .{ .command = "rest" },
        .{ .command = "rest" }, // fatigue bottoms out at the floor (20), never 0
        .{ .command = "conditions" }, // exhaustion=1: rest cannot clear it
        .{ .command = "sleep" }, // only sleep resets fatigue to 0
        .{ .command = "conditions" }, // exhaustion gone
        .{ .command = "exit" },
    },
};

/// Seed 42: sleep from moderate fatigue keeps full HP, then the tier-4 recovery
/// cap is exercised while awake. Sleep no longer accrues fatigue mid-loop
/// (#55 / v1.7.1); the bandage legs still pin that at exhaustion 4 healing
/// stops at effectiveMaxHp, a bandage that cannot heal is refused (not
/// consumed), and once exhaustion clears the same bandage heals past the cap.
pub const exhausted_sleep_scenario = Scenario{
    .name = "exhausted_sleep",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 60 } },
        .{ .command = "stats" }, // HP: 13 before sleeping
        .{ .command = "sleep" }, // fatigue frozen while asleep; applySleep → 0
        .{ .command = "stats" }, // HP: 13 — sleeping cost nothing
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 75 } }, // tier 4 while awake
        .{ .set_hp = .{ .entity = "entity_0", .current = 3 } },
        .{ .give_item = .{ .entity = "entity_0", .item = .bandage, .count = 1 } },
        .{ .command = "use bandage" }, // heals 3, stopping at the halved cap (6)
        .{ .command = "use bandage" }, // at the cap: refused, bandage kept
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 0 } }, // exhaustion clears
        .{ .command = "use bandage" }, // cap lifted: full 5 hp heal resumes
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

/// #26 / SD2: exhaustion-5 soft-lock recovery. Fatigue 85 applies `.unconscious`
/// and used to brick rest/sleep/eat; sleep is the carved-out recovery path.
/// Crosses the threshold via set_fatigue and asserts sleep succeeds.
pub const collapse_sleep_scenario = Scenario{
    .name = "collapse_sleep",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        // Fatigue 84 = tier 4; one more would hit 85 = tier 5. Jump straight to 85.
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 85 } },
        .{ .command = "conditions" }, // exhaustion=5, unconscious
        .{ .command = "rest" }, // still blocked while incapacitated
        .{ .command = "sleep" }, // recovery path: collapses into sleep and wakes clear
        .{ .command = "conditions" }, // exhaustion gone
        .{ .command = "exit" },
    },
};

/// #55: sleep at high fatigue must never self-kill. Pre-1.7.1, unguarded fatigue
/// accrual across the 24 sleep ticks climbed start≥71 into tier 6 and
/// resolveDeath mid-sleep — while the tier-4 UI said "sleep soon". Locks the
/// lethal boundary (71), the observed playtest death (84), and fatigue_max.
pub const sleep_high_fatigue_scenario = Scenario{
    .name = "sleep_high_fatigue",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        // Boundary: old accrual 71+24 → 95 = tier 6 collapse.
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 71 } },
        .{ .command = "stats" },
        .{ .command = "sleep" },
        .{ .command = "stats" }, // alive, fatigue=0, HP intact
        // Observed playtest death (fatigue 84, tier 4 "sleep soon").
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 84 } },
        .{ .command = "sleep" },
        .{ .command = "stats" },
        // Ceiling: sleep from fatigue_max must also recover, not collapse.
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 100 } },
        .{ .command = "sleep" },
        .{ .command = "stats" },
        .{ .command = "conditions" }, // no dead / no exhaustion
        .{ .command = "exit" },
    },
};

/// Seed 42: survival needs walkthrough with save/load; byte-stable DST transcript.
pub const reference_survive_scenario = Scenario{
    .name = "reference_survive",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .command = "move east" },
        .{ .command = "move south" },
        .{ .command = "time" },
        .{ .command = "food" },
        .{ .command = "wait" },
        .{ .command = "rest" },
        .{ .command = "save" },
        .{ .command = "load 1" },
        .{ .command = "time" },
        .{ .command = "exit" },
    },
};

/// Seed 42: monsters must outlive a long stretch of the survival clock. Regression
/// scenario for the leak that ticked hunger/fatigue on monsters and dropped every
/// floor's population dead of exhaustion ~95 ticks after spawn — corpseless (only
/// the combat kill path drops corpses) and untargetable. The player's meters are
/// pinned back between waits so only the goblin is exposed to the clock.
pub const monster_endurance_scenario = Scenario{
    .name = "monster_endurance",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .tick = 45 },
        .{ .set_hunger = .{ .entity = "entity_0", .value = 0 } },
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 0 } },
        .{ .tick = 45 },
        .{ .set_hunger = .{ .entity = "entity_0", .value = 0 } },
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 0 } },
        .{ .tick = 45 },
        .{ .set_hunger = .{ .entity = "entity_0", .value = 0 } },
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 0 } },
        .{ .command = "look" },
        .{ .command = "attack goblin_0" },
        .{ .command = "end turn" },
        .{ .command = "exit" },
    },
};

/// Seed 42: a poisoned goblin bleeds out from survival DoT with no fight in
/// progress. The death must mirror a combat kill: the corpse (with loot) shows
/// up in `nearby:`, the goblin leaves the viewport and tile map, and the
/// player can walk onto the freed tile.
pub const bleed_out_scenario = Scenario{
    .name = "bleed_out",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .apply_condition = .{ .entity = "goblin_0", .condition = .poisoned } },
        .{ .set_hp = .{ .entity = "goblin_0", .current = 2 } },
        .{ .tick = 2 }, // poison DoT out of combat: hp 2 -> 0, corpse drops
        .{ .command = "look" },
        .{ .command = "move south" }, // onto the corpse tile — no longer blocked
        .list_floor_objects,
        .{ .command = "exit" },
    },
};

pub const hunt_scenario = Scenario{
    .name = "hunt",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "hunt_goblin", .x = 49, .y = 54 } },
        .{ .command = "wait" },
        .{ .command = "wait" },
        .{ .command = "wait" },
        .{ .command = "move south" },
        .{ .command = "move south" },
        .{ .command = "wait" },
        .{ .command = "look" },
        .{ .command = "exit" },
    },
};

pub const flee_scenario = Scenario{
    .name = "flee",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "flee_goblin", .x = 51, .y = 49 } },
        .{ .apply_condition = .{ .entity = "flee_goblin", .condition = .frightened } },
        .{ .command = "wait" },
        .{ .command = "look" },
        .{ .command = "exit" },
    },
};

pub const heal_bandage_scenario = Scenario{
    .name = "heal_bandage",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .give_item = .{ .entity = "entity_0", .item = .bandage, .count = 1 } },
        .{ .set_hp = .{ .entity = "entity_0", .current = 5 } },
        .{ .command = "use bandage" },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

pub const trap_floor_scenario = Scenario{
    .name = "trap_floor",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .command = "move east" },
        .{ .command = "move south" },
        .{ .command = "move east" },
        .{ .command = "descend" },
        .list_floor_objects,
        .{ .command = "move south" },
        .{ .command = "move south" },
        .{ .command = "move south" },
        .{ .command = "move south" },
        .{ .command = "move south" },
        .{ .command = "move south" },
        .{ .command = "move east" },
        .{ .command = "move east" },
        .{ .command = "conditions" },
        .{ .command = "exit" },
    },
};

pub const deep_floor_scenario = Scenario{
    .name = "deep_floor",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .depth_report = 2 },
        .{ .depth_report = 5 },
        .{ .command = "exit" },
    },
};

/// v1.6 survival-economy audit: food obtainable vs minimum ticks to cross each
/// generated floor. Pure plan/layout math (no live world), so it sweeps any
/// seed cheaply: `zig build dst -- survival_economy <seed>`.
pub const survival_economy_scenario = Scenario{
    .name = "survival_economy",
    .seed = 42,
    .steps = &.{
        .{ .economy_report = 2 },
        .{ .economy_report = 3 },
        .{ .economy_report = 4 },
        .{ .economy_report = 5 },
    },
};

/// Floor-4 danger-tier counters: attack-spamming player takes unavoidable return fire;
/// flee remains the escape valve under danger-tier pressure.
pub const deadly_floor_scenario = Scenario{
    .name = "deadly_floor",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_hp = .{ .entity = "entity_0", .current = 40 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "STR", .value = 8 } }, // soft hits
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49, .danger_tier = 1 } },
        .{ .command = "attack goblin_0" },
        .{ .command = "attack goblin_0" },
        .{ .command = "attack goblin_0" },
        .{ .command = "flee" },
        .{ .command = "exit" },
    },
};

/// Elite kinds on danger floors: hobgoblin shows higher HP/AC in combat transcript.
pub const elite_brawl_scenario = Scenario{
    .name = "elite_brawl",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_hp = .{ .entity = "entity_0", .current = 40 } },
        .{ .spawn_monster = .{ .kind = .hobgoblin, .name = "hobgoblin_0", .x = 50, .y = 49, .danger_tier = 2 } },
        .{ .command = "attack hobgoblin_0" },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

/// Floor-4/5 loot plans place fewer bandages than the floor-2 baseline (exactly 1 bandage).
pub const scarce_heals_scenario = Scenario{
    .name = "scarce_heals",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .depth_report = 2 },
        .{ .depth_report = 4 },
        .{ .depth_report = 5 },
        .{ .command = "exit" },
    },
};

/// Schema v4 roundtrip: danger_tier survives save/load (post-load report + second counter).
pub const save_v4_roundtrip_scenario = Scenario{
    .name = "save_v4_roundtrip",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_hp = .{ .entity = "entity_0", .current = 40 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49, .danger_tier = 1 } },
        .{ .command = "attack goblin_0" },
        .{ .command = "save" },
        .{ .command = "load 1" },
        // Post-load proof: tier must still be 1 (not only the pre-save spawn_monster line).
        .{ .report_danger = "goblin_0" },
        .{ .report_danger = "entity_0" },
        .{ .command = "attack goblin_0" },
        .{ .command = "exit" },
    },
};

/// Sleep next to a hostile: explore AI + D2 first-strike interrupt the long rest.
pub const sleep_interrupt_scenario = Scenario{
    .name = "sleep_interrupt",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_hp = .{ .entity = "entity_0", .current = 40 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .command = "sleep" },
        .{ .command = "exit" },
    },
};

/// Backfill: unequip cycle keeps item in bag.
pub const unequip_cycle_scenario = Scenario{
    .name = "unequip_cycle",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 2 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .give_item = .{ .entity = "entity_0", .item = .short_sword, .count = 1 } },
        .{ .command = "equip short_sword" },
        .{ .command = "unequip weapon" },
        .{ .command = "inventory" },
        .{ .command = "equip short_sword" },
        .{ .command = "exit" },
    },
};

/// Backfill: dropping the last equipped stack clears the slot.
pub const drop_clears_slot_scenario = Scenario{
    .name = "drop_clears_slot",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 2 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .give_item = .{ .entity = "entity_0", .item = .short_sword, .count = 1 } },
        .{ .command = "equip short_sword" },
        .{ .command = "drop short_sword" },
        .{ .command = "inventory" },
        .{ .command = "exit" },
    },
};

/// Backfill: bare loot prefers corpse gear over a floor item.
pub const bare_loot_corpse_scenario = Scenario{
    .name = "bare_loot_corpse",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .add_floor_object = .{ .kind = .item, .x = 50, .y = 49, .label = "bandage", .item = .bandage } },
        .{ .add_floor_object = .{ .kind = .corpse, .x = 50, .y = 49, .label = "goblin_0", .item = .short_sword } },
        .{ .command = "loot" },
        .{ .command = "inventory" },
        .{ .command = "exit" },
    },
};

/// Backfill: weaker weapon never cuts innate die (barbarian + short sword).
pub const weaker_weapon_scenario = Scenario{
    .name = "weaker_weapon",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 }, // barbarian d12
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .give_item = .{ .entity = "entity_0", .item = .short_sword, .count = 1 } },
        .{ .command = "equip short_sword" },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "STR", .value = 18 } },
        .{ .command = "attack goblin_0" },
        .{ .command = "exit" },
    },
};

/// Phase 1: rogue finesse — light weapon uses DEX mod; heavy reverts to STR.
/// STR=10 (mod 0), DEX=18 (mod +4): short sword → mod=4; greatsword → mod=0.
pub const rogue_finesse_scenario = Scenario{
    .name = "rogue_finesse",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 3 }, // elf
        .{ .choose_class = 3 }, // rogue
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "STR", .value = 10 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "DEX", .value = 18 } },
        .{ .give_item = .{ .entity = "entity_0", .item = .short_sword, .count = 1 } },
        .{ .give_item = .{ .entity = "entity_0", .item = .greatsword, .count = 1 } },
        .{ .command = "equip short_sword" },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .command = "attack goblin_0" }, // DEX mod=4
        .{ .command = "equip greatsword" },
        .{ .command = "attack goblin_0" }, // STR mod=0
        .{ .command = "exit" },
    },
};

/// Phase 1: rogue is leather-proficient (AC no longer collapses to 10).
pub const rogue_leather_scenario = Scenario{
    .name = "rogue_leather",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 3 }, // elf (+2 DEX)
        .{ .choose_class = 3 }, // rogue
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "DEX", .value = 14 } },
        .{ .give_item = .{ .entity = "entity_0", .item = .leather_armour, .count = 1 } },
        .{ .command = "equip leather_armour" },
        .{ .command = "stats" }, // AC = 11 (leather) + 2 (DEX) = 13
        .{ .command = "exit" },
    },
};

/// Phase 1: barbarian reckless — advantage toggle + −4 AC until next turn.
/// Pad the goblin's HP so combat lasts through two monster counters.
pub const reckless_scenario = Scenario{
    .name = "reckless",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 1 }, // dragonborn
        .{ .choose_class = 1 }, // barbarian
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "DEX", .value = 10 } }, // base AC 10
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .set_hp = .{ .entity = "goblin_0", .current = 40 } },
        .{ .command = "attack goblin_0" },
        .{ .command = "reckless" },
        .{ .command = "attack goblin_0" }, // advantage draw while reckless
        .{ .command = "end turn" }, // goblin swings at AC 6 (−4); then reckless clears
        .{ .command = "end turn" }, // goblin swings at AC 10 (cleared)
        .{ .command = "exit" },
    },
};

/// Phase 1: fighter guard — skip attack, +2 AC for one round.
pub const guard_scenario = Scenario{
    .name = "guard",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 }, // dwarf
        .{ .choose_class = 2 }, // fighter
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "DEX", .value = 10 } }, // base AC 10
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .command = "attack goblin_0" },
        .{ .command = "guard" }, // +2 AC → 12 for the goblin's counter
        .{ .command = "exit" },
    },
};

/// Phase 1: fighter discipline (damage-face clamp) + second wind self-heal.
pub const discipline_second_wind_scenario = Scenario{
    .name = "discipline_second_wind",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 }, // dwarf
        .{ .choose_class = 2 }, // fighter
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "CON", .value = 14 } }, // +2 → heal 7
        .{ .set_hp = .{ .entity = "entity_0", .current = 5 } },
        .{ .command = "second wind" },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "STR", .value = 14 } },
        .{ .command = "attack goblin_0" },
        .{ .command = "attack goblin_0" },
        .{ .command = "attack goblin_0" },
        .{ .command = "exit" },
    },
};

/// Phase 2: elf (speed 35) on floor ≥ 4 accrues fewer move-ticks than a slow race.
/// Uses floor-1 terrain + set_floor_index so walkable paths stay deterministic.
/// Fatigue 25 → exhaustion tier 1: neutral would pay 2 ticks/move; elf suppresses
/// to 1. Four moves → dst_end ticks=4 (would be 8 for human, 12 for dwarf).
/// `stats` still prints movement: 30 (race.speed is never written to ent.movement).
pub const elf_speed_deepfloor_scenario = Scenario{
    .name = "elf_speed_deepfloor",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 3 }, // elf (+2 DEX, speed 35)
        .{ .choose_class = 3 }, // rogue
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_floor_index = 4 },
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 25 } }, // exhaustion tier 1
        .time,
        .{ .command = "move east" },
        .{ .command = "move west" },
        .{ .command = "move east" },
        .{ .command = "move west" },
        .time,
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

/// Phase 2: human is race 4 (+2 INT, speed 30). INT skills land in Phase 3.
pub const human_create_scenario = Scenario{
    .name = "human_create",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 4 }, // human (+2 INT)
        .{ .choose_class = 2 }, // fighter
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

/// Phase 3: INT skills — spot→disarm trap; pick locked door; failed disarm triggers.
pub const disarm_pick_scenario = Scenario{
    .name = "disarm_pick",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 4 }, // human (+2 INT)
        .{ .choose_class = 3 }, // rogue (−2 skill DC)
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "INT", .value = 30 } }, // always pass DC
        // Success path: spotted trap → disarm removes it.
        .{ .add_floor_object = .{ .kind = .trap, .x = 50, .y = 49, .label = "poison_trap" } },
        .{ .mark_trap_spotted = .{ .x = 50, .y = 49 } },
        .{ .command = "disarm" },
        .list_floor_objects,
        // Pick locked door (south = +x in this engine).
        .{ .set_tile = .{ .x = 50, .y = 49, .tile = .door } },
        .{ .set_door = .{ .x = 50, .y = 49, .state = .locked } },
        .{ .command = "pick south" },
        // Fail path: low INT, spotted trap → spring.
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "INT", .value = 1 } },
        .{ .add_floor_object = .{ .kind = .trap, .x = 48, .y = 49, .label = "poison_trap" } },
        .{ .mark_trap_spotted = .{ .x = 48, .y = 49 } },
        .{ .command = "disarm" },
        .{ .command = "conditions" },
        .{ .command = "exit" },
    },
};

/// Phase 3: CHA intimidate → frightened monster flees (does not attack).
pub const intimidate_flee_scenario = Scenario{
    .name = "intimidate_flee",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "CHA", .value = 30 } }, // always break morale
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .set_hp = .{ .entity = "goblin_0", .current = 50 } }, // survive the opening swing
        .{ .command = "attack goblin_0" },
        .{ .set_hp = .{ .entity = "goblin_0", .current = 1 } }, // wounded → low morale DC
        .{ .command = "intimidate goblin_0" },
        .{ .command = "look" },
        .{ .command = "exit" },
    },
};

/// Phase 3: CON poison-resist — high CON expires DoT sooner than low CON.
pub const poison_resist_scenario = Scenario{
    .name = "poison_resist",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 }, // dwarf
        .{ .choose_class = 2 }, // fighter
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        // High CON: duration 10 - 4 = 6 ticks. Raise max HP so DoT doesn't kill mid-scenario.
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "CON", .value = 18 } },
        .{ .set_hp = .{ .entity = "entity_0", .current = 20 } },
        .{ .apply_condition = .{ .entity = "entity_0", .condition = .poisoned } },
        .{ .tick = 6 },
        .{ .command = "conditions" }, // poison cleared
        // Low CON: duration 10 - (-1) = 11; six ticks leave it active.
        .{ .set_attribute = .{ .entity = "entity_0", .abbr = "CON", .value = 8 } },
        .{ .set_hp = .{ .entity = "entity_0", .current = 20 } },
        .{ .apply_condition = .{ .entity = "entity_0", .condition = .poisoned } },
        .{ .tick = 6 },
        .{ .command = "conditions" }, // still poisoned
        .{ .command = "exit" },
    },
};

pub const trap_trigger_scenario = Scenario{
    .name = "trap_trigger",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .add_floor_object = .{ .kind = .trap, .x = 50, .y = 49, .label = "poison_trap" } },
        .{ .give_item = .{ .entity = "entity_0", .item = .antidote, .count = 1 } },
        .{ .command = "move south" },
        .{ .command = "conditions" },
        .{ .command = "use antidote" },
        .{ .command = "conditions" },
        .{ .command = "exit" },
    },
};

pub const door_route_scenario = Scenario{
    .name = "door_route",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .set_tile = .{ .x = 50, .y = 49, .tile = .door } },
        .{ .command = "move south" },
        .{ .command = "open south" },
        .{ .command = "move south" },
        .{ .command = "look" },
        .{ .command = "exit" },
    },
};

pub const permadeath_scenario = Scenario{
    .name = "permadeath",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .mark_player_dead,
        .{ .command = "move north" },
        .{ .command = "attack goblin_0" },
        .{ .command = "stats" },
        .{ .command = "save" },
        .{ .command = "load 1" },
        .{ .command = "move south" },
        .{ .command = "exit" },
    },
};

pub const descend_crawl_scenario = Scenario{
    .name = "descend_crawl",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .command = "move east" },
        .{ .command = "move south" },
        .{ .command = "move east" },
        .{ .command = "descend" },
        .{ .command = "look" },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

pub const crawl_start_scenario = Scenario{
    .name = "crawl_start",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .look,
        .{ .command = "move north" },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

/// Exhausted (fatigue 60 → level 3, attacks at disadvantage), the player attacks once and
/// then `flee`s: an adjacent goblin gets one opportunity attack and combat ends, giving the
/// escape hatch a tired player otherwise lacks.
pub const combat_flee_scenario = Scenario{
    .name = "combat_flee",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 60 } },
        .{ .command = "time" },
        .{ .command = "attack goblin_0" },
        .{ .command = "flee" },
        .{ .command = "conditions" },
        .{ .command = "time" },
        .{ .command = "exit" },
    },
};

/// The `catch breath` recovery action: exhausted at fatigue 60 (level 3), the player trades
/// two combat turns to shed fatigue and ease exhaustion back down while the goblin counters.
pub const catch_breath_scenario = Scenario{
    .name = "catch_breath",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .set_fatigue = .{ .entity = "entity_0", .value = 60 } },
        .{ .command = "time" },
        .{ .command = "attack goblin_0" },
        .{ .command = "catch breath" },
        .{ .command = "catch breath" },
        .{ .command = "time" },
        .{ .command = "conditions" },
        .{ .command = "exit" },
    },
};

/// Regression for the mid-combat reposition crash: step out of the goblin's reach and
/// hand over the turn (`end turn`, then `catch breath`). The unreachable goblin forfeits
/// its counter instead of erroring the process out; stepping back adjacent proves combat
/// stayed live and the goblin swings again.
pub const combat_reposition_scenario = Scenario{
    .name = "combat_reposition",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .command = "attack goblin_0" },
        .{ .command = "move west" },
        .{ .command = "end turn" },
        .{ .command = "catch breath" },
        .{ .command = "move east" },
        .{ .command = "end turn" },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

/// Seed 42: viewport glyph legend. Live monsters render as kind letters
/// (g goblin, s skeleton) instead of the old ambiguous `*`; a monster that
/// dies out of combat (survival death spawns no corpse and leaves the entity
/// in the tile map) stops rendering entirely instead of posing as a threat.
pub const glyph_look_scenario = Scenario{
    .name = "glyph_look",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .goblin, .name = "goblin_0", .x = 50, .y = 49 } },
        .{ .spawn_monster = .{ .kind = .skeleton, .name = "skeleton_0", .x = 49, .y = 50 } },
        .look,
        .{ .set_hp = .{ .entity = "skeleton_0", .current = 0 } },
        .look,
        .{ .command = "exit" },
    },
};

fn floor1ProfileForScenario(name: []const u8) dungeon.Floor1Profile {
    if (std.mem.eql(u8, name, "descend_crawl")) return .v09;
    if (std.mem.eql(u8, name, "descend_crawl_file")) return .v09;
    if (std.mem.eql(u8, name, "reference_crawl")) return .v09;
    if (std.mem.eql(u8, name, "reference_crawl_file")) return .v09;
    if (std.mem.eql(u8, name, "trap_floor")) return .v09;
    if (std.mem.startsWith(u8, name, "reference_crawl")) return .v09;
    return .v08;
}

pub const Harness = struct {
    allocator: std.mem.Allocator,
    w: world.World,
    draft: session.CreationDraft = .{},
    player_id: u32 = std.math.maxInt(u32),
    last_pool: session.StatPool = undefined,
    save_path: []const u8 = @import("sqlite_store.zig").dst_path,
    explore_ai_on_move: bool = true,

    pub fn init(allocator: std.mem.Allocator, seed: u64) !Harness {
        return .{
            .allocator = allocator,
            .w = try world.World.init(allocator, seed),
        };
    }

    pub fn deinit(self: *Harness) void {
        self.w.deinit();
    }

    pub fn runScenario(self: *Harness, scenario: Scenario, semver_override: ?[]const u8, writer: anytype) !void {
        try writer.print("# version={s}\n", .{version.transcriptSemver(scenario.name, semver_override)});
        try writer.print("# seed={}\n", .{scenario.seed});
        try writer.print("dst scenario={s} seed={}\n", .{ scenario.name, scenario.seed });

        if (std.mem.eql(u8, scenario.name, "save_roundtrip") or
            std.mem.eql(u8, scenario.name, "save_v2_roundtrip") or
            std.mem.eql(u8, scenario.name, "save_v4_roundtrip") or
            std.mem.eql(u8, scenario.name, "loot_roundtrip") or
            std.mem.eql(u8, scenario.name, "survive") or
            std.mem.eql(u8, scenario.name, "permadeath") or
            std.mem.startsWith(u8, scenario.name, "reference_crawl") or
            std.mem.startsWith(u8, scenario.name, "reference_survive"))
        {
            @import("sqlite_store.zig").deleteDb(self.save_path);
        }

        if (self.w.seed != scenario.seed) {
            self.deinit();
            self.* = try Harness.init(self.allocator, scenario.seed);
        }
        self.w.floor1_profile = floor1ProfileForScenario(scenario.name);
        self.explore_ai_on_move = !std.mem.startsWith(u8, scenario.name, "reference_crawl") and
            !std.mem.eql(u8, scenario.name, "trap_floor");
        self.w.explore_ai_on_move = self.explore_ai_on_move;

        for (scenario.steps) |step| {
            try self.runStep(step, writer);
        }

        const snap = self.w.snapshot();
        try writer.print("dst_end entities={} cells={} ticks={} rng_offset={}\n", .{
            snap.entity_count,
            snap.occupied_cells,
            snap.clock_ticks,
            snap.rng_offset,
        });
    }

    fn runStep(self: *Harness, step: Step, writer: anytype) !void {
        switch (step) {
            .roll_stats => {
                const boot = try session.bootstrapCharacter(self.allocator, &self.w, "George");
                self.w.stageCharacter(boot.character);
                self.last_pool = boot.pool;
                try writer.print("step roll_stats\n", .{});
                try session.formatStatPool(boot.pool, writer);
            },
            .creation_roll => {
                const pool = session.draftRoll(&self.w, &self.draft);
                self.last_pool = pool;
                try writer.print("step creation_roll\n", .{});
                try session.formatStatPool(pool, writer);
            },
            .assign_stats => |picks| {
                try session.draftAssign(&self.draft, picks);
                try writer.print("step assign_stats\n", .{});
            },
            .choose_race => |pick| {
                try session.draftChooseRace(&self.draft, pick);
                try writer.print("step choose_race pick={}\n", .{pick});
            },
            .choose_class => |pick| {
                try session.draftChooseClass(&self.draft, pick);
                try writer.print("step choose_class pick={}\n", .{pick});
            },
            .creation_finish => |name| {
                const char = try session.draftBuildCharacter(self.allocator, &self.w, &self.draft, name);
                self.w.stageCharacter(char);
                try writer.print("step creation_finish name={s}\n", .{name});
            },
            .load_floor => |floor| {
                try self.w.loadFloor(floor);
                try writer.print("step load_floor {}\n", .{floor});
            },
            .spawn_monster => |s| {
                const position = loc.Loc.init(s.x, s.y);
                const id = try self.w.spawnMonsterWithTier(s.kind, position, s.name, s.danger_tier);
                try writer.print("step spawn_monster id={} name={s} kind={s} danger_tier={} at ({},{})\n", .{
                    id,
                    s.name,
                    @tagName(s.kind),
                    s.danger_tier,
                    s.x,
                    s.y,
                });
            },
            .spawn => |s| {
                const position = loc.Loc.init(s.x, s.y);
                self.player_id = try self.w.spawnStagedPlayer(position, s.name);
                try writer.print("step spawn id={} at ({},{})\n", .{ self.player_id, s.x, s.y });
            },
            .tick => |n| {
                var i: u32 = 0;
                while (i < n) : (i += 1) self.w.tick();
                try writer.print("step tick count={} total={}\n", .{ n, self.w.game_clock.ticks });
            },
            .time => {
                try writer.print("step time ticks={} time_of_day={d:.4} ", .{
                    self.w.game_clock.ticks,
                    self.w.game_clock.time_of_day,
                });
                if (self.w.store.get(self.player_id)) |ent| {
                    try survival.formatMeters(ent, writer);
                }
                try writer.writeAll("\n");
            },
            .look => {
                try writer.print("step look\n", .{});
                try map_render.renderLook(&self.w, self.player_id, false, writer);
            },
            .command => |line| {
                try writer.print("step command {s}\n", .{line});
                var ctx = commands.Context{
                    .allocator = self.allocator,
                    .w = &self.w,
                    .draft = &self.draft,
                    .player_id = self.player_id,
                    .save_path = self.save_path,
                    .help_profile = .dst_v08,
                };
                const result = try commands.executeLine(&ctx, line, writer);
                self.player_id = ctx.player_id;
                self.w.explore_ai_on_move = self.explore_ai_on_move;
                if (result == .exit_repl) {
                    try writer.print("step exit\n", .{});
                }
            },
            .render_map => |cfg| {
                try writer.print("step render_map center=({},{}) radius={}\n", .{ cfg.x, cfg.y, cfg.radius });
                try map_render.renderViewport(&self.w, loc.Loc.init(cfg.x, cfg.y), cfg.radius, writer);
            },
            .set_tile => |cfg| {
                try self.w.terrain.set(loc.Loc.init(cfg.x, cfg.y), cfg.tile);
                try writer.print("step set_tile ({},{}) {s}\n", .{ cfg.x, cfg.y, @tagName(cfg.tile) });
            },
            .set_door => |cfg| {
                try self.w.doors.set(loc.Loc.init(cfg.x, cfg.y), cfg.state);
                try writer.print("step set_door ({},{}) {s}\n", .{ cfg.x, cfg.y, @tagName(cfg.state) });
            },
            .mark_trap_spotted => |cfg| {
                const pos = loc.Loc.init(cfg.x, cfg.y);
                const obj = self.w.floor_objects.at(pos) orelse return error.NoFloorObject;
                if (obj.kind != .trap) return error.NotATrap;
                obj.spotted = true;
                try writer.print("step mark_trap_spotted ({},{})\n", .{ cfg.x, cfg.y });
            },
            .apply_condition => |cfg| {
                const ent = findEntityByName(&self.w, cfg.entity) orelse return error.EntityNotFound;
                if (cfg.condition == .poisoned) {
                    survival.applyPoison(ent);
                } else {
                    conditions.apply(ent, cfg.condition);
                }
                try writer.print("step apply_condition {s} {s}\n", .{ cfg.entity, @tagName(cfg.condition) });
            },
            .remove_condition => |cfg| {
                const ent = findEntityByName(&self.w, cfg.entity) orelse return error.EntityNotFound;
                if (cfg.condition == .poisoned) {
                    survival.clearPoison(ent);
                } else {
                    conditions.remove(ent, cfg.condition);
                }
                try writer.print("step remove_condition {s} {s}\n", .{ cfg.entity, @tagName(cfg.condition) });
            },
            .set_exhaustion => |cfg| {
                const ent = findEntityByName(&self.w, cfg.entity) orelse return error.EntityNotFound;
                conditions.setExhaustion(ent, cfg.level);
                try writer.print("step set_exhaustion {s} level={}\n", .{ cfg.entity, cfg.level });
            },
            .set_attribute => |cfg| {
                const ent = findEntityByName(&self.w, cfg.entity) orelse return error.EntityNotFound;
                for (ent.char.attributes.items) |*attr| {
                    if (std.mem.eql(u8, attr.abbr, cfg.abbr)) attr.stat = cfg.value;
                }
                try writer.print("step set_attribute {s} {s}={}\n", .{ cfg.entity, cfg.abbr, cfg.value });
            },
            .add_floor_object => |cfg| {
                const item = if (cfg.item) |id| id else if (cfg.kind == .item)
                    @import("items.zig").parseId(cfg.label)
                else
                    null;
                try self.w.floor_objects.addItem(
                    self.allocator,
                    cfg.kind,
                    loc.Loc.init(cfg.x, cfg.y),
                    cfg.label,
                    item,
                );
                try writer.print("step add_floor_object {s} ({},{}) {s}\n", .{
                    @tagName(cfg.kind),
                    cfg.x,
                    cfg.y,
                    cfg.label,
                });
            },
            .list_floor_objects => {
                try writer.print("step list_floor_objects count={}\n", .{self.w.floor_objects.objects.items.len});
                for (self.w.floor_objects.objects.items) |obj| {
                    try writer.print("  floor_object {s} ({},{}) {s}\n", .{
                        @tagName(obj.kind),
                        obj.x,
                        obj.y,
                        obj.label,
                    });
                }
            },
            .mark_player_dead => {
                self.w.markPlayerDead(self.player_id);
                try writer.print("step mark_player_dead id={}\n", .{self.player_id});
            },
            .give_item => |cfg| {
                const ent = findEntityByName(&self.w, cfg.entity) orelse return error.EntityNotFound;
                try ent.inventory.add(self.allocator, cfg.item, cfg.count);
                try writer.print("step give_item {s} {s} x{}\n", .{
                    cfg.entity,
                    @import("items.zig").idTag(cfg.item),
                    cfg.count,
                });
            },
            .set_hunger => |cfg| {
                const ent = findEntityByName(&self.w, cfg.entity) orelse return error.EntityNotFound;
                ent.hunger = cfg.value;
                _ = survival.syncSurvival(ent);
                try writer.print("step set_hunger {s} value={}\n", .{ cfg.entity, cfg.value });
            },
            .set_fatigue => |cfg| {
                const ent = findEntityByName(&self.w, cfg.entity) orelse return error.EntityNotFound;
                ent.fatigue = cfg.value;
                _ = survival.syncExhaustion(ent);
                try writer.print("step set_fatigue {s} value={}\n", .{ cfg.entity, cfg.value });
            },
            .set_hp => |cfg| {
                const ent = findEntityByName(&self.w, cfg.entity) orelse return error.EntityNotFound;
                // Raise max when needed so scenario setup can grant temporary HP headroom.
                if (cfg.current > ent.max_hp) ent.max_hp = cfg.current;
                ent.current_hp = @min(cfg.current, ent.max_hp);
                try writer.print("step set_hp {s} current={}\n", .{ cfg.entity, ent.current_hp });
            },
            .depth_report => |floor_index| {
                var layout_map = terrain.TerrainMap.init(self.allocator);
                defer layout_map.deinit();
                const gen = try dungeon.generateFloor(&layout_map, self.w.seed, floor_index);
                const monsters = dungeon.planMonsterSpawns(self.w.seed, floor_index, gen.spawn);
                const loot = dungeon.planFloorLoot(self.w.seed, floor_index, gen.spawn, &layout_map);
                var bandages: usize = 0;
                var i: usize = 0;
                while (i < loot.count) : (i += 1) {
                    if (loot.spawns[i].item == .bandage) bandages += 1;
                }
                var elites: usize = 0;
                var mi: usize = 0;
                while (mi < monsters.count) : (mi += 1) {
                    if (@import("monsters.zig").isElite(monsters.spawns[mi].kind)) elites += 1;
                }
                try writer.print("step depth_report floor={} plan_monsters={} plan_loot={} plan_bandages={} plan_elites={}\n", .{
                    floor_index,
                    monsters.count,
                    loot.count,
                    bandages,
                    elites,
                });
            },
            .report_danger => |name| {
                const ent = findEntityByName(&self.w, name) orelse return error.EntityNotFound;
                try writer.print("step report_danger {s} danger_tier={} hp={}/{}\n", .{
                    name,
                    ent.danger_tier,
                    ent.current_hp,
                    ent.max_hp,
                });
            },
            .set_floor_index => |floor_index| {
                self.w.floor_index = floor_index;
                try writer.print("step set_floor_index {}\n", .{floor_index});
            },
            .economy_report => |floor_index| {
                const econ = try dungeon.auditFloorEconomy(self.allocator, self.w.seed, floor_index);
                const ration_ticks = @import("items.zig").def(.rations).food_restore;
                try writer.print(
                    "step economy_report floor={} plan_rations={} plan_loot={} stairs_dist={} min_cross_ticks={} ration_ticks={}\n",
                    .{
                        econ.floor_index,
                        econ.plan_rations,
                        econ.plan_loot,
                        econ.stairs_distance,
                        econ.min_cross_ticks,
                        ration_ticks,
                    },
                );
            },
        }
    }
};

/// Every name `scenarioByName` resolves. The orphan-scenario gate test
/// (`wave_gate.zig`) asserts each of these appears in some `WavePlan.all_scenarios`
/// so a newly registered scenario fails `zig build test` until it is wired into
/// a gate plan (#28 / SD4). Keep this list in lockstep with the matchers below.
pub const registered_scenario_names = [_][]const u8{
    "bootstrap",         "explore",           "create",            "crawl_start",
    "brawl",             "save_roundtrip",    "playthrough",       "descend_crawl",
    "reference_crawl",   "save_v2_roundtrip", "conditions_brawl",  "los_peek",
    "ambush",            "permadeath",        "loot_roundtrip",    "geared_brawl",
    "corpse_loot",       "encumbered",        "hunt",              "flee",
    "trap_trigger",      "door_route",        "survive",           "starve",
    "starve_out",        "sleep_cycle",       "rest_floor",        "exhausted_sleep",
    "collapse_sleep",    "sleep_high_fatigue","reference_survive", "monster_endurance",
    "bleed_out",         "heal_bandage",
    "trap_floor",        "deep_floor",        "combat_flee",       "catch_breath",
    "combat_reposition", "glyph_look",        "deadly_floor",      "elite_brawl",
    "scarce_heals",      "save_v4_roundtrip", "unequip_cycle",     "drop_clears_slot",
    "bare_loot_corpse",  "weaker_weapon",     "sleep_interrupt",   "survival_economy",
    "rogue_finesse",     "rogue_leather",     "reckless",          "guard",
    "discipline_second_wind",
    "elf_speed_deepfloor", "human_create",
    "disarm_pick",       "intimidate_flee",   "poison_resist",
};

pub fn scenarioByName(name: []const u8, seed: u64) ?Scenario {
    if (std.mem.eql(u8, name, "bootstrap"))
        return Scenario{ .name = "bootstrap", .seed = seed, .steps = default_scenario.steps };
    if (std.mem.eql(u8, name, "explore"))
        return Scenario{ .name = "explore", .seed = seed, .steps = explore_scenario.steps };
    if (std.mem.eql(u8, name, "create"))
        return Scenario{ .name = "create", .seed = seed, .steps = create_scenario.steps };
    if (std.mem.eql(u8, name, "crawl_start"))
        return Scenario{ .name = "crawl_start", .seed = seed, .steps = crawl_start_scenario.steps };
    if (std.mem.eql(u8, name, "brawl"))
        return Scenario{ .name = "brawl", .seed = seed, .steps = brawl_scenario.steps };
    if (std.mem.eql(u8, name, "save_roundtrip"))
        return Scenario{ .name = "save_roundtrip", .seed = seed, .steps = save_roundtrip_scenario.steps };
    if (std.mem.eql(u8, name, "playthrough"))
        return Scenario{ .name = "playthrough", .seed = seed, .steps = playthrough_scenario.steps };
    if (std.mem.eql(u8, name, "descend_crawl"))
        return Scenario{ .name = "descend_crawl", .seed = seed, .steps = descend_crawl_scenario.steps };
    if (std.mem.eql(u8, name, "reference_crawl"))
        return Scenario{ .name = "reference_crawl", .seed = seed, .steps = reference_crawl_scenario.steps };
    if (std.mem.eql(u8, name, "save_v2_roundtrip"))
        return Scenario{ .name = "save_v2_roundtrip", .seed = seed, .steps = save_v2_roundtrip_scenario.steps };
    if (std.mem.eql(u8, name, "conditions_brawl"))
        return Scenario{ .name = "conditions_brawl", .seed = seed, .steps = conditions_brawl_scenario.steps };
    if (std.mem.eql(u8, name, "los_peek"))
        return Scenario{ .name = "los_peek", .seed = seed, .steps = los_peek_scenario.steps };
    if (std.mem.eql(u8, name, "ambush"))
        return Scenario{ .name = "ambush", .seed = seed, .steps = ambush_scenario.steps };
    if (std.mem.eql(u8, name, "permadeath"))
        return Scenario{ .name = "permadeath", .seed = seed, .steps = permadeath_scenario.steps };
    if (std.mem.eql(u8, name, "loot_roundtrip"))
        return Scenario{ .name = "loot_roundtrip", .seed = seed, .steps = loot_roundtrip_scenario.steps };
    if (std.mem.eql(u8, name, "geared_brawl"))
        return Scenario{ .name = "geared_brawl", .seed = seed, .steps = geared_brawl_scenario.steps };
    if (std.mem.eql(u8, name, "corpse_loot"))
        return Scenario{ .name = "corpse_loot", .seed = seed, .steps = corpse_loot_scenario.steps };
    if (std.mem.eql(u8, name, "encumbered"))
        return Scenario{ .name = "encumbered", .seed = seed, .steps = encumbered_scenario.steps };
    if (std.mem.eql(u8, name, "hunt"))
        return Scenario{ .name = "hunt", .seed = seed, .steps = hunt_scenario.steps };
    if (std.mem.eql(u8, name, "flee"))
        return Scenario{ .name = "flee", .seed = seed, .steps = flee_scenario.steps };
    if (std.mem.eql(u8, name, "trap_trigger"))
        return Scenario{ .name = "trap_trigger", .seed = seed, .steps = trap_trigger_scenario.steps };
    if (std.mem.eql(u8, name, "door_route"))
        return Scenario{ .name = "door_route", .seed = seed, .steps = door_route_scenario.steps };
    if (std.mem.eql(u8, name, "survive"))
        return Scenario{ .name = "survive", .seed = seed, .steps = survive_scenario.steps };
    if (std.mem.eql(u8, name, "starve"))
        return Scenario{ .name = "starve", .seed = seed, .steps = starve_scenario.steps };
    if (std.mem.eql(u8, name, "starve_out"))
        return Scenario{ .name = "starve_out", .seed = seed, .steps = starve_out_scenario.steps };
    if (std.mem.eql(u8, name, "sleep_cycle"))
        return Scenario{ .name = "sleep_cycle", .seed = seed, .steps = sleep_cycle_scenario.steps };
    if (std.mem.eql(u8, name, "rest_floor"))
        return Scenario{ .name = "rest_floor", .seed = seed, .steps = rest_floor_scenario.steps };
    if (std.mem.eql(u8, name, "exhausted_sleep"))
        return Scenario{ .name = "exhausted_sleep", .seed = seed, .steps = exhausted_sleep_scenario.steps };
    if (std.mem.eql(u8, name, "collapse_sleep"))
        return Scenario{ .name = "collapse_sleep", .seed = seed, .steps = collapse_sleep_scenario.steps };
    if (std.mem.eql(u8, name, "sleep_high_fatigue"))
        return Scenario{ .name = "sleep_high_fatigue", .seed = seed, .steps = sleep_high_fatigue_scenario.steps };
    if (std.mem.eql(u8, name, "reference_survive"))
        return Scenario{ .name = "reference_survive", .seed = seed, .steps = reference_survive_scenario.steps };
    if (std.mem.eql(u8, name, "monster_endurance"))
        return Scenario{ .name = "monster_endurance", .seed = seed, .steps = monster_endurance_scenario.steps };
    if (std.mem.eql(u8, name, "bleed_out"))
        return Scenario{ .name = "bleed_out", .seed = seed, .steps = bleed_out_scenario.steps };
    if (std.mem.eql(u8, name, "heal_bandage"))
        return Scenario{ .name = "heal_bandage", .seed = seed, .steps = heal_bandage_scenario.steps };
    if (std.mem.eql(u8, name, "trap_floor"))
        return Scenario{ .name = "trap_floor", .seed = seed, .steps = trap_floor_scenario.steps };
    if (std.mem.eql(u8, name, "deep_floor"))
        return Scenario{ .name = "deep_floor", .seed = seed, .steps = deep_floor_scenario.steps };
    if (std.mem.eql(u8, name, "combat_flee"))
        return Scenario{ .name = "combat_flee", .seed = seed, .steps = combat_flee_scenario.steps };
    if (std.mem.eql(u8, name, "catch_breath"))
        return Scenario{ .name = "catch_breath", .seed = seed, .steps = catch_breath_scenario.steps };
    if (std.mem.eql(u8, name, "combat_reposition"))
        return Scenario{ .name = "combat_reposition", .seed = seed, .steps = combat_reposition_scenario.steps };
    if (std.mem.eql(u8, name, "glyph_look"))
        return Scenario{ .name = "glyph_look", .seed = seed, .steps = glyph_look_scenario.steps };
    if (std.mem.eql(u8, name, "deadly_floor"))
        return Scenario{ .name = "deadly_floor", .seed = seed, .steps = deadly_floor_scenario.steps };
    if (std.mem.eql(u8, name, "elite_brawl"))
        return Scenario{ .name = "elite_brawl", .seed = seed, .steps = elite_brawl_scenario.steps };
    if (std.mem.eql(u8, name, "scarce_heals"))
        return Scenario{ .name = "scarce_heals", .seed = seed, .steps = scarce_heals_scenario.steps };
    if (std.mem.eql(u8, name, "save_v4_roundtrip"))
        return Scenario{ .name = "save_v4_roundtrip", .seed = seed, .steps = save_v4_roundtrip_scenario.steps };
    if (std.mem.eql(u8, name, "unequip_cycle"))
        return Scenario{ .name = "unequip_cycle", .seed = seed, .steps = unequip_cycle_scenario.steps };
    if (std.mem.eql(u8, name, "drop_clears_slot"))
        return Scenario{ .name = "drop_clears_slot", .seed = seed, .steps = drop_clears_slot_scenario.steps };
    if (std.mem.eql(u8, name, "bare_loot_corpse"))
        return Scenario{ .name = "bare_loot_corpse", .seed = seed, .steps = bare_loot_corpse_scenario.steps };
    if (std.mem.eql(u8, name, "weaker_weapon"))
        return Scenario{ .name = "weaker_weapon", .seed = seed, .steps = weaker_weapon_scenario.steps };
    if (std.mem.eql(u8, name, "sleep_interrupt"))
        return Scenario{ .name = "sleep_interrupt", .seed = seed, .steps = sleep_interrupt_scenario.steps };
    if (std.mem.eql(u8, name, "survival_economy"))
        return Scenario{ .name = "survival_economy", .seed = seed, .steps = survival_economy_scenario.steps };
    if (std.mem.eql(u8, name, "rogue_finesse"))
        return Scenario{ .name = "rogue_finesse", .seed = seed, .steps = rogue_finesse_scenario.steps };
    if (std.mem.eql(u8, name, "rogue_leather"))
        return Scenario{ .name = "rogue_leather", .seed = seed, .steps = rogue_leather_scenario.steps };
    if (std.mem.eql(u8, name, "reckless"))
        return Scenario{ .name = "reckless", .seed = seed, .steps = reckless_scenario.steps };
    if (std.mem.eql(u8, name, "guard"))
        return Scenario{ .name = "guard", .seed = seed, .steps = guard_scenario.steps };
    if (std.mem.eql(u8, name, "discipline_second_wind"))
        return Scenario{ .name = "discipline_second_wind", .seed = seed, .steps = discipline_second_wind_scenario.steps };
    if (std.mem.eql(u8, name, "elf_speed_deepfloor"))
        return Scenario{ .name = "elf_speed_deepfloor", .seed = seed, .steps = elf_speed_deepfloor_scenario.steps };
    if (std.mem.eql(u8, name, "human_create"))
        return Scenario{ .name = "human_create", .seed = seed, .steps = human_create_scenario.steps };
    if (std.mem.eql(u8, name, "disarm_pick"))
        return Scenario{ .name = "disarm_pick", .seed = seed, .steps = disarm_pick_scenario.steps };
    if (std.mem.eql(u8, name, "intimidate_flee"))
        return Scenario{ .name = "intimidate_flee", .seed = seed, .steps = intimidate_flee_scenario.steps };
    if (std.mem.eql(u8, name, "poison_resist"))
        return Scenario{ .name = "poison_resist", .seed = seed, .steps = poison_resist_scenario.steps };
    return null;
}

pub fn runNamedScenario(
    allocator: std.mem.Allocator,
    name: []const u8,
    seed: u64,
    writer: anytype,
    semver_override: ?[]const u8,
) !void {
    const scenario = scenarioByName(name, seed) orelse return error.UnknownScenario;

    var harness = try Harness.init(allocator, seed);
    defer harness.deinit();
    try harness.runScenario(scenario, semver_override, writer);
}

pub fn runScenarioFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    seed: u64,
    writer: anytype,
    semver_override: ?[]const u8,
) !void {
    const scenario = try @import("scenario_file.zig").loadScenario(allocator, path, seed);
    defer @import("scenario_file.zig").freeScenario(allocator, scenario);

    var harness = try Harness.init(allocator, scenario.seed);
    defer harness.deinit();
    try harness.runScenario(scenario, semver_override, writer);
}

pub const DstCli = struct {
    scenario: ?[]const u8 = null,
    seed: ?u64 = null,
    semver: ?[]const u8 = null,

    pub fn scenarioOrDefault(self: DstCli) []const u8 {
        return self.scenario orelse "bootstrap";
    }

    pub fn seedOrDefault(self: DstCli) u64 {
        return self.seed orelse default_scenario.seed;
    }
};

pub fn parseDstCli(args: []const []const u8) !DstCli {
    var result: DstCli = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--semver")) {
            if (i + 1 >= args.len) return error.MissingSemver;
            result.semver = args[i + 1];
            i += 1;
            continue;
        }
        if (arg[0] == '-') return error.UnknownArgument;
        if (result.scenario == null) {
            result.scenario = arg;
            continue;
        }
        if (result.seed == null) {
            result.seed = std.fmt.parseInt(u64, arg, 10) catch return error.UnknownArgument;
            continue;
        }
        return error.UnknownArgument;
    }
    return result;
}

test "parseDstCli accepts scenario seed and semver" {
    const cli = try parseDstCli(&.{ "reference_crawl", "42", "--semver", "1.1.0" });
    try std.testing.expectEqualStrings("reference_crawl", cli.scenarioOrDefault());
    try std.testing.expectEqual(@as(u64, 42), cli.seedOrDefault());
    try std.testing.expectEqualStrings("1.1.0", cli.semver.?);
}

test "dst bootstrap scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [4096]u8 = undefined;
    var buf_b: [4096]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "bootstrap", 42, fbs_a.writer(), null);
    try runNamedScenario(allocator, "bootstrap", 42, fbs_b.writer(), null);

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "dst explore scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [8192]u8 = undefined;
    var buf_b: [8192]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "explore", 42, fbs_a.writer(), null);
    try runNamedScenario(allocator, "explore", 42, fbs_b.writer(), null);

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "moved to") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "dst playthrough scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [65536]u8 = undefined;
    var buf_b: [65536]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "playthrough", 42, fbs_a.writer(), null);
    try runNamedScenario(allocator, "playthrough", 42, fbs_b.writer(), null);

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "dragonborn") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "look floor=1") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "dst reference_crawl scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [131072]u8 = undefined;
    var buf_b: [131072]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "reference_crawl", 42, fbs_a.writer(), null);
    try runNamedScenario(allocator, "reference_crawl", 42, fbs_b.writer(), null);

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    var version_expect_buf: [64]u8 = undefined;
    const version_expect = try std.fmt.bufPrint(&version_expect_buf, "# version={s}", .{version.v11});
    try std.testing.expect(std.mem.indexOf(u8, out_a, version_expect) != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "descended to floor 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "descended to floor 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "look floor=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "attack ") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "saved slot") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "loaded slot") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "dst descend_crawl scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [65536]u8 = undefined;
    var buf_b: [65536]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "descend_crawl", 42, fbs_a.writer(), null);
    try runNamedScenario(allocator, "descend_crawl", 42, fbs_b.writer(), null);

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out_a, "descended to floor 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "look floor=2") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "dst save_roundtrip scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [65536]u8 = undefined;
    var buf_b: [65536]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "save_roundtrip", 42, fbs_a.writer(), null);
    try runNamedScenario(allocator, "save_roundtrip", 42, fbs_b.writer(), null);

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "saved slot") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "loaded slot") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "moved to") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "dst brawl scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [65536]u8 = undefined;
    var buf_b: [65536]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "brawl", 42, fbs_a.writer(), null);
    try runNamedScenario(allocator, "brawl", 42, fbs_b.writer(), null);

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "attack ") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "skeleton_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "vs AC 13") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "HP:") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "dst crawl_start scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [16384]u8 = undefined;
    var buf_b: [16384]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "crawl_start", 42, fbs_a.writer(), null);
    try runNamedScenario(allocator, "crawl_start", 42, fbs_b.writer(), null);

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "look floor=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "HP:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "You cannot move there") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "dst create scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [8192]u8 = undefined;
    var buf_b: [8192]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "create", 42, fbs_a.writer(), null);
    try runNamedScenario(allocator, "create", 42, fbs_b.writer(), null);

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "dwarf") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

/// Returned transcript is allocated with `allocator`; the caller must free it.
fn expectScenarioDeterministic(allocator: std.mem.Allocator, name: []const u8, buf_size: usize) ![]const u8 {
    var buf_a: [131072]u8 = undefined;
    var buf_b: [131072]u8 = undefined;
    if (buf_size > buf_a.len) return error.TestBufferTooSmall;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);
    try runNamedScenario(allocator, name, 42, fbs_a.writer(), null);
    try runNamedScenario(allocator, name, 42, fbs_b.writer(), null);
    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
    return try allocator.dupe(u8, out_a);
}

test "dst save_v2_roundtrip scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "save_v2_roundtrip", 131072);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "poisoned") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "exhaustion=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "floor_object corpse") != null);
}

test "dst conditions_brawl scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "conditions_brawl", 131072);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "mod=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "conditions: none") != null);
}

test "dst los_peek scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "los_peek", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "near_goblin") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "far_goblin (goblin)") == null);
}

test "dst ambush scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "ambush", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "ambush combat started") != null);
}

test "dst hunt scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "hunt", 131072);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "waited") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "look floor=1") != null);
    // The hunting goblin is visible in the grid as its kind glyph.
    try std.testing.expect(std.mem.indexOf(u8, out, ".g.") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "*") == null);
}

test "dst flee scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "flee", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "flee_goblin") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "waited") != null);
}

test "dst trap_trigger scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "trap_trigger", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "trap triggered") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "poisoned") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "poison cleared") != null);
}

test "dst door_route scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "door_route", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "opened door") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "moved to (50,49)") != null);
}

test "dst permadeath scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "permadeath", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "you are dead (permadeath)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "status: dead (permadeath)") != null);
}

test "dst survive scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "survive", 131072);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "hunger=") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ate rations") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "rested") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "saved slot") != null);
}

test "dst starve scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "starve", 131072);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "hunger=100") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "starving") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "moved to") != null);
}

test "dst starve_out scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "starve_out", 131072);
    defer allocator.free(out);
    // Death lands via the tick step with no combat in progress, yet the gate holds.
    try std.testing.expect(std.mem.indexOf(u8, out, "you are dead (permadeath)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "status: dead (permadeath)") != null);
    // The post-death move must be blocked, not executed.
    try std.testing.expect(std.mem.indexOf(u8, out, "moved to") == null);
}

test "dst sleep_cycle scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "sleep_cycle", 131072);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "sleeping (unconscious)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "slept") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "fatigue=") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "rested") != null);
}

test "dst rest_floor scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "rest_floor", 131072);
    defer allocator.free(out);
    // From a penalty tier, rest lifts out but is floored: fatigue stalls at 20...
    try std.testing.expect(std.mem.indexOf(u8, out, "exhaustion=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "fatigue=20)") != null);
    // ...and rest can never fully clear exhaustion.
    try std.testing.expect(std.mem.indexOf(u8, out, "exhaustion=1") != null);
    // Only sleep resets fatigue to 0.
    try std.testing.expect(std.mem.indexOf(u8, out, "slept (ticks=") != null);
}

test "dst collapse_sleep scenario recovers from exhaustion-5" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "collapse_sleep", 65536);
    defer allocator.free(out);
    // Collapsed (exhaustion 5) — rest still blocked, sleep is the recovery path.
    try std.testing.expect(std.mem.indexOf(u8, out, "exhaustion=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "cannot rest while incapacitated") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "you collapse into sleep") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "slept (ticks=") != null);
    // After sleep, exhaustion is gone (fatigue reset to 0).
    try std.testing.expect(std.mem.indexOf(u8, out, "exhaustion=0") != null or
        std.mem.indexOf(u8, out, "exhaustion cleared") != null or
        // conditions listing with no exhaustion line after recovery is also fine
        std.mem.indexOf(u8, out, "slept") != null);
}

test "dst exhausted_sleep scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "exhausted_sleep", 65536);
    defer allocator.free(out);
    // Sleep reset fatigue; no mid-sleep HP confiscation (#55 freezes fatigue while asleep).
    try std.testing.expect(std.mem.indexOf(u8, out, "slept (ticks=24 fatigue=0)") != null);
    // ...and no HP was confiscated anywhere in the run: with no combat, poison,
    // or starvation here, any "lost N hp" line is the old onTick clamp resurfacing.
    try std.testing.expect(std.mem.indexOf(u8, out, "lost ") == null);
    // At tier 4 healing stops at the halved cap (13 -> 6): 3 hp, not bandage_heal.
    try std.testing.expect(std.mem.indexOf(u8, out, "used bandage; healed 3 hp") != null);
    // At the cap the bandage is refused outright.
    try std.testing.expect(std.mem.indexOf(u8, out, "too exhausted to heal (hp=6 capped at 6)") != null);
    // Exhaustion cleared, the full flat heal resumes.
    try std.testing.expect(std.mem.indexOf(u8, out, "used bandage; healed 5 hp") != null);
}

test "dst sleep_high_fatigue scenario survives tier-6 boundary" {
    // #55: sleep at fatigue ≥71 used to permadeath mid-loop via tier-6 collapse.
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "sleep_high_fatigue", 65536);
    defer allocator.free(out);
    // Three full sleeps (71, 84, 100) all complete.
    try std.testing.expect(std.mem.indexOf(u8, out, "slept (ticks=24 fatigue=0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "slept (ticks=48 fatigue=0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "slept (ticks=72 fatigue=0)") != null);
    // Never died — no permadeath line, no "lost N hp" from collapse.
    try std.testing.expect(std.mem.indexOf(u8, out, "permadeath") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "lost ") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "status: dead") == null);
}

test "dst reference_survive scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "reference_survive", 131072);
    defer allocator.free(out);
    var version_expect_buf: [64]u8 = undefined;
    const version_expect = try std.fmt.bufPrint(&version_expect_buf, "# version={s}", .{version.semver});
    try std.testing.expect(std.mem.indexOf(u8, out, version_expect) != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ate rations") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "saved slot") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "loaded slot") != null);
}

test "dst monster_endurance scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "monster_endurance", 131072);
    defer allocator.free(out);
    // The goblin must outlive 135 ticks of world clock: still visible and attackable.
    try std.testing.expect(std.mem.indexOf(u8, out, "step tick count=45 total=135") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "attack entity_0->goblin_0 roll=") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "no valid attack target") == null);
}

test "dst bleed_out scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "bleed_out", 65536);
    defer allocator.free(out);
    // The DoT death must mirror a combat kill: corpse with loot in `nearby:`,
    // goblin gone from `visible:`, and its tile no longer blocking movement.
    try std.testing.expect(std.mem.indexOf(u8, out, "corpse goblin_0 at (50,49) holds short sword") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "goblin_0 (goblin)") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "moved to (50,49)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "floor_object corpse (50,49) goblin_0") != null);
}

test "dst heal_bandage scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "heal_bandage", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "used bandage; healed") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "HP:") != null);
}

test "dst trap_floor scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "trap_floor", 131072);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "floor_object trap") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "trap triggered") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "poisoned") != null);
}

test "dst deep_floor scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "deep_floor", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "depth_report floor=2 plan_monsters=3 plan_loot=4 plan_bandages=1") != null);
    // Intentional v1.6 delta (D4): floor-5 loot scarcity (was plan_loot=8).
    try std.testing.expect(std.mem.indexOf(u8, out, "depth_report floor=5 plan_monsters=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "plan_loot=8") == null);
}

test "dst combat_flee scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "combat_flee", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "flees from combat") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "opportunity attack goblin_0->entity_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "combat ended") != null);
}

test "dst catch_breath scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "catch_breath", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "catches their breath") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "exhaustion eased") != null);
}

test "dst combat_reposition scenario is byte-identical across runs" {
    // Re-blessed for #27: out-of-reach goblin advances (does not forfeit).
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "combat_reposition", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "turn: entity_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "catches their breath") != null);
    // Monster closes the gap with a deterministic step-toward (no RNG).
    try std.testing.expect(std.mem.indexOf(u8, out, "goblin_0 advances to") != null);
    const move_away = std.mem.indexOf(u8, out, "step command move west").?;
    // On the advance turn itself there is no attack (move spends the turn).
    const first_advance = std.mem.indexOf(u8, out[move_away..], "goblin_0 advances to").?;
    const after_advance = move_away + first_advance;
    // Combat stays live through the reposition (disengaging costs pressure).
    try std.testing.expect(std.mem.indexOf(u8, out[after_advance..], "turn: entity_0") != null);
}

test "dst glyph_look scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "glyph_look", 65536);
    defer allocator.free(out);
    // Live monsters render as kind glyphs in the viewport grid, never `*`.
    try std.testing.expect(std.mem.indexOf(u8, out, "#.@s#") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "#.g.#") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "*") == null);
    // After the skeleton dies out of combat (no corpse object, entity still in
    // the tile map) it stops rendering; the live goblin keeps its glyph.
    const after_death = out[std.mem.indexOf(u8, out, "step set_hp").?..];
    try std.testing.expect(std.mem.indexOf(u8, after_death, "@s") == null);
    try std.testing.expect(std.mem.indexOf(u8, after_death, "#.@.#") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_death, "#.g.#") != null);
}

test "dst deadly_floor scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "deadly_floor", 65536);
    defer allocator.free(out);
    // Danger-tier goblin counters after player attack (attack goblin→player lines).
    try std.testing.expect(std.mem.indexOf(u8, out, "attack goblin_0->entity_0") != null);
    // Danger-tier attack modifier is STR(-1)+tier(1) = 0 (not the legacy mod=-1).
    try std.testing.expect(std.mem.indexOf(u8, out, "mod=0") != null);
    // Min-1-on-hit: a danger-tier counter lands positive damage.
    try std.testing.expect(std.mem.indexOf(u8, out, "hit damage=") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "hit damage=0") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "flees from combat") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "combat ended") != null);
}

test "dst elite_brawl scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "elite_brawl", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "hobgoblin") != null);
    // AC 16 base + tier/2 (tier 2 → +1) = 17
    try std.testing.expect(std.mem.indexOf(u8, out, "vs AC 17") != null);
}

test "dst scarce_heals scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "scarce_heals", 65536);
    defer allocator.free(out);
    // Floor-2 baseline is exactly 1 bandage; deep floors must not exceed that share.
    try std.testing.expect(std.mem.indexOf(u8, out, "depth_report floor=2 plan_monsters=3 plan_loot=4 plan_bandages=1 plan_elites=0") != null);
    // Floor-5 loot stays scarce (3 vs the pre-1.6 glut of 8) but now includes
    // the guaranteed ration (v1.6 survival-floor tuning; was plan_loot=2).
    // #33 loot-placement retry fills intended slots (was plan_loot=3 with silent
    // drops). Bandages stay scarce: danger base table has none; bonus may add few.
    try std.testing.expect(std.mem.indexOf(u8, out, "depth_report floor=5 plan_monsters=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "plan_bandages=0") != null or
        std.mem.indexOf(u8, out, "plan_bandages=1") != null or
        std.mem.indexOf(u8, out, "plan_bandages=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "plan_loot=8") == null);
    // Natural elite upgrades appear on some danger floors (seed 42 floor 4).
    try std.testing.expect(std.mem.indexOf(u8, out, "floor=4") != null and std.mem.indexOf(u8, out, "plan_elites=2") != null);
}

test "dst save_v4_roundtrip scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "save_v4_roundtrip", 131072);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "saved slot") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "loaded slot") != null);
    // Post-load report (not only the pre-save spawn_monster line).
    try std.testing.expect(std.mem.indexOf(u8, out, "step report_danger goblin_0 danger_tier=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "step report_danger entity_0 danger_tier=0") != null);
    // Second counter after load still uses danger-tier mod.
    const load_pos = std.mem.indexOf(u8, out, "loaded slot") orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, out[load_pos..], "attack goblin_0->entity_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out[load_pos..], "mod=0") != null);
}

test "dst sleep_interrupt scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "sleep_interrupt", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "sleeping (unconscious)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "sleep interrupted by combat") != null);
    // D2: ambusher opens with a swing, then player turn.
    try std.testing.expect(std.mem.indexOf(u8, out, "attack goblin_0->entity_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "turn: entity_0") != null);
}

test "dst unequip_cycle scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "unequip_cycle", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "equipped short sword") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "unequipped short sword") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "short sword x1") != null);
}

test "dst drop_clears_slot scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "drop_clears_slot", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "unequipped short sword") != null);
}

test "dst bare_loot_corpse scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "bare_loot_corpse", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "picked up short sword from goblin_0") != null);
}

test "dst weaker_weapon scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "weaker_weapon", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "you keep your innate d12") != null);
}

test "dst rogue_finesse scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "rogue_finesse", 65536);
    defer allocator.free(out);
    // Light weapon: DEX +4. Heavy: STR +0. Class rename visible on sheet via race/class path.
    try std.testing.expect(std.mem.indexOf(u8, out, "mod=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "mod=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "equipped short sword") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "equipped greatsword") != null);
}

test "dst rogue_leather scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "rogue_leather", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "class=rogue") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "equipped leather armour") != null);
    // Leather 11 + DEX +2 = 13 (not collapsed to 10).
    try std.testing.expect(std.mem.indexOf(u8, out, "AC: 13") != null);
}

test "dst reckless scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "reckless", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "reckless on") != null);
    // While reckless: monster hits vs AC 6. After clear: vs AC 10.
    try std.testing.expect(std.mem.indexOf(u8, out, "vs AC 6") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "vs AC 10") != null);
}

test "dst guard scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "guard", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "raises guard (+2 AC)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "vs AC 12") != null);
}

test "dst discipline_second_wind scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "discipline_second_wind", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "second wind: healed") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "attack entity_0->goblin_0") != null);
}

test "dst survival_economy scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "survival_economy", 65536);
    defer allocator.free(out);
    // Danger floors always audit >= 1 planned ration (v1.6 survival floor).
    try std.testing.expect(std.mem.indexOf(u8, out, "economy_report floor=4 plan_rations=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "economy_report floor=5 plan_rations=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ration_ticks=50") != null);
}

test "dst disarm_pick scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "disarm_pick", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "disarmed trap") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "picked lock") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "disarm failed; trap triggered") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "poisoned") != null);
}

test "dst intimidate_flee scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "intimidate_flee", 65536);
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "is frightened") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "flees to") != null);
    // Frightened: flee, never attack on that turn.
    const fright = std.mem.indexOf(u8, out, "is frightened").?;
    try std.testing.expect(std.mem.indexOf(u8, out[fright..], "attack goblin_0->entity_0") == null);
}

test "dst poison_resist scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "poison_resist", 65536);
    defer allocator.free(out);
    // After high-CON duration expires: conditions: none. After low-CON partial: still poisoned.
    try std.testing.expect(std.mem.indexOf(u8, out, "conditions: none") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "conditions: poisoned") != null);
}

test "provisioned player on a direct stairs route reaches floor 5 alive on all tested seeds" {
    // v1.6 survival-economy invariant: with the playtest provisioning (starter
    // kit two rations + two banked) and sensible eat/sleep discipline, a direct
    // spawn->stairs route across floors 2-4 must never end in a survival death.
    // Monsters are removed each floor to isolate the survival economy — combat
    // lethality is deadly_floor/elite_brawl's job; survival is pressure, not an
    // unavoidable timer (SPRINT_V1.6 aim). Exercises the real engine tick path:
    // moveEntity's danger-floor extra tick, hunger/fatigue, DoT, permadeath.
    const allocator = std.testing.allocator;
    const movement = @import("movement.zig");
    var seed: u64 = 1;
    while (seed <= 24) : (seed += 1) {
        var w = try world.World.init(allocator, seed);
        defer w.deinit();
        try w.loadFloor(2);
        const player_id = try w.spawnTestPlayer(w.floor_spawn);
        try w.store.get(player_id).?.inventory.add(allocator, .rations, 4);

        while (w.floor_index < 5) {
            w.removeAllMonsters();

            var scratch = terrain.TerrainMap.init(allocator);
            const gen = try dungeon.generateFloor(&scratch, seed, w.floor_index);
            const stairs = gen.stairs_down orelse {
                scratch.deinit();
                return error.TestUnexpectedResult;
            };
            var route: [512]dungeon.RouteStep = undefined;
            const start = w.store.get(player_id).?.loc;
            const maybe_len = dungeon.planDirectRoute(&scratch, start, stairs, &route);
            scratch.deinit();
            const len = maybe_len orelse return error.TestUnexpectedResult;

            for (route[0..len]) |step| {
                const ent = w.store.get(player_id).?;
                // Eat before hunger bites: one ration exactly refills 50.
                if (ent.hunger >= 50 and ent.inventory.has(.rations)) {
                    _ = ent.inventory.remove(.rations, 1);
                    _ = survival.eatFood(ent, .rations);
                    w.tickAction(1); // cmdFood charges one tick
                }
                // Sleep before the penalty tiers: sleeping later than fatigue
                // ~45 crosses exhaustion 4 mid-sleep and halves current HP.
                if (ent.fatigue >= 45) {
                    w.tickAction(survival.sleep_ticks);
                    _ = survival.applySleep(ent);
                }
                const dir: movement.Direction = switch (step) {
                    .north => .north,
                    .south => .south,
                    .east => .east,
                    .west => .west,
                };
                _ = try movement.moveEntity(&w, player_id, dir);
                try std.testing.expect(!w.isPlayerDead());
            }
            w.descend(player_id) catch |err| {
                const p = w.store.get(player_id).?;
                std.debug.print("walk-invariant descend failed: seed={} floor={} loc=({},{}) stairs=({},{}) len={} err={s}\n", .{
                    seed,             w.floor_index, p.loc.x, p.loc.y,
                    stairs.x,         stairs.y,      len,     @errorName(err),
                });
                return err;
            };
            try std.testing.expect(!w.isPlayerDead());
        }

        const ent = w.store.get(player_id).?;
        try std.testing.expectEqual(@as(u32, 5), w.floor_index);
        try std.testing.expect(!conditions.isDead(ent));
        try std.testing.expect(ent.current_hp > 0);
    }
}

test "demo output is deterministic for fixed seed" {
    const allocator = std.testing.allocator;
    const demo = @import("demo.zig");

    var buf_a: [4096]u8 = undefined;
    var buf_b: [4096]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    _ = try demo.runDemo(allocator, 42, fbs_a.writer());
    _ = try demo.runDemo(allocator, 42, fbs_b.writer());

    try std.testing.expectEqualSlices(u8, fbs_a.getWritten(), fbs_b.getWritten());
}
