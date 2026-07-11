//! Player inventory, equipment, and encumbrance.
const std = @import("std");
const items = @import("items.zig");
const entity = @import("entity.zig");
const character = @import("character.zig");
const conditions = @import("conditions.zig");
const types = @import("types.zig");

pub const Stack = struct {
    id: items.Id,
    count: u8 = 1,
};

/// The three equipment slots a bag item can occupy. Equipped gear stays in the
/// bag; the slot merely marks which stack is worn/wielded.
pub const Slot = enum { weapon, armour, shield };

pub fn slotLabel(slot: Slot) []const u8 {
    return switch (slot) {
        .weapon => "weapon",
        .armour => "armour",
        .shield => "shield",
    };
}

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

    /// Binary encumbrance model (#36): weight > cap hard-blocks movement.
    /// Graduated 10/20 speed bands were dead code (blocksMove fired first).
    pub fn encumbrancePenalty(self: *const State, ent: *const entity.Entity) i32 {
        _ = self;
        _ = ent;
        return 0;
    }

    pub fn isOverloaded(self: *const State, ent: *const entity.Entity) bool {
        // Alias of blocksMove under the binary model (was unreachable >2*cap tier).
        return self.blocksMove(ent);
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

    /// Clear any equipment slot (weapon/armour/shield) currently referencing `id`.
    /// Returns true if a slot was cleared. Call this when an item leaves the bag so
    /// combat stats (weaponDamageDie, playerAc) fall back to defaults instead of
    /// keeping a "phantom" reference to gear the player no longer holds.
    pub fn unequip(self: *State, id: items.Id) bool {
        var cleared = false;
        if (self.weapon == id) {
            self.weapon = null;
            cleared = true;
        }
        if (self.armour == id) {
            self.armour = null;
            cleared = true;
        }
        if (self.shield == id) {
            self.shield = null;
            cleared = true;
        }
        return cleared;
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

    pub fn effectiveMovement(self: *const State, ent: *const entity.Entity) u8 {
        var speed = ent.movement;
        const penalty = self.encumbrancePenalty(ent);
        if (penalty >= speed) return 1;
        speed -%= @intCast(penalty);
        // Display: exhaustion tier 3+ movement −1. Real extra move ticks live in
        // `movement.moveEntity` (tier ≥ 3 always; tiers 1–2 on floor ≥ 4 only).
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
        // Shield AC only with class proficiency (fighter exclusive from Phase 1).
        if (self.shield) |sid| {
            if (classProficient(ent, sid)) {
                ac +%= items.def(sid).ac_bonus;
            }
        }
        // Class specials (combat-transient): guard +2, reckless −4.
        if (ent.guarding) ac +%= 2;
        if (ent.reckless) {
            if (ac > 4) ac -= 4 else ac = 0;
        }
        return ac;
    }

    /// The entity's unarmed/martial damage die: the innate die seeded at spawn
    /// (`initEntityCombat` sets it to the class hit_die), falling back to the
    /// class hit_die if unset (e.g. before combat init).
    pub fn baselineDamageDie(ent: *const entity.Entity) u8 {
        if (ent.damage_die > 0) return ent.damage_die;
        return ent.char.class.hit_die;
    }

    /// Effective melee damage die. A wielded weapon can only *upgrade* damage:
    /// the innate martial baseline (e.g. barbarian d12) stands unless the weapon
    /// beats it, so looting a weaker weapon (short sword d6) never silently cuts a
    /// melee class's damage. A weapon still contributes its trait regardless.
    pub fn weaponDamageDie(self: *const State, ent: *const entity.Entity) u8 {
        const baseline = baselineDamageDie(ent);
        if (self.weapon) |wid| return @max(items.def(wid).damage_die, baseline);
        return baseline;
    }

    /// Item currently occupying `slot`, or null if the slot is empty.
    pub fn equippedIn(self: *const State, slot: Slot) ?items.Id {
        return switch (slot) {
            .weapon => self.weapon,
            .armour => self.armour,
            .shield => self.shield,
        };
    }

    /// Which slot, if any, currently holds `id`.
    pub fn slotOf(self: *const State, id: items.Id) ?Slot {
        if (self.weapon == id) return .weapon;
        if (self.armour == id) return .armour;
        if (self.shield == id) return .shield;
        return null;
    }

    /// Clears `slot` and returns the item that occupied it (null if empty).
    pub fn clearSlot(self: *State, slot: Slot) ?items.Id {
        const prev = self.equippedIn(slot);
        switch (slot) {
            .weapon => self.weapon = null,
            .armour => self.armour = null,
            .shield => self.shield = null,
        }
        return prev;
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
    // #30: clear phantom equipment slots whose id is not in the bag (pre-fix
    // saves / corrupt rows). Prevents weaponDamageDie/playerAc honoring ghost
    // gear and unequip's old re-add guard from duplicating it back into the bag.
    if (state.weapon) |id| {
        if (!state.has(id)) _ = state.unequip(id);
    }
    if (state.armour) |id| {
        if (!state.has(id)) _ = state.unequip(id);
    }
    if (state.shield) |id| {
        if (!state.has(id)) _ = state.unequip(id);
    }
    return state;
}

test "total weight sums stacks" {
    var state = State.init();
    defer state.deinit(std.testing.allocator);
    try state.add(std.testing.allocator, .leather_armour, 3);
    try std.testing.expectEqual(@as(u32, 30), state.totalWeight());
}

test "unequip clears matching slots and reports whether it did" {
    var state = State.init();
    defer state.deinit(std.testing.allocator);
    state.weapon = .short_sword;
    state.armour = .leather_armour;
    try std.testing.expect(state.unequip(.short_sword));
    try std.testing.expect(state.weapon == null);
    try std.testing.expectEqual(.leather_armour, state.armour.?);
    // Nothing references a bare hand any more, so no slot changes.
    try std.testing.expect(!state.unequip(.short_sword));
}

test "resolve bag item by category" {
    var state = State.init();
    defer state.deinit(std.testing.allocator);
    try state.add(std.testing.allocator, .leather_armour, 1);
    try std.testing.expectEqual(.leather_armour, state.resolveBagItem("armour").found);
    try std.testing.expectEqual(.leather_armour, state.resolveBagItem("armor").found);
    try std.testing.expect(state.resolveBagItem("weapon") == .none_in_category);
}

test "fromSave clears phantom equipment slots absent from the bag" {
    // #30: equipped id not in bag → slot cleared, no phantom combat bonus.
    const allocator = std.testing.allocator;
    const save = GearSave{
        .bag = &.{}, // empty bag
        .weapon = .short_sword,
        .armour = .leather_armour,
        .shield = null,
    };
    var state = try fromSave(allocator, save);
    defer state.deinit(allocator);
    try std.testing.expect(state.weapon == null);
    try std.testing.expect(state.armour == null);
    try std.testing.expect(!state.has(.short_sword));
    try std.testing.expect(!state.has(.leather_armour));
}

test "fromSave keeps slots whose id is still in the bag" {
    const allocator = std.testing.allocator;
    var bag = [_]ItemSave{.{ .id = .short_sword, .count = 1 }};
    const save = GearSave{
        .bag = bag[0..],
        .weapon = .short_sword,
        .armour = null,
        .shield = null,
    };
    var state = try fromSave(allocator, save);
    defer state.deinit(allocator);
    try std.testing.expectEqual(.short_sword, state.weapon.?);
    try std.testing.expect(state.has(.short_sword));
}

test "clearSlot returns the item and leaves it in the bag" {
    var state = State.init();
    defer state.deinit(std.testing.allocator);
    try state.add(std.testing.allocator, .short_sword, 1);
    state.weapon = .short_sword;
    try std.testing.expectEqual(Slot.weapon, state.slotOf(.short_sword).?);

    try std.testing.expectEqual(.short_sword, state.clearSlot(.weapon).?);
    try std.testing.expect(state.weapon == null);
    // Equipped gear never left the bag, so it is still carried after unequip.
    try std.testing.expect(state.has(.short_sword));
    // Clearing an already-empty slot yields null.
    try std.testing.expect(state.clearSlot(.weapon) == null);
}

test "weapon damage die only ever upgrades the innate baseline" {
    var char = types.Character{
        .name = "George",
        .attributes = .empty,
        .race = .{ .name = "dwarf", .speed = 25, .attr_bonuses = .empty },
        .class = .{ .name = "barbarian", .hit_die = 12 },
    };
    var ent: entity.Entity = undefined;
    ent.char = &char;
    ent.damage_die = 12; // innate d12, as initEntityCombat seeds a barbarian

    var state = State.init();
    defer state.deinit(std.testing.allocator);

    // Bare-fisted barbarian rolls its innate d12.
    try std.testing.expectEqual(@as(u8, 12), state.weaponDamageDie(&ent));

    // Looting and equipping the weaker short sword (d6) must NOT cut damage to d6.
    state.weapon = .short_sword;
    try std.testing.expectEqual(@as(u8, 12), state.weaponDamageDie(&ent));

    // But a weapon that beats the baseline upgrades the die.
    ent.damage_die = 4;
    try std.testing.expectEqual(@as(u8, 6), state.weaponDamageDie(&ent));

    // With no innate die recorded, the class hit_die is the baseline.
    state.weapon = null;
    ent.damage_die = 0;
    try std.testing.expectEqual(@as(u8, 12), state.weaponDamageDie(&ent));
}
