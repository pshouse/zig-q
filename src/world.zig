const std = @import("std");
const rng = @import("rng.zig");
const types = @import("types.zig");
const clock = @import("clock.zig");
const loc = @import("loc.zig");
const entity = @import("entity.zig");
const map = @import("map.zig");

pub const World = struct {
    allocator: std.mem.Allocator,
    seed: u64,
    rng: rng.SeededRng,
    store: entity.EntityStore,
    tile_map: map.TileMap,
    attribute_templates: std.ArrayList(types.Attribute),
    races: std.ArrayList(types.Race),
    game_clock: clock.Clock,
    next_entity_id: entity.EntityId,

    pub fn init(allocator: std.mem.Allocator, seed: u64) !World {
        var attribute_templates = try types.defaultAttributes(allocator);
        errdefer attribute_templates.deinit(allocator);

        var races = try types.defaultRaces(allocator);
        errdefer types.deinitRaceList(allocator, &races);

        return .{
            .allocator = allocator,
            .seed = seed,
            .rng = rng.SeededRng.init(seed),
            .store = entity.EntityStore.init(),
            .tile_map = map.TileMap.init(allocator),
            .attribute_templates = attribute_templates,
            .races = races,
            .game_clock = clock.Clock.init(0.45, 120.0, 5.0, 1.0),
            .next_entity_id = 0,
        };
    }

    pub fn deinit(self: *World) void {
        self.store.deinit(self.allocator);
        self.tile_map.deinit();
        self.attribute_templates.deinit(self.allocator);
        types.deinitRaceList(self.allocator, &self.races);
    }

    pub fn spawnPlayer(self: *World, character: *types.Character, position: loc.Loc, name: []const u8) !entity.EntityId {
        const id = self.next_entity_id;
        self.next_entity_id += 1;
        _ = try self.store.create(self.allocator, id, name, position, character);
        try self.tile_map.place(position, id);
        if (self.store.get(id)) |ent| ent.loc = position;
        return id;
    }

    pub fn tick(self: *World) void {
        self.game_clock.tick();
    }

    pub fn snapshot(self: *const World) Snapshot {
        return .{
            .seed = self.seed,
            .entity_count = self.store.count(),
            .occupied_cells = self.tile_map.occupiedCellCount(),
            .clock_ticks = self.game_clock.ticks,
            .rng_offset = self.rng.offset,
        };
    }
};

pub const Snapshot = struct {
    seed: u64,
    entity_count: usize,
    occupied_cells: usize,
    clock_ticks: u64,
    rng_offset: u16,
};

test "world init place deinit lifecycle" {
    const allocator = std.testing.allocator;

    var world = try World.init(allocator, 42);
    defer world.deinit();

    var attrs = try types.defaultAttributes(allocator);
    defer attrs.deinit(allocator);

    const char = try allocator.create(types.Character);
    defer allocator.destroy(char);
    char.* = .{
        .name = "George",
        .attributes = attrs,
        .race = world.races.items[0],
        .class = types.defaultClasses()[0],
    };

    const id = try world.spawnPlayer(char, loc.Loc.init(49, 49), "entity_0");
    try std.testing.expectEqual(@as(entity.EntityId, 0), id);
    try std.testing.expectEqual(@as(usize, 1), world.store.count());
    try std.testing.expectEqual(@as(usize, 1), world.tile_map.occupiedCellCount());
    try std.testing.expectEqual(@as(usize, 1), world.tile_map.entityCountAt(loc.Loc.init(49, 49)));
}

test "same seed yields identical world snapshot after spawn" {
    const allocator = std.testing.allocator;

    var a = try World.init(allocator, 99);
    defer a.deinit();
    var b = try World.init(allocator, 99);
    defer b.deinit();

    var attrs_a = try types.defaultAttributes(allocator);
    defer attrs_a.deinit(allocator);
    var attrs_b = try types.defaultAttributes(allocator);
    defer attrs_b.deinit(allocator);

    const char_a = try allocator.create(types.Character);
    defer allocator.destroy(char_a);
    char_a.* = .{
        .name = "George",
        .attributes = attrs_a,
        .race = a.races.items[0],
        .class = types.defaultClasses()[0],
    };
    const char_b = try allocator.create(types.Character);
    defer allocator.destroy(char_b);
    char_b.* = .{
        .name = "George",
        .attributes = attrs_b,
        .race = b.races.items[0],
        .class = types.defaultClasses()[0],
    };

    _ = try a.spawnPlayer(char_a, loc.Loc.init(49, 49), "entity_0");
    _ = try b.spawnPlayer(char_b, loc.Loc.init(49, 49), "entity_0");

    const sa = a.snapshot();
    const sb = b.snapshot();
    try std.testing.expectEqual(sa.seed, sb.seed);
    try std.testing.expectEqual(sa.entity_count, sb.entity_count);
    try std.testing.expectEqual(sa.occupied_cells, sb.occupied_cells);
    try std.testing.expectEqual(sa.clock_ticks, sb.clock_ticks);
    try std.testing.expectEqual(sa.rng_offset, sb.rng_offset);
}