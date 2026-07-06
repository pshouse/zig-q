const std = @import("std");
const types = @import("types.zig");
const loc = @import("loc.zig");
const inventory = @import("inventory.zig");
const movement = @import("movement.zig");

pub const EntityId = u32;
pub const invalid_id: EntityId = std.math.maxInt(EntityId);

pub const Entity = struct {
    id: EntityId,
    name: []u8,
    loc: loc.Loc,
    movement: u8 = 30,
    char: *types.Character,
    conditions: types.ConditionSet,
    exhaustion_level: u3 = 0,
    hunger: u16 = 100,
    fatigue: u16 = 0,
    sleeping: bool = false,
    current_hp: u32 = 0,
    max_hp: u32 = 0,
    damage_die: u8 = 0,
    is_monster: bool = false,
    heap_char_name: bool = false,
    inventory: inventory.State = .init(),
    ai_origin: loc.Loc = loc.Loc.init(0, 0),
    ai_patrol_phase: u8 = 0,
    last_move_dir: ?movement.Direction = null,
};

pub const EntityStore = struct {
    entities: std.ArrayList(Entity),

    pub fn init() EntityStore {
        return .{ .entities = .empty };
    }

    pub fn deinit(self: *EntityStore, allocator: std.mem.Allocator) void {
        for (self.entities.items) |*ent| {
            if (ent.heap_char_name) allocator.free(ent.char.name);
            ent.char.attributes.deinit(allocator);
            allocator.destroy(ent.char);
            ent.inventory.deinit(allocator);
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

    pub fn get(self: *const EntityStore, id: EntityId) ?*Entity {
        for (self.entities.items) |*ent| {
            if (ent.id == id) return ent;
        }
        return null;
    }

    pub fn count(self: *const EntityStore) usize {
        return self.entities.items.len;
    }

    pub fn remove(self: *EntityStore, allocator: std.mem.Allocator, id: EntityId) void {
        var i: usize = 0;
        while (i < self.entities.items.len) : (i += 1) {
            if (self.entities.items[i].id != id) continue;
            const ent = &self.entities.items[i];
            if (ent.heap_char_name) allocator.free(ent.char.name);
            ent.char.attributes.deinit(allocator);
            allocator.destroy(ent.char);
            ent.inventory.deinit(allocator);
            allocator.free(ent.name);
            _ = self.entities.swapRemove(i);
            return;
        }
    }
};