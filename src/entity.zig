const std = @import("std");
const types = @import("types.zig");
const loc = @import("loc.zig");

pub const EntityId = u32;
pub const invalid_id: EntityId = std.math.maxInt(EntityId);

pub const Entity = struct {
    id: EntityId,
    name: []u8,
    loc: loc.Loc,
    movement: u8 = 30,
    char: *types.Character,
    conditions: types.ConditionSet,
};

pub const EntityStore = struct {
    entities: std.ArrayList(Entity),

    pub fn init() EntityStore {
        return .{ .entities = .empty };
    }

    pub fn deinit(self: *EntityStore, allocator: std.mem.Allocator) void {
        for (self.entities.items) |*ent| {
            allocator.free(ent.name);
        }
        self.entities.deinit(allocator);
    }

    pub fn create(
        self: *EntityStore,
        allocator: std.mem.Allocator,
        id: EntityId,
        name: []const u8,
        position: loc.Loc,
        character: *types.Character,
    ) !EntityId {
        const owned = try allocator.alloc(u8, name.len);
        @memcpy(owned, name);
        try self.entities.append(allocator, .{
            .id = id,
            .name = owned,
            .loc = position,
            .char = character,
            .conditions = types.ConditionSet.initEmpty(),
        });
        return id;
    }

    pub fn get(self: *EntityStore, id: EntityId) ?*Entity {
        for (self.entities.items) |*ent| {
            if (ent.id == id) return ent;
        }
        return null;
    }

    pub fn count(self: *const EntityStore) usize {
        return self.entities.items.len;
    }
};