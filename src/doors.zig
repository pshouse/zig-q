//! Door open/close/locked state (persists in save v2).
const std = @import("std");
const loc = @import("loc.zig");
const terrain = @import("terrain.zig");

pub const State = enum {
    closed,
    open,
    locked,
};

pub const DoorSave = struct {
    x: u64,
    y: u64,
    state: State,
};

pub const Store = struct {
    states: std.AutoHashMap(loc.Loc, State),

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{ .states = std.AutoHashMap(loc.Loc, State).init(allocator) };
    }

    pub fn deinit(self: *Store) void {
        self.states.deinit();
    }

    pub fn clear(self: *Store) void {
        self.states.clearRetainingCapacity();
    }

    pub fn set(self: *Store, position: loc.Loc, state: State) !void {
        try self.states.put(position, state);
    }

    pub fn get(self: *const Store, position: loc.Loc) ?State {
        return self.states.get(position);
    }

    pub fn resolve(self: *const Store, map: *const terrain.TerrainMap, position: loc.Loc) ?State {
        if (self.get(position)) |state| return state;
        if (map.get(position)) |tile| {
            if (tile == .door) return .closed;
        }
        return null;
    }

    pub fn blocks(self: *const Store, position: loc.Loc) bool {
        if (self.get(position)) |state| return state != .open;
        return false;
    }

    pub fn blocksAt(self: *const Store, map: *const terrain.TerrainMap, position: loc.Loc) bool {
        const tile = map.get(position) orelse return false;
        if (tile != .door) return false;
        const state = self.resolve(map, position) orelse .closed;
        return state != .open;
    }
};

test "default door is closed and blocks" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    var store = Store.init(allocator);
    defer store.deinit();
    const at = loc.Loc.init(10, 10);
    try map.set(at, .door);
    try std.testing.expect(store.blocksAt(&map, at));
}