//! Floor objects: corpses, traps, items (persist in save v2).
const std = @import("std");
const loc = @import("loc.zig");
const items = @import("items.zig");

pub const Kind = enum {
    corpse,
    trap,
    item,
};

pub const FloorObject = struct {
    kind: Kind,
    x: u64,
    y: u64,
    label: []const u8,
    item: ?items.Id = null,
};

pub const Store = struct {
    objects: std.ArrayList(FloorObject),

    pub fn init() Store {
        return .{ .objects = .empty };
    }

    pub fn deinit(self: *Store, allocator: std.mem.Allocator) void {
        for (self.objects.items) |obj| allocator.free(obj.label);
        self.objects.deinit(allocator);
    }

    pub fn add(self: *Store, allocator: std.mem.Allocator, kind: Kind, position: loc.Loc, label: []const u8) !void {
        try self.addItem(allocator, kind, position, label, null);
    }

    pub fn addItem(
        self: *Store,
        allocator: std.mem.Allocator,
        kind: Kind,
        position: loc.Loc,
        label: []const u8,
        item: ?items.Id,
    ) !void {
        try self.objects.append(allocator, .{
            .kind = kind,
            .x = position.x,
            .y = position.y,
            .label = try allocator.dupe(u8, label),
            .item = item,
        });
    }

    pub fn at(self: *const Store, position: loc.Loc) ?*FloorObject {
        for (self.objects.items) |*obj| {
            if (obj.x == position.x and obj.y == position.y) return obj;
        }
        return null;
    }

    pub fn blocksTileAt(self: *const Store, position: loc.Loc) bool {
        const obj = self.at(position) orelse return false;
        return obj.kind == .corpse and corpseBlocksTile(obj.label);
    }

    pub fn removeAt(self: *Store, allocator: std.mem.Allocator, position: loc.Loc) void {
        var i: usize = 0;
        while (i < self.objects.items.len) : (i += 1) {
            if (self.objects.items[i].x == position.x and self.objects.items[i].y == position.y) {
                allocator.free(self.objects.items[i].label);
                _ = self.objects.swapRemove(i);
                return;
            }
        }
    }
};

/// Only truly large corpses block movement; humanoids (goblin, skeleton, etc.) can be stepped over.
pub fn corpseBlocksTile(label: []const u8) bool {
    return std.mem.startsWith(u8, label, "dragon");
}

pub const ObjectSave = struct {
    kind: Kind,
    x: u64,
    y: u64,
    label: []const u8,
    item: ?items.Id = null,
};

test "corpse size gates tile blocking" {
    try std.testing.expect(!corpseBlocksTile("goblin_0"));
    try std.testing.expect(!corpseBlocksTile("skeleton_0"));
    try std.testing.expect(corpseBlocksTile("dragon_0"));
}

test "store add and at" {
    const allocator = std.testing.allocator;
    var store = Store.init();
    defer store.deinit(allocator);
    try store.add(allocator, .corpse, loc.Loc.init(50, 49), "goblin_0");
    try std.testing.expect(store.at(loc.Loc.init(50, 49)) != null);
    try std.testing.expect(store.at(loc.Loc.init(49, 49)) == null);
}