const loc = @import("loc.zig");
const terrain = @import("terrain.zig");

const TileEntry = struct {
    x: u64,
    y: u64,
    tile: terrain.Tile,
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

pub fn loadFloor1(map: *terrain.TerrainMap) !void {
    map.clear();
    for (floor1_tiles) |entry| {
        try map.set(loc.Loc.init(entry.x, entry.y), entry.tile);
    }
}

test "floor1 blocks north of spawn" {
    const allocator = @import("std").testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    try loadFloor1(&map);
    try @import("std").testing.expect(!map.isWalkable(loc.Loc.init(48, 49)));
    try @import("std").testing.expect(map.isWalkable(loc.Loc.init(49, 49)));
    try @import("std").testing.expect(map.isWalkable(loc.Loc.init(49, 53)));
}