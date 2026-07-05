const std = @import("std");
const loc = @import("loc.zig");

pub const Tile = enum {
    floor,
    wall,
    door,
    stairs,

    pub fn isWalkable(self: Tile) bool {
        return self == .floor or self == .door or self == .stairs;
    }

    pub fn isDescendTrigger(self: Tile) bool {
        return self == .door or self == .stairs;
    }

    pub fn renderChar(self: Tile) u8 {
        return switch (self) {
            .floor => '.',
            .wall => '#',
            .door => '+',
            .stairs => '>',
        };
    }
};

pub const TerrainMap = struct {
    allocator: std.mem.Allocator,
    tiles: std.AutoHashMap(loc.Loc, Tile),

    pub fn init(allocator: std.mem.Allocator) TerrainMap {
        return .{
            .allocator = allocator,
            .tiles = std.AutoHashMap(loc.Loc, Tile).init(allocator),
        };
    }

    pub fn deinit(self: *TerrainMap) void {
        self.tiles.deinit();
    }

    pub fn clear(self: *TerrainMap) void {
        self.tiles.clearRetainingCapacity();
    }

    pub fn set(self: *TerrainMap, position: loc.Loc, tile: Tile) !void {
        try self.tiles.put(position, tile);
    }

    pub fn get(self: *const TerrainMap, position: loc.Loc) ?Tile {
        return self.tiles.get(position);
    }

    pub fn isWalkable(self: *const TerrainMap, position: loc.Loc) bool {
        const tile = self.get(position) orelse return true;
        return tile.isWalkable();
    }
};