//! Player inventory, equipment, and encumbrance.
const std = @import("std");
const items = @import("items.zig");
const entity = @import("entity.zig");
const character = @import("character.zig");
const conditions = @import("conditions.zig");

pub const Stack = struct {
    id: items.Id,
    count: u8 = 1,
};

pub const State = struct {
    bag: std.ArrayList(Stack),
    weapon: ?items.Id = null,
    armour: ?items.Id = null,
    shield: ?items.Id = null,

    pub fn init() State {
        return .{ .bag = .empty };
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        self.bag.deinit(allocator);
    }

    pub fn totalWeight(self: *const State) u32 {
        var total: u32 = 0;
        for (self.bag.items) |stack| {
            total += @as(u32, items.def(stack.id).weight) * stack.count;
        }
        return total;
    }

    pub fn carryCapacity(str: u64) u32 {
        return @intCast(str * 5);
    }

    pub fn encumbrancePenalty(self: *const State, ent: *const entity.Entity) i32 {
        const cap = carryCapacity(character.statByAbbr(ent.char, "STR"));
        const weight = self.totalWeight();
        if (weight <= cap) return 0;
        if (weight <= cap * 2) return 10;
        return 20;
    }

    pub fn isOverloaded(self: *const State, ent: *const entity.Entity) bool {
        const cap = carryCapacity(character.statByAbbr(ent.char, "STR"));
        return self.totalWeight() > cap * 2;
    }

    pub fn blocksMove(self: *const State, ent: *const entity.Entity) bool {
        const cap = carryCapacity(character.statByAbbr(ent.char, "STR"));
        return self.totalWeight() > cap;
    }

    pub fn findStack(self: *State, id: items.Id) ?*Stack {
        for (self.bag.items) |*stack| {
            if (stack.id == id) return stack;
        }
        return null;
    }

    pub fn add(self: *State, allocator: std.mem.Allocator, id: items.Id, count: u8) !void {
        if (findStack(self, id)) |stack| {
            stack.count +%= count;
            return;
        }
        try self.bag.append(allocator, .{ .id = id, .count = count });
    }

    pub fn remove(self: *State, id: items.Id, count: u8) bool {
        if (findStack(self, id)) |stack| {
            if (stack.count < count) return false;
            stack.count -= count;
            if (stack.count == 0) {
                for (self.bag.items, 0..) |*s, i| {
                    if (s.id == id) {
                        _ = self.bag.swapRemove(i);
                        break;
                    }
                }
            }
            return true;
        }
        return false;
    }

    pub fn has(self: *const State, id: items.Id) bool {
        if (findStack(@constCast(self), id)) |stack| return stack.count > 0;
        return false;
    }

    pub const BagResolve = union(enum) {
        found: items.Id,
        unknown,
        none_in_category: items.Category,
        ambiguous: items.Category,
    };

    pub fn resolveBagItem(self: *const State, name: []const u8) BagResolve {
        if (items.parseId(name)) |id| return .{ .found = id };
        if (items.parseCategory(name)) |cat| {
            var single: ?items.Id = null;
            var count: usize = 0;
            for (self.bag.items) |stack| {
                if (stack.count == 0) continue;
                if (items.def(stack.id).category != cat) continue;
                count += 1;
                single = stack.id;
            }
            if (count == 0) return .{ .none_in_category = cat };
            if (count == 1) return .{ .found = single.? };
            return .{ .ambiguous = cat };
        }
        return .unknown;
    }

    pub fn classProficient(ent: *const entity.Entity, id: items.Id) bool {
        const d = items.def(id);
        if (d.proficient_classes.len == 0) return true;
        for (d.proficient_classes) |class_name| {
            if (std.mem.eql(u8, ent.char.class.name, class_name)) return true;
        }
        return false;
    }

    pub fn effectiveMovement(self: *const State, ent: *entity.Entity) u8 {
        var speed = ent.movement;
        const penalty = self.encumbrancePenalty(ent);
        if (penalty >= speed) return 1;
        speed -%= @intCast(penalty);
        if (conditions.exhaustionLevel(ent) >= 3) {
            if (speed > 1) speed -%= 1;
        }
        return @max(speed, 1);
    }

    pub fn playerAc(self: *const State, ent: *const entity.Entity) u32 {
        var ac: u32 = 10;
        if (self.armour) |aid| {
            const d = items.def(aid);
            if (classProficient(ent, aid)) {
                ac = d.ac_bonus;
            }
        }
        const dex_mod = character.abilityModifier(character.statByAbbr(ent.char, "DEX"));
        if (self.armour == null) {
            ac +%= @intCast(@max(dex_mod, 0));
        } else if (self.armour) |aid| {
            const d = items.def(aid);
            if (classProficient(ent, aid) and d.ac_bonus <= 12) {
                ac +%= @intCast(@max(dex_mod, 0));
            }
        }
        if (self.shield) |sid| {
            ac +%= items.def(sid).ac_bonus;
        }
        return ac;
    }

    pub fn weaponDamageDie(self: *const State, ent: *const entity.Entity) u8 {
        if (self.weapon) |wid| return items.def(wid).damage_die;
        if (ent.damage_die > 0) return ent.damage_die;
        return ent.char.class.hit_die;
    }

    pub fn format(self: *const State, writer: anytype) !void {
        try writer.writeAll("inventory:\n");
        if (self.bag.items.len == 0) {
            try writer.writeAll("  (empty)\n");
        } else {
            for (self.bag.items) |stack| {
                const d = items.def(stack.id);
                try writer.print("  {s} x{} weight={}\n", .{ d.name, stack.count, d.weight });
            }
        }
        if (self.weapon) |w| try writer.print("wielding: {s}\n", .{items.def(w).name});
        if (self.armour) |a| try writer.print("wearing: {s}\n", .{items.def(a).name});
        if (self.shield) |s| try writer.print("shield: {s}\n", .{items.def(s).name});
    }
};

pub const ItemSave = struct {
    id: items.Id,
    count: u8,
};

pub const GearSave = struct {
    bag: []ItemSave,
    weapon: ?items.Id = null,
    armour: ?items.Id = null,
    shield: ?items.Id = null,
};

pub fn toSave(allocator: std.mem.Allocator, state: *const State) !GearSave {
    var list: std.ArrayList(ItemSave) = .empty;
    errdefer list.deinit(allocator);
    for (state.bag.items) |stack| {
        try list.append(allocator, .{ .id = stack.id, .count = stack.count });
    }
    return .{
        .bag = try list.toOwnedSlice(allocator),
        .weapon = state.weapon,
        .armour = state.armour,
        .shield = state.shield,
    };
}

pub fn fromSave(allocator: std.mem.Allocator, save: GearSave) !State {
    var state = State.init();
    errdefer state.deinit(allocator);
    for (save.bag) |stack| {
        try state.add(allocator, stack.id, stack.count);
    }
    state.weapon = save.weapon;
    state.armour = save.armour;
    state.shield = save.shield;
    return state;
}

test "total weight sums stacks" {
    var state = State.init();
    defer state.deinit(std.testing.allocator);
    try state.add(std.testing.allocator, .leather_armour, 3);
    try std.testing.expectEqual(@as(u32, 30), state.totalWeight());
}

test "resolve bag item by category" {
    var state = State.init();
    defer state.deinit(std.testing.allocator);
    try state.add(std.testing.allocator, .leather_armour, 1);
    try std.testing.expectEqual(.leather_armour, state.resolveBagItem("armour").found);
    try std.testing.expectEqual(.leather_armour, state.resolveBagItem("armor").found);
    try std.testing.expect(state.resolveBagItem("weapon") == .none_in_category);
}