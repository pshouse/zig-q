//! Central registry for entity conditions and exhaustion.
const std = @import("std");
const types = @import("types.zig");
const entity = @import("entity.zig");

pub fn apply(ent: *entity.Entity, cond: types.Condition) void {
    ent.conditions.add(cond);
}

pub fn remove(ent: *entity.Entity, cond: types.Condition) void {
    ent.conditions.flags.remove(cond);
}

pub fn has(ent: *const entity.Entity, cond: types.Condition) bool {
    return ent.conditions.has(cond);
}

pub fn setExhaustion(ent: *entity.Entity, level: u3) void {
    ent.exhaustion_level = level;
    if (level > 0) {
        ent.conditions.add(.exhaustion);
    } else {
        ent.conditions.flags.remove(.exhaustion);
    }
}

pub fn exhaustionLevel(ent: *const entity.Entity) u3 {
    return ent.exhaustion_level;
}

pub fn isDead(ent: *const entity.Entity) bool {
    return has(ent, .dead) or ent.current_hp == 0;
}

pub fn markDead(ent: *entity.Entity) void {
    ent.current_hp = 0;
    apply(ent, .dead);
}

pub fn blocksLook(ent: *const entity.Entity) bool {
    return has(ent, .blinded);
}

pub fn blocksMove(ent: *const entity.Entity) bool {
    return has(ent, .restrained) or has(ent, .grappled) or has(ent, .incapacitated) or
        has(ent, .stunned) or has(ent, .unconscious) or has(ent, .paralyzed);
}

pub fn blocksAttack(ent: *const entity.Entity) bool {
    return has(ent, .incapacitated) or has(ent, .stunned) or has(ent, .unconscious) or
        has(ent, .paralyzed) or isDead(ent);
}

pub fn attackDisadvantage(attacker: *const entity.Entity) bool {
    return has(attacker, .blinded) or has(attacker, .prone) or has(attacker, .frightened) or
        has(attacker, .poisoned) or has(attacker, .starving) or exhaustionLevel(attacker) >= 3;
}

pub fn attackAdvantageVs(target: *const entity.Entity) i32 {
    if (has(target, .prone)) return 2;
    return 0;
}

pub fn hasActive(ent: *const entity.Entity) bool {
    if (exhaustionLevel(ent) > 0) return true;
    inline for (std.meta.fields(types.Condition)) |field| {
        const cond = @field(types.Condition, field.name);
        if (has(ent, cond)) return true;
    }
    return false;
}

pub fn formatList(ent: *const entity.Entity, writer: anytype) !void {
    var first = true;
    inline for (std.meta.fields(types.Condition)) |field| {
        const cond = @field(types.Condition, field.name);
        if (has(ent, cond)) {
            if (!first) try writer.writeAll(", ");
            try writer.writeAll(field.name);
            first = false;
        }
    }
    if (exhaustionLevel(ent) > 0) {
        if (!first) try writer.writeAll(", ");
        try writer.print("exhaustion={}", .{exhaustionLevel(ent)});
    }
    if (first) try writer.writeAll("none");
}

pub fn toBits(ent: *const entity.Entity) u32 {
    var bits: u32 = 0;
    inline for (std.meta.fields(types.Condition)) |field| {
        const cond = @field(types.Condition, field.name);
        if (has(ent, cond)) bits |= @as(u32, 1) << @intFromEnum(cond);
    }
    return bits;
}

pub fn fromBits(bits: u32) types.ConditionSet {
    var set = types.ConditionSet.initEmpty();
    inline for (std.meta.fields(types.Condition)) |field| {
        const cond = @field(types.Condition, field.name);
        if ((bits & (@as(u32, 1) << @intFromEnum(cond))) != 0) set.add(cond);
    }
    return set;
}

test "apply remove roundtrip" {
    var ent: entity.Entity = undefined;
    ent.conditions = types.ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 10;
    apply(&ent, .poisoned);
    try std.testing.expect(has(&ent, .poisoned));
    remove(&ent, .poisoned);
    try std.testing.expect(!has(&ent, .poisoned));
}

test "exhaustion level sets flag" {
    var ent: entity.Entity = undefined;
    ent.conditions = types.ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 10;
    setExhaustion(&ent, 2);
    try std.testing.expectEqual(@as(u3, 2), exhaustionLevel(&ent));
    try std.testing.expect(has(&ent, .exhaustion));
}