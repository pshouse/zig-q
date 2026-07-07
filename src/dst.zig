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

pub const Step = union(enum) {
    roll_stats,
    creation_roll,
    assign_stats: [6]usize,
    choose_race: usize,
    choose_class: usize,
    creation_finish: []const u8,
    load_floor: u32,
    spawn_monster: struct { kind: @import("monsters.zig").Kind, name: []const u8, x: u64, y: u64 },
    spawn: struct { name: []const u8, x: u64, y: u64 },
    tick: u32,
    time,
    look,
    command: []const u8,
    render_map: struct { x: u64, y: u64, radius: u8 },
    set_tile: struct { x: u64, y: u64, tile: terrain.Tile },
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
        .{ .give_item = .{ .entity = "entity_0", .item = .rations, .count = 1 } },
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
        .{ .give_item = .{ .entity = "entity_0", .item = .rations, .count = 2 } },
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

fn floor1ProfileForScenario(name: []const u8) dungeon.Floor1Profile {
    if (std.mem.eql(u8, name, "descend_crawl")) return .v09;
    if (std.mem.eql(u8, name, "descend_crawl_file")) return .v09;
    if (std.mem.eql(u8, name, "reference_crawl")) return .v09;
    if (std.mem.eql(u8, name, "reference_crawl_file")) return .v09;
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
        self.explore_ai_on_move = !std.mem.startsWith(u8, scenario.name, "reference_crawl");
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
                const id = try self.w.spawnMonster(s.kind, position, s.name);
                try writer.print("step spawn_monster id={} name={s} kind={s} at ({},{})\n", .{
                    id,
                    s.name,
                    @tagName(s.kind),
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
            .apply_condition => |cfg| {
                const ent = findEntityByName(&self.w, cfg.entity) orelse return error.EntityNotFound;
                conditions.apply(ent, cfg.condition);
                try writer.print("step apply_condition {s} {s}\n", .{ cfg.entity, @tagName(cfg.condition) });
            },
            .remove_condition => |cfg| {
                const ent = findEntityByName(&self.w, cfg.entity) orelse return error.EntityNotFound;
                conditions.remove(ent, cfg.condition);
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
        }
    }
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
    if (std.mem.eql(u8, name, "sleep_cycle"))
        return Scenario{ .name = "sleep_cycle", .seed = seed, .steps = sleep_cycle_scenario.steps };
    if (std.mem.eql(u8, name, "reference_survive"))
        return Scenario{ .name = "reference_survive", .seed = seed, .steps = reference_survive_scenario.steps };
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
    return out_a;
}

test "dst save_v2_roundtrip scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "save_v2_roundtrip", 131072);
    try std.testing.expect(std.mem.indexOf(u8, out, "poisoned") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "exhaustion=3") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "floor_object corpse") != null);
}

test "dst conditions_brawl scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "conditions_brawl", 131072);
    try std.testing.expect(std.mem.indexOf(u8, out, "mod=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "conditions: none") != null);
}

test "dst los_peek scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "los_peek", 65536);
    try std.testing.expect(std.mem.indexOf(u8, out, "near_goblin") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "far_goblin (goblin)") == null);
}

test "dst ambush scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "ambush", 65536);
    try std.testing.expect(std.mem.indexOf(u8, out, "ambush combat started") != null);
}

test "dst hunt scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "hunt", 131072);
    try std.testing.expect(std.mem.indexOf(u8, out, "waited") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "look floor=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "*") != null);
}

test "dst flee scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "flee", 65536);
    try std.testing.expect(std.mem.indexOf(u8, out, "flee_goblin") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "waited") != null);
}

test "dst trap_trigger scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "trap_trigger", 65536);
    try std.testing.expect(std.mem.indexOf(u8, out, "trap triggered") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "poisoned") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "poison cleared") != null);
}

test "dst door_route scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "door_route", 65536);
    try std.testing.expect(std.mem.indexOf(u8, out, "opened door") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "moved to (50,49)") != null);
}

test "dst permadeath scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "permadeath", 65536);
    try std.testing.expect(std.mem.indexOf(u8, out, "you are dead (permadeath)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "status: dead (permadeath)") != null);
}

test "dst survive scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "survive", 131072);
    try std.testing.expect(std.mem.indexOf(u8, out, "hunger=") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ate rations") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "rested") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "saved slot") != null);
}

test "dst starve scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "starve", 131072);
    try std.testing.expect(std.mem.indexOf(u8, out, "hunger=100") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "starving") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "moved to") != null);
}

test "dst sleep_cycle scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "sleep_cycle", 131072);
    try std.testing.expect(std.mem.indexOf(u8, out, "sleeping (unconscious)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "slept") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "fatigue=") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "rested") != null);
}

test "dst reference_survive scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    const out = try expectScenarioDeterministic(allocator, "reference_survive", 131072);
    var version_expect_buf: [64]u8 = undefined;
    const version_expect = try std.fmt.bufPrint(&version_expect_buf, "# version={s}", .{version.semver});
    try std.testing.expect(std.mem.indexOf(u8, out, version_expect) != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ate rations") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "saved slot") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "loaded slot") != null);
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