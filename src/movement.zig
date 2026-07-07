const std = @import("std");
const loc = @import("loc.zig");
const world = @import("world.zig");
const entity = @import("entity.zig");

pub const Direction = enum {
    north,
    south,
    east,
    west,

    pub fn parse(word: []const u8) ?Direction {
        if (std.mem.eql(u8, word, "north") or std.mem.eql(u8, word, "n")) return .north;
        if (std.mem.eql(u8, word, "south") or std.mem.eql(u8, word, "s")) return .south;
        if (std.mem.eql(u8, word, "east") or std.mem.eql(u8, word, "e")) return .east;
        if (std.mem.eql(u8, word, "west") or std.mem.eql(u8, word, "w")) return .west;
        return null;
    }

    pub fn token(dir: Direction) []const u8 {
        return switch (dir) {
            .north => "n",
            .south => "s",
            .east => "e",
            .west => "w",
        };
    }
};

/// Compound compass shorthand (north-then-west, etc.).
pub fn parseCompound(word: []const u8) ?[2]Direction {
    if (std.mem.eql(u8, word, "nw")) return .{ .north, .west };
    if (std.mem.eql(u8, word, "ne")) return .{ .north, .east };
    if (std.mem.eql(u8, word, "sw")) return .{ .south, .west };
    if (std.mem.eql(u8, word, "se")) return .{ .south, .east };
    return null;
}

pub fn step(from: loc.Loc, dir: Direction) ?loc.Loc {
    return switch (dir) {
        .north => if (from.x == 0) null else loc.Loc.init(from.x - 1, from.y),
        .south => loc.Loc.init(from.x + 1, from.y),
        .east => loc.Loc.init(from.x, from.y + 1),
        .west => if (from.y == 0) null else loc.Loc.init(from.x, from.y - 1),
    };
}

/// Moves entity on the sparse map, ticks the clock on success.
pub fn moveEntity(w: *world.World, id: entity.EntityId, dir: Direction) !loc.Loc {
    const ent = w.store.get(id) orelse return error.EntityNotFound;
    const old_loc = ent.loc;
    const new_loc = step(old_loc, dir) orelse return error.Blocked;
    if (w.has_dungeon) {
        if (w.terrain.get(new_loc)) |tile| {
            if (!tile.isWalkable()) return error.Blocked;
            if (tile == .door and w.doors.blocksAt(&w.terrain, new_loc)) return error.Blocked;
        }
    }
    if (w.isTileBlockedFor(new_loc, id)) return error.Blocked;

    w.tile_map.remove(old_loc, id);
    try w.tile_map.place(new_loc, id);
    ent.loc = new_loc;
    w.tick();
    return new_loc;
}

test "moveEntity updates loc and map occupancy" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 1);
    defer w.deinit();

    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const start = loc.Loc.init(49, 49);

    try std.testing.expectEqual(@as(usize, 1), w.tile_map.entityCountAt(start));
    try std.testing.expectEqual(@as(usize, 0), w.tile_map.entityCountAt(loc.Loc.init(49, 50)));

    const after = try moveEntity(&w, id, .east);
    try std.testing.expectEqual(loc.Loc.init(49, 50), after);
    try std.testing.expectEqual(@as(usize, 0), w.tile_map.entityCountAt(start));
    try std.testing.expectEqual(@as(usize, 1), w.tile_map.entityCountAt(after));
    try std.testing.expectEqual(after.x, w.store.get(id).?.loc.x);
    try std.testing.expectEqual(after.y, w.store.get(id).?.loc.y);
}

test "moveEntity advances clock" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 1);
    defer w.deinit();

    const id = try w.spawnTestPlayer(loc.Loc.init(10, 10));
    try std.testing.expectEqual(@as(u64, 0), w.game_clock.ticks);

    _ = try moveEntity(&w, id, .south);
    try std.testing.expectEqual(@as(u64, 1), w.game_clock.ticks);
}

test "moveEntity rejects dungeon wall" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 1);
    defer w.deinit();
    try w.loadFloor(1);

    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    try std.testing.expectError(error.Blocked, moveEntity(&w, id, .north));
}

test "moveEntity allows stepping onto corpse floor object" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    try w.floor_objects.addItem(allocator, .corpse, loc.Loc.init(50, 49), "goblin_0", null);

    const new_loc = try moveEntity(&w, id, .south);
    try std.testing.expectEqual(loc.Loc.init(50, 49), new_loc);
}

test "moveEntity rejects large corpse on tile" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    try w.floor_objects.addItem(allocator, .corpse, loc.Loc.init(50, 49), "skeleton_0", null);

    try std.testing.expectError(error.Blocked, moveEntity(&w, id, .south));
}

test "moveEntity ignores dead entity still listed on tile map" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const monster_id = try w.spawnMonster(@import("monsters.zig").Kind.goblin, loc.Loc.init(50, 49), "goblin_0");
    const monster = w.store.get(monster_id).?;
    @import("conditions.zig").markDead(monster);

    const new_loc = try moveEntity(&w, player_id, .south);
    try std.testing.expectEqual(loc.Loc.init(50, 49), new_loc);
}

test "moveEntity rejects blocked tile" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 1);
    defer w.deinit();

    const a = try w.spawnTestPlayer(loc.Loc.init(5, 5));
    const b = try w.spawnTestPlayer(loc.Loc.init(5, 6));

    const a_loc = w.store.get(a).?.loc;
    const b_loc = w.store.get(b).?.loc;
    _ = a_loc;
    _ = b_loc;

    try std.testing.expectError(error.Blocked, moveEntity(&w, a, .east));
}