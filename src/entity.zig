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
    hunger: u16 = 0,
    fatigue: u16 = 0,
    sleeping: bool = false,
    current_hp: u32 = 0,
    max_hp: u32 = 0,
    damage_die: u8 = 0,
    /// Depth-danger bonus tier (0 on floors 1–3; 1–2 on floors 4–5). Player always 0.
    danger_tier: u32 = 0,
    is_monster: bool = false,
    heap_char_name: bool = false,
    inventory: inventory.State = .init(),
    ai_origin: loc.Loc = loc.Loc.init(0, 0),
    ai_patrol_phase: u8 = 0,
    last_move_dir: ?movement.Direction = null,
    /// #35 chase-memory: last player tile seen with LOS; chase continues here
    /// for `chase_memory_turns` explore turns after LOS breaks.
    chase_last_seen: ?loc.Loc = null,
    chase_memory_left: u8 = 0,
    /// Barbarian `reckless` toggle: advantage on attack rolls, −4 AC until next turn.
    /// Combat-transient; not persisted (cleared on combat end / next player turn).
    reckless: bool = false,
    /// Fighter `guard` stance: +2 AC for one round (skips the attack). Combat-transient.
    guarding: bool = false,
    /// Fighter `second wind` once-per-floor self-heal. Reset on descend; not persisted.
    second_wind_used: bool = false,
    /// Last damage-die face after discipline clamp (0 = none). Fuzz/discipline probe only.
    last_damage_face: u8 = 0,
    /// Remaining poison DoT ticks (0 = unset / cleared). CON shortens on apply; not persisted.
    poison_ticks_remaining: u16 = 0,
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
