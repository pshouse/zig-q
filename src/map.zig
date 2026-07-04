const std = @import("std");
const loc = @import("loc.zig");
const entity = @import("entity.zig");

pub const TileMap = struct {
    allocator: std.mem.Allocator,
    cells: std.AutoHashMap(loc.Loc, std.ArrayList(entity.EntityId)),

    pub fn init(allocator: std.mem.Allocator) TileMap {
        return .{
            .allocator = allocator,
            .cells = std.AutoHashMap(loc.Loc, std.ArrayList(entity.EntityId)).init(allocator),
        };
    }

    pub fn deinit(self: *TileMap) void {
        var it = self.cells.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.cells.deinit();
    }

    pub fn place(self: *TileMap, position: loc.Loc, id: entity.EntityId) !void {
        const gop = try self.cells.getOrPut(position);
        if (!gop.found_existing) {
            gop.value_ptr.* = .empty;
        }
        try gop.value_ptr.append(self.allocator, id);
    }

    pub fn remove(self: *TileMap, position: loc.Loc, id: entity.EntityId) void {
        const list_ptr = self.cells.getPtr(position) orelse return;
        var i: usize = 0;
        while (i < list_ptr.items.len) : (i += 1) {
            if (list_ptr.items[i] == id) {
                _ = list_ptr.orderedRemove(i);
                break;
            }
        }
        if (list_ptr.items.len == 0) {
            list_ptr.deinit(self.allocator);
            _ = self.cells.remove(position);
        }
    }

    pub fn isBlockedFor(self: *const TileMap, position: loc.Loc, exclude_id: entity.EntityId) bool {
        const list = self.cells.get(position) orelse return false;
        for (list.items) |eid| {
            if (eid != exclude_id) return true;
        }
        return false;
    }

    pub fn entityCountAt(self: *const TileMap, position: loc.Loc) usize {
        const list = self.cells.get(position) orelse return 0;
        return list.items.len;
    }

    pub fn occupiedCellCount(self: *const TileMap) usize {
        return self.cells.count();
    }
};