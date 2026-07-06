const std = @import("std");
const world = @import("world.zig");
const entity = @import("entity.zig");
const loc = @import("loc.zig");
const types = @import("types.zig");
const combat = @import("combat.zig");
const monsters = @import("monsters.zig");
const character = @import("character.zig");
const dungeon = @import("dungeon.zig");
const conditions = @import("conditions.zig");
const world_objects = @import("world_objects.zig");
const inventory = @import("inventory.zig");
const doors = @import("doors.zig");

pub const schema_version: u32 = 2;
pub const schema_version_v1: u32 = 1;

pub const EntitySave = struct {
    id: entity.EntityId,
    name: []const u8,
    x: u64,
    y: u64,
    movement: u8,
    char_name: []const u8,
    race_name: []const u8,
    class_name: []const u8,
    status: types.Status,
    str: u64,
    dex: u64,
    con: u64,
    int_stat: u64,
    wis: u64,
    cha: u64,
    conditions_bits: u32,
    exhaustion_level: u3 = 0,
    hunger: u16 = 100,
    fatigue: u16 = 0,
    sleeping: bool = false,
    current_hp: u32,
    max_hp: u32,
    damage_die: u8,
    is_monster: bool,
    gear: inventory.GearSave = .{ .bag = &.{} },
};

pub const MapCellSave = struct {
    x: u64,
    y: u64,
    entity_ids: []const entity.EntityId,
};

pub const CombatSave = struct {
    participants: []const entity.EntityId,
    turn_index: usize,
    player_id: entity.EntityId,
};

pub const WorldSave = struct {
    schema_version: u32,
    seed: u64,
    rng_state: u64,
    rng_offset: u16,
    floor_index: u32,
    floor1_profile: dungeon.Floor1Profile = .v09,
    has_dungeon: bool,
    clock_ticks: u64,
    clock_time_of_day: f64,
    clock_seconds_per_day: f64,
    clock_update_rate: f64,
    clock_time_multiplier: f64,
    next_entity_id: entity.EntityId,
    player_id: entity.EntityId,
    entities: []EntitySave,
    map_cells: []MapCellSave,
    combat: ?CombatSave,
    floor_objects: []world_objects.ObjectSave = &.{},
    door_states: []doors.DoorSave = &.{},
    player_dead: bool = false,

    pub fn deinit(self: *WorldSave, allocator: std.mem.Allocator) void {
        for (self.entities) |ent| {
            allocator.free(ent.name);
            allocator.free(ent.char_name);
            allocator.free(ent.race_name);
            allocator.free(ent.class_name);
            allocator.free(ent.gear.bag);
        }
        allocator.free(self.entities);
        for (self.map_cells) |cell| allocator.free(cell.entity_ids);
        allocator.free(self.map_cells);
        if (self.combat) |c| allocator.free(c.participants);
        for (self.floor_objects) |obj| allocator.free(obj.label);
        allocator.free(self.floor_objects);
        allocator.free(self.door_states);
    }
};

pub fn conditionsToBits(set: types.ConditionSet) u32 {
    var bits: u32 = 0;
    inline for (std.meta.fields(types.Condition)) |field| {
        const cond = @field(types.Condition, field.name);
        if (set.has(cond)) bits |= @as(u32, 1) << @intFromEnum(cond);
    }
    return bits;
}

pub fn bitsToConditions(bits: u32) types.ConditionSet {
    var set = types.ConditionSet.initEmpty();
    inline for (std.meta.fields(types.Condition)) |field| {
        const cond = @field(types.Condition, field.name);
        if ((bits & (@as(u32, 1) << @intFromEnum(cond))) != 0) set.add(cond);
    }
    return set;
}

fn statByAbbr(char: *const types.Character, abbr: []const u8) u64 {
    for (char.attributes.items) |attr| {
        if (std.mem.eql(u8, attr.abbr, abbr)) return attr.stat;
    }
    return 0;
}

pub fn capture(allocator: std.mem.Allocator, w: *const world.World, player_id: entity.EntityId) !WorldSave {
    var entities: std.ArrayList(EntitySave) = .empty;
    errdefer {
        for (entities.items) |ent| {
            allocator.free(ent.name);
            allocator.free(ent.char_name);
            allocator.free(ent.race_name);
            allocator.free(ent.class_name);
        }
        entities.deinit(allocator);
    }

    for (w.store.entities.items) |ent| {
        const char = ent.char.*;
        try entities.append(allocator, .{
            .id = ent.id,
            .name = try allocator.dupe(u8, ent.name),
            .x = ent.loc.x,
            .y = ent.loc.y,
            .movement = ent.movement,
            .char_name = try allocator.dupe(u8, char.name),
            .race_name = try allocator.dupe(u8, char.race.name),
            .class_name = try allocator.dupe(u8, char.class.name),
            .status = char.status,
            .str = statByAbbr(&char, "STR"),
            .dex = statByAbbr(&char, "DEX"),
            .con = statByAbbr(&char, "CON"),
            .int_stat = statByAbbr(&char, "INT"),
            .wis = statByAbbr(&char, "WIS"),
            .cha = statByAbbr(&char, "CHA"),
            .conditions_bits = conditions.toBits(&ent),
            .exhaustion_level = ent.exhaustion_level,
            .hunger = ent.hunger,
            .fatigue = ent.fatigue,
            .sleeping = ent.sleeping,
            .current_hp = ent.current_hp,
            .max_hp = ent.max_hp,
            .damage_die = ent.damage_die,
            .is_monster = ent.is_monster,
            .gear = try inventory.toSave(allocator, &ent.inventory),
        });
    }

    var cells: std.ArrayList(MapCellSave) = .empty;
    errdefer {
        for (cells.items) |cell| allocator.free(cell.entity_ids);
        cells.deinit(allocator);
    }

    var it = w.tile_map.cells.iterator();
    while (it.next()) |entry| {
        const ids = try allocator.alloc(entity.EntityId, entry.value_ptr.items.len);
        @memcpy(ids, entry.value_ptr.items);
        try cells.append(allocator, .{
            .x = entry.key_ptr.x,
            .y = entry.key_ptr.y,
            .entity_ids = ids,
        });
    }

    var combat_save: ?CombatSave = null;
    if (w.combat) |c| {
        const parts = try allocator.alloc(entity.EntityId, c.participants.items.len);
        @memcpy(parts, c.participants.items);
        combat_save = .{
            .participants = parts,
            .turn_index = c.turn_index,
            .player_id = c.player_id,
        };
    }

    var obj_list: std.ArrayList(world_objects.ObjectSave) = .empty;
    errdefer {
        for (obj_list.items) |obj| allocator.free(obj.label);
        obj_list.deinit(allocator);
    }
    for (w.floor_objects.objects.items) |obj| {
        try obj_list.append(allocator, .{
            .kind = obj.kind,
            .x = obj.x,
            .y = obj.y,
            .label = try allocator.dupe(u8, obj.label),
            .item = obj.item,
        });
    }

    var door_list: std.ArrayList(doors.DoorSave) = .empty;
    errdefer door_list.deinit(allocator);
    var door_it = w.doors.states.iterator();
    while (door_it.next()) |entry| {
        try door_list.append(allocator, .{
            .x = entry.key_ptr.x,
            .y = entry.key_ptr.y,
            .state = entry.value_ptr.*,
        });
    }

    return .{
        .schema_version = schema_version,
        .seed = w.seed,
        .rng_state = w.rng.state,
        .rng_offset = w.rng.offset,
        .floor_index = w.floor_index,
        .floor1_profile = w.floor1_profile,
        .has_dungeon = w.has_dungeon,
        .clock_ticks = w.game_clock.ticks,
        .clock_time_of_day = w.game_clock.time_of_day,
        .clock_seconds_per_day = w.game_clock.seconds_per_day,
        .clock_update_rate = w.game_clock.update_rate,
        .clock_time_multiplier = w.game_clock.time_multiplier,
        .next_entity_id = w.next_entity_id,
        .player_id = player_id,
        .entities = try entities.toOwnedSlice(allocator),
        .map_cells = try cells.toOwnedSlice(allocator),
        .combat = combat_save,
        .floor_objects = try obj_list.toOwnedSlice(allocator),
        .door_states = try door_list.toOwnedSlice(allocator),
        .player_dead = w.player_dead,
    };
}

fn findRace(w: *const world.World, name: []const u8) types.Race {
    for (w.races.items) |race| {
        if (std.mem.eql(u8, race.name, name)) return race;
    }
    return w.races.items[0];
}

fn findClass(name: []const u8) types.Class {
    for (types.defaultClasses()) |cls| {
        if (std.mem.eql(u8, cls.name, name)) return cls;
    }
    return types.defaultClasses()[0];
}

fn buildCharacter(allocator: std.mem.Allocator, w: *const world.World, ent: EntitySave) !*types.Character {
    const attrs = try types.defaultAttributes(allocator);
    for (attrs.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "STR")) attr.stat = ent.str;
        if (std.mem.eql(u8, attr.abbr, "DEX")) attr.stat = ent.dex;
        if (std.mem.eql(u8, attr.abbr, "CON")) attr.stat = ent.con;
        if (std.mem.eql(u8, attr.abbr, "INT")) attr.stat = ent.int_stat;
        if (std.mem.eql(u8, attr.abbr, "WIS")) attr.stat = ent.wis;
        if (std.mem.eql(u8, attr.abbr, "CHA")) attr.stat = ent.cha;
    }
    const char = try allocator.create(types.Character);
    char.* = .{
        .name = try allocator.dupe(u8, ent.char_name),
        .attributes = attrs,
        .race = findRace(w, ent.race_name),
        .class = findClass(ent.class_name),
        .status = ent.status,
    };
    return char;
}

pub fn apply(allocator: std.mem.Allocator, save: *const WorldSave) !world.World {
    var w = try world.World.init(allocator, save.seed);
    errdefer w.deinit();

    w.rng.state = save.rng_state;
    w.rng.offset = save.rng_offset;
    w.floor_index = save.floor_index;
    w.floor1_profile = save.floor1_profile;
    if (save.has_dungeon) try w.loadFloor(save.floor_index);
    w.game_clock.ticks = save.clock_ticks;
    w.game_clock.time_of_day = save.clock_time_of_day;
    w.game_clock.seconds_per_day = save.clock_seconds_per_day;
    w.game_clock.update_rate = save.clock_update_rate;
    w.game_clock.time_multiplier = save.clock_time_multiplier;
    w.next_entity_id = save.next_entity_id;

    for (save.entities) |ent_save| {
        const char_ptr = try buildCharacter(allocator, &w, ent_save);
        const position = loc.Loc.init(ent_save.x, ent_save.y);
        _ = try w.store.create(allocator, ent_save.id, ent_save.name, position, char_ptr);
        const ent = w.store.get(ent_save.id).?;
        ent.heap_char_name = true;
        ent.loc = position;
        ent.movement = ent_save.movement;
        ent.conditions = conditions.fromBits(ent_save.conditions_bits);
        ent.exhaustion_level = ent_save.exhaustion_level;
        ent.hunger = ent_save.hunger;
        ent.fatigue = ent_save.fatigue;
        ent.sleeping = ent_save.sleeping;
        ent.current_hp = ent_save.current_hp;
        ent.max_hp = ent_save.max_hp;
        ent.damage_die = ent_save.damage_die;
        ent.is_monster = ent_save.is_monster;
        ent.inventory = try inventory.fromSave(allocator, ent_save.gear);
    }

    for (save.map_cells) |cell| {
        for (cell.entity_ids) |id| {
            try w.tile_map.place(loc.Loc.init(cell.x, cell.y), id);
        }
    }

    w.player_dead = save.player_dead;
    for (save.floor_objects) |obj| {
        try w.floor_objects.addItem(w.allocator, obj.kind, loc.Loc.init(obj.x, obj.y), obj.label, obj.item);
    }
    for (save.door_states) |door| {
        try w.doors.set(loc.Loc.init(door.x, door.y), door.state);
    }

    if (save.combat) |c| {
        const combat_ptr = try allocator.create(combat.CombatState);
        combat_ptr.* = .{ .participants = .empty, .player_id = c.player_id };
        errdefer {
            combat_ptr.participants.deinit(allocator);
            allocator.destroy(combat_ptr);
        }
        for (c.participants) |pid| try combat_ptr.participants.append(allocator, pid);
        combat_ptr.turn_index = c.turn_index;
        w.combat = combat_ptr;
    }

    return w;
}

pub fn migrateV1ToV2(save: *WorldSave, allocator: std.mem.Allocator) !void {
    if (save.schema_version != schema_version_v1) return;
    save.schema_version = schema_version;
    save.floor_objects = try allocator.alloc(world_objects.ObjectSave, 0);
    save.player_dead = false;
    for (save.entities) |*ent| {
        ent.exhaustion_level = 0;
        ent.hunger = 100;
        ent.fatigue = 0;
        ent.sleeping = false;
    }
}

test "migrate v1 save adds v2 defaults" {
    const allocator = std.testing.allocator;
    var save = WorldSave{
        .schema_version = schema_version_v1,
        .seed = 42,
        .rng_state = 1,
        .rng_offset = 0,
        .floor_index = 1,
        .has_dungeon = true,
        .clock_ticks = 0,
        .clock_time_of_day = 0,
        .clock_seconds_per_day = 120,
        .clock_update_rate = 5,
        .clock_time_multiplier = 1,
        .next_entity_id = 1,
        .player_id = 0,
        .entities = &.{},
        .map_cells = &.{},
        .combat = null,
    };
    try migrateV1ToV2(&save, allocator);
    try std.testing.expectEqual(schema_version, save.schema_version);
    try std.testing.expectEqual(@as(usize, 0), save.floor_objects.len);
    try std.testing.expect(!save.player_dead);
}

pub fn replaceWorld(dst: *world.World, src: world.World) void {
    dst.deinit();
    dst.* = src;
}

pub fn expectEqual(a: *const WorldSave, b: *const WorldSave) !void {
    try std.testing.expectEqual(a.schema_version, b.schema_version);
    try std.testing.expectEqual(a.seed, b.seed);
    try std.testing.expectEqual(a.rng_state, b.rng_state);
    try std.testing.expectEqual(a.rng_offset, b.rng_offset);
    try std.testing.expectEqual(a.floor_index, b.floor_index);
    try std.testing.expectEqual(a.floor1_profile, b.floor1_profile);
    try std.testing.expectEqual(a.has_dungeon, b.has_dungeon);
    try std.testing.expectEqual(a.clock_ticks, b.clock_ticks);
    try std.testing.expect(a.clock_time_of_day == b.clock_time_of_day);
    try std.testing.expectEqual(a.next_entity_id, b.next_entity_id);
    try std.testing.expectEqual(a.player_id, b.player_id);
    try std.testing.expectEqual(a.entities.len, b.entities.len);
    try std.testing.expectEqual(a.map_cells.len, b.map_cells.len);

    var i: usize = 0;
    while (i < a.entities.len) : (i += 1) {
        const ea = a.entities[i];
        const eb = b.entities[i];
        try std.testing.expectEqual(ea.id, eb.id);
        try std.testing.expectEqualStrings(ea.name, eb.name);
        try std.testing.expectEqual(ea.x, eb.x);
        try std.testing.expectEqual(ea.y, eb.y);
        try std.testing.expectEqual(ea.current_hp, eb.current_hp);
        try std.testing.expectEqual(ea.max_hp, eb.max_hp);
        try std.testing.expectEqual(ea.conditions_bits, eb.conditions_bits);
        try std.testing.expectEqual(ea.is_monster, eb.is_monster);
        try std.testing.expectEqual(ea.status, eb.status);
    }
}

test "capture apply roundtrip preserves multi-floor state" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    var draft = @import("session.zig").CreationDraft{};
    _ = @import("session.zig").draftRoll(&w, &draft);
    try @import("session.zig").draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try @import("session.zig").draftChooseRace(&draft, 2);
    try @import("session.zig").draftChooseClass(&draft, 1);
    const char = try @import("session.zig").draftBuildCharacter(allocator, &w, &draft, "George");
    w.stageCharacter(char);
    const player_id = try w.spawnStagedPlayer(dungeon.floor1_spawn, "entity_0");
    try dungeon.walkSpawnToFloor1Stairs(&w, player_id);
    try w.descend(player_id);

    var before = try capture(allocator, &w, player_id);
    defer before.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 2), before.floor_index);

    var restored = try apply(allocator, &before);
    defer restored.deinit();
    try std.testing.expectEqual(@as(u32, 2), restored.floor_index);

    var after = try capture(allocator, &restored, player_id);
    defer after.deinit(allocator);
    try expectEqual(&before, &after);
}

test "capture apply roundtrip preserves crawl state" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    var draft = @import("session.zig").CreationDraft{};
    _ = @import("session.zig").draftRoll(&w, &draft);
    try @import("session.zig").draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try @import("session.zig").draftChooseRace(&draft, 2);
    try @import("session.zig").draftChooseClass(&draft, 1);
    const char = try @import("session.zig").draftBuildCharacter(allocator, &w, &draft, "George");
    w.stageCharacter(char);
    const player_id = try w.spawnStagedPlayer(loc.Loc.init(49, 49), "entity_0");
    _ = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");
    w.tick();
    w.tick();

    var before = try capture(allocator, &w, player_id);
    defer before.deinit(allocator);

    var restored = try apply(allocator, &before);
    defer restored.deinit();

    var after = try capture(allocator, &restored, player_id);
    defer after.deinit(allocator);
    try expectEqual(&before, &after);
}