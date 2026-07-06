const std = @import("std");
const loc = @import("loc.zig");
const terrain = @import("terrain.zig");
const rng = @import("rng.zig");
const monsters = @import("monsters.zig");
const items = @import("items.zig");

const TileEntry = struct {
    x: u64,
    y: u64,
    tile: terrain.Tile,
};

pub const Floor1Profile = enum {
    /// v0.8 regression layout: door (+) at (49,53) unreachable from spawn.
    v08,
    /// v0.9 playable layout: stairs (>) at south-east exit (50,51).
    v09,
};

/// Floor 1: small chamber around spawn (49,49). North wall blocks `move north`.
const floor1_tiles = [_]TileEntry{
    .{ .x = 47, .y = 47, .tile = .wall },
    .{ .x = 47, .y = 48, .tile = .wall },
    .{ .x = 47, .y = 49, .tile = .wall },
    .{ .x = 47, .y = 50, .tile = .wall },
    .{ .x = 47, .y = 51, .tile = .wall },
    .{ .x = 48, .y = 47, .tile = .wall },
    .{ .x = 48, .y = 48, .tile = .wall },
    .{ .x = 48, .y = 49, .tile = .wall },
    .{ .x = 48, .y = 50, .tile = .wall },
    .{ .x = 48, .y = 51, .tile = .wall },
    .{ .x = 49, .y = 47, .tile = .wall },
    .{ .x = 50, .y = 47, .tile = .wall },
    .{ .x = 51, .y = 47, .tile = .wall },
    .{ .x = 49, .y = 51, .tile = .wall },
    .{ .x = 50, .y = 51, .tile = .wall },
    .{ .x = 51, .y = 51, .tile = .wall },
    .{ .x = 51, .y = 48, .tile = .wall },
    .{ .x = 51, .y = 49, .tile = .wall },
    .{ .x = 51, .y = 50, .tile = .wall },
    .{ .x = 49, .y = 53, .tile = .door },
};

fn skipFloor1Tile(profile: Floor1Profile, entry: TileEntry) bool {
    if (profile != .v09) return false;
    // v0.9: replace far-east door and south-east wall with proper stairs.
    if (entry.x == 49 and entry.y == 53 and entry.tile == .door) return true;
    if (entry.x == 50 and entry.y == 51 and entry.tile == .wall) return true;
    return false;
}

pub fn loadFloor1(map: *terrain.TerrainMap, profile: Floor1Profile) !void {
    map.clear();
    for (floor1_tiles) |entry| {
        if (skipFloor1Tile(profile, entry)) continue;
        try map.set(loc.Loc.init(entry.x, entry.y), entry.tile);
    }
    if (profile == .v09) {
        try map.set(floor1_stairs_v09, .stairs);
    }
}

pub const floor1_spawn = loc.Loc.init(49, 49);
/// v0.8 regression descend trigger (door glyph).
pub const floor1_door_v08 = loc.Loc.init(49, 53);
/// v0.9 descend trigger at the chamber's south-east exit.
pub const floor1_stairs_v09 = loc.Loc.init(50, 51);

/// Moves from spawn to floor-1 stairs on the v0.9 layout: east, south, east.
pub fn walkSpawnToFloor1Stairs(w: *@import("world.zig").World, player_id: @import("entity.zig").EntityId) !void {
    const movement = @import("movement.zig");
    _ = try movement.moveEntity(w, player_id, .east);
    _ = try movement.moveEntity(w, player_id, .south);
    _ = try movement.moveEntity(w, player_id, .east);
}

pub fn floorSeed(world_seed: u64, floor_index: u32) u64 {
    return std.hash.Wyhash.hash(0, std.mem.asBytes(&world_seed)) ^
        (@as(u64, floor_index) *% 0x9E3779B97F4A7C15);
}

pub fn floorRng(world_seed: u64, floor_index: u32) rng.SeededRng {
    return rng.SeededRng.init(floorSeed(world_seed, floor_index));
}

pub const GeneratedFloor = struct {
    spawn: loc.Loc,
    stairs_down: ?loc.Loc,
    walkable_count: usize,
    layout_hash: u64,
};

const grid_w: usize = 24;
const grid_h: usize = 16;
const origin_x: u64 = 40;
const origin_y: u64 = 40;

fn gridToLoc(gx: usize, gy: usize) loc.Loc {
    return loc.Loc.init(origin_x + gx, origin_y + gy);
}

fn carveRoom(cells: *[grid_h][grid_w]bool, x: usize, y: usize, w: usize, h: usize) void {
    var dy: usize = 0;
    while (dy < h) : (dy += 1) {
        var dx: usize = 0;
        while (dx < w) : (dx += 1) {
            const gx = x + dx;
            const gy = y + dy;
            if (gx < grid_w and gy < grid_h) cells[gy][gx] = true;
        }
    }
}

fn carveAt(cells: *[grid_h][grid_w]bool, position: loc.Loc) void {
    if (position.x < origin_x or position.y < origin_y) return;
    const gx = position.x - origin_x;
    const gy = position.y - origin_y;
    if (gx >= grid_w or gy >= grid_h) return;
    cells[@intCast(gy)][@intCast(gx)] = true;
}

fn carveCorridor(cells: *[grid_h][grid_w]bool, from: loc.Loc, to: loc.Loc) void {
    var x = from.x;
    var y = from.y;
    while (x != to.x) {
        carveAt(cells, loc.Loc.init(x, y));
        if (x < to.x) x += 1 else x -= 1;
    }
    while (y != to.y) {
        carveAt(cells, loc.Loc.init(x, y));
        if (y < to.y) y += 1 else y -= 1;
    }
    carveAt(cells, to);
}

pub fn generateFloor(map: *terrain.TerrainMap, world_seed: u64, floor_index: u32) !GeneratedFloor {
    map.clear();
    var cells = [_][grid_w]bool{[_]bool{false} ** grid_w} ** grid_h;

    var floor_rng = floorRng(world_seed, floor_index);
    const room_count = 3 + (floor_rng.nextU8() % 3);
    var room_centers: [6]loc.Loc = undefined;
    var centers_len: usize = 0;

    var attempt: u8 = 0;
    while (centers_len < room_count and attempt < 32) : (attempt += 1) {
        const rw: usize = 4 + (floor_rng.nextU8() % 4);
        const rh: usize = 3 + (floor_rng.nextU8() % 3);
        const rx: usize = @intCast(floor_rng.nextU8() % @as(u8, @intCast(grid_w - rw - 1)));
        const ry: usize = @intCast(floor_rng.nextU8() % @as(u8, @intCast(grid_h - rh - 1)));
        carveRoom(&cells, rx, ry, rw, rh);
        const cx = origin_x + rx + rw / 2;
        const cy = origin_y + ry + rh / 2;
        room_centers[centers_len] = loc.Loc.init(cx, cy);
        centers_len += 1;
    }

    var i: usize = 1;
    while (i < centers_len) : (i += 1) {
        carveCorridor(&cells, room_centers[i - 1], room_centers[i]);
    }

    var walkable: usize = 0;
    var hash: u64 = 0;
    var gy: usize = 0;
    while (gy < grid_h) : (gy += 1) {
        var gx: usize = 0;
        while (gx < grid_w) : (gx += 1) {
            const position = gridToLoc(gx, gy);
            if (cells[gy][gx]) {
                try map.set(position, .floor);
                walkable += 1;
                hash ^= std.hash.Wyhash.hash(hash, std.mem.asBytes(&position.x));
                hash ^= std.hash.Wyhash.hash(hash, std.mem.asBytes(&position.y));
            } else {
                try map.set(position, .wall);
            }
        }
    }

    const spawn = room_centers[0];
    const stairs_loc = room_centers[centers_len - 1];
    try map.set(stairs_loc, .stairs);

    return .{
        .spawn = spawn,
        .stairs_down = stairs_loc,
        .walkable_count = walkable,
        .layout_hash = hash,
    };
}

fn offsetLoc(base: loc.Loc, dx: i64, dy: i64) loc.Loc {
    const x = @as(i64, @intCast(base.x)) + dx;
    const y = @as(i64, @intCast(base.y)) + dy;
    return loc.Loc.init(
        @intCast(if (x < 0) 0 else x),
        @intCast(if (y < 0) 0 else y),
    );
}

pub const MonsterSpawn = struct {
    kind: monsters.Kind,
    name: []const u8,
    position: loc.Loc,
};

pub const MonsterPlan = struct {
    spawns: [4]MonsterSpawn,
    count: usize,
};

pub fn planMonsterSpawns(world_seed: u64, floor_index: u32, spawn: loc.Loc) MonsterPlan {
    var floor_rng = floorRng(world_seed, floor_index);
    _ = floor_rng.nextU8();
    _ = floor_rng.nextU8();

    var list: [4]MonsterSpawn = undefined;
    var count: usize = 0;

    const goblin_count = 1 + (floor_rng.nextU8() % 2);
    var g: u8 = 0;
    while (g < goblin_count and count < list.len) : (g += 1) {
        const offset_x: i64 = @intCast((floor_rng.nextU8() % 3) + 1);
        const offset_y: i64 = @as(i64, @intCast(floor_rng.nextU8() % 3)) - 1;
        list[count] = .{
            .kind = .goblin,
            .name = switch (count) {
                0 => "goblin_0",
                1 => "goblin_1",
                else => "goblin_2",
            },
            .position = offsetLoc(spawn, offset_x, offset_y),
        };
        count += 1;
    }

    if ((floor_rng.nextU8() % 2) == 0 and count < list.len) {
        const offset_x: i64 = -@as(i64, @intCast((floor_rng.nextU8() % 2) + 1));
        const offset_y: i64 = @intCast(floor_rng.nextU8() % 2);
        list[count] = .{
            .kind = .skeleton,
            .name = "skeleton_0",
            .position = offsetLoc(spawn, offset_x, offset_y),
        };
        count += 1;
    }

    return .{ .spawns = list, .count = count };
}

pub const LootSpawn = struct {
    item: items.Id,
    position: loc.Loc,
};

pub const LootPlan = struct {
    spawns: [4]LootSpawn,
    count: usize,
};

pub fn planFloorLoot(
    world_seed: u64,
    floor_index: u32,
    spawn: loc.Loc,
    map: *const terrain.TerrainMap,
) LootPlan {
    var floor_rng = floorRng(world_seed, floor_index);
    _ = floor_rng.nextU8();
    _ = floor_rng.nextU8();
    _ = floor_rng.nextU8();

    var list: [4]LootSpawn = undefined;
    var count: usize = 0;
    const candidates = [_]items.Id{ .bandage, .antidote, .leather_armour };
    var c: usize = 0;
    while (c < candidates.len and count < list.len) : (c += 1) {
        const offset_x: i64 = @intCast((floor_rng.nextU8() % 4) + 1);
        const offset_y: i64 = @as(i64, @intCast(floor_rng.nextU8() % 4)) - 2;
        const pos = offsetLoc(spawn, offset_x, offset_y);
        if (!map.isWalkable(pos)) continue;
        list[count] = .{ .item = candidates[c], .position = pos };
        count += 1;
    }
    return .{ .spawns = list, .count = count };
}

test "floor1 blocks north of spawn" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    try loadFloor1(&map, .v09);
    try std.testing.expect(!map.isWalkable(loc.Loc.init(48, 49)));
    try std.testing.expect(map.isWalkable(loc.Loc.init(49, 49)));
    try std.testing.expect(map.isWalkable(floor1_stairs_v09));
}

test "floor1 v08 blocks east corridor to door" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    try loadFloor1(&map, .v08);
    try std.testing.expect(!map.isWalkable(loc.Loc.init(49, 51)));
}

test "floor1 v09 stairs reachable from spawn via south-east exit" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    try loadFloor1(&map, .v09);
    try std.testing.expect(!map.isWalkable(loc.Loc.init(49, 51)));

    const path = [_]loc.Loc{
        loc.Loc.init(49, 50),
        loc.Loc.init(50, 50),
        floor1_stairs_v09,
    };
    for (path) |tile| try std.testing.expect(map.isWalkable(tile));

    const stairs_tile = map.get(floor1_stairs_v09) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(terrain.Tile.stairs, stairs_tile);
}

test "generated floor is deterministic for same seed" {
    const allocator = std.testing.allocator;
    var a = terrain.TerrainMap.init(allocator);
    defer a.deinit();
    var b = terrain.TerrainMap.init(allocator);
    defer b.deinit();

    const ga = try generateFloor(&a, 42, 2);
    const gb = try generateFloor(&b, 42, 2);
    try std.testing.expectEqual(ga.walkable_count, gb.walkable_count);
    try std.testing.expectEqual(ga.layout_hash, gb.layout_hash);
    try std.testing.expectEqual(ga.spawn.x, gb.spawn.x);
    try std.testing.expectEqual(ga.spawn.y, gb.spawn.y);
    @import("evidence_format.zig").printLayoutEvidence(42, 2, ga);
}

test "generated floor differs across floor index" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();

    const f2 = try generateFloor(&map, 99, 2);
    const f3 = try generateFloor(&map, 99, 3);
    try std.testing.expect(f2.layout_hash != f3.layout_hash or f2.walkable_count != f3.walkable_count);
}

test "monster spawn plan is deterministic" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    const gen = try generateFloor(&map, 42, 2);

    const a = planMonsterSpawns(42, 2, gen.spawn);
    const b = planMonsterSpawns(42, 2, gen.spawn);
    try std.testing.expectEqual(a.count, b.count);
    try std.testing.expectEqualStrings(a.spawns[0].name, b.spawns[0].name);
    try std.testing.expectEqual(a.spawns[0].position.x, b.spawns[0].position.x);
}