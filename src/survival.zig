//! Hunger, fatigue, and exhaustion progression on the action clock (mundane only).
const std = @import("std");
const entity = @import("entity.zig");
const world = @import("world.zig");
const conditions = @import("conditions.zig");
const items = @import("items.zig");

/// Peak hunger (starving). Zero means sated.
pub const hunger_max: u16 = 100;
pub const fatigue_max: u16 = 100;

/// Hunger at or above this threshold applies the starving condition.
pub const starving_threshold: u16 = 75;

pub const rest_ticks: u32 = 6;
pub const sleep_ticks: u32 = 24;

pub const hunger_restore_food: u16 = 50;
pub const fatigue_restore_rest: u16 = 30;

pub fn initEntity(ent: *entity.Entity) void {
    ent.hunger = 0;
    ent.fatigue = 0;
}

pub fn effectiveMaxHp(ent: *const entity.Entity) u32 {
    var max = ent.max_hp;
    if (conditions.exhaustionLevel(ent) >= 4) {
        max = @max(max / 2, 1);
    }
    return max;
}

pub fn isStarving(hunger: u16) bool {
    return hunger >= starving_threshold;
}

fn fatigueExhaustion(fatigue: u16) u3 {
    if (fatigue < 20) return 0;
    if (fatigue < 40) return 1;
    if (fatigue < 55) return 2;
    if (fatigue < 70) return 3;
    if (fatigue < 85) return 4;
    if (fatigue < 95) return 5;
    return 6;
}

pub fn computeExhaustion(ent: *const entity.Entity) u3 {
    return fatigueExhaustion(ent.fatigue);
}

pub const ExhaustionChange = struct {
    before: u3,
    after: u3,
};

pub const StarvingChange = struct {
    before: bool,
    after: bool,
};

pub const SurvivalChange = struct {
    exhaustion: ExhaustionChange,
    starving: StarvingChange,
};

pub fn syncStarving(ent: *entity.Entity) StarvingChange {
    const before = conditions.has(ent, .starving);
    if (isStarving(ent.hunger)) {
        conditions.apply(ent, .starving);
    } else {
        conditions.remove(ent, .starving);
    }
    return .{ .before = before, .after = conditions.has(ent, .starving) };
}

pub fn syncExhaustion(ent: *entity.Entity) ExhaustionChange {
    const before = conditions.exhaustionLevel(ent);
    const level = computeExhaustion(ent);
    conditions.setExhaustion(ent, level);
    if (level >= 5) {
        conditions.apply(ent, .unconscious);
    } else if (!ent.sleeping) {
        conditions.remove(ent, .unconscious);
    }
    return .{ .before = before, .after = level };
}

pub fn syncSurvival(ent: *entity.Entity) SurvivalChange {
    const starving = syncStarving(ent);
    const exhaustion = syncExhaustion(ent);
    return .{ .exhaustion = exhaustion, .starving = starving };
}

pub fn exhaustionEffectHint(level: u3) ?[]const u8 {
    return switch (level) {
        1, 2 => "getting tired",
        3 => "disadvantage on attacks; movement -1",
        4 => "HP max halved",
        5, 6 => "risk of collapse",
        else => null,
    };
}

pub fn printExhaustionNotice(before: u3, after: u3, writer: anytype) !void {
    if (after > before) {
        var level: u32 = @as(u32, before) + 1;
        while (level <= after) : (level += 1) {
            const lvl: u3 = @intCast(level);
            try writer.print("exhaustion level {}", .{lvl});
            if (exhaustionEffectHint(lvl)) |hint| try writer.print(" ({s})", .{hint});
            try writer.writeAll("\n");
        }
    } else if (after < before) {
        if (after == 0) {
            try writer.print("exhaustion cleared\n", .{});
        } else {
            try writer.print("exhaustion eased to level {}", .{after});
            if (exhaustionEffectHint(after)) |hint| try writer.print(" ({s})", .{hint});
            try writer.writeAll("\n");
        }
    }
}

pub fn printStarvingNotice(before: bool, after: bool, writer: anytype) !void {
    if (!before and after) {
        try writer.print("you are starving (losing HP each tick)\n", .{});
    } else if (before and !after) {
        try writer.print("no longer starving\n", .{});
    }
}

pub fn printSurvivalNotices(change: SurvivalChange, writer: anytype) !void {
    try printExhaustionNotice(change.exhaustion.before, change.exhaustion.after, writer);
    try printStarvingNotice(change.starving.before, change.starving.after, writer);
}

fn applyHpDot(w: *world.World, ent: *entity.Entity, amount: u32) void {
    if (ent.current_hp == 0) return;
    ent.current_hp -|= amount;
    if (ent.current_hp == 0) {
        if (w.combat) |c| {
            if (ent.id == c.player_id) w.markPlayerDead(ent.id);
        }
        conditions.markDead(ent);
    }
}

pub fn onTick(w: *world.World, ent: *entity.Entity) void {
    if (conditions.isDead(ent)) return;

    if (ent.hunger < hunger_max) ent.hunger += 1;
    if (ent.fatigue < fatigue_max) ent.fatigue += 1;

    _ = syncStarving(ent);

    if (conditions.has(ent, .poisoned)) applyHpDot(w, ent, 1);
    if (conditions.has(ent, .starving)) applyHpDot(w, ent, 1);

    _ = syncExhaustion(ent);
    clampHpToEffectiveMax(ent);

    if (conditions.exhaustionLevel(ent) >= 6) {
        if (w.combat) |c| {
            if (ent.id == c.player_id) w.markPlayerDead(ent.id);
        }
        conditions.markDead(ent);
    }
}

fn clampHpToEffectiveMax(ent: *entity.Entity) void {
    const cap = effectiveMaxHp(ent);
    if (ent.current_hp > cap) ent.current_hp = cap;
}

pub fn eatFood(ent: *entity.Entity, id: items.Id) bool {
    const d = items.def(id);
    if (d.category != .consumable or !d.is_food) return false;
    if (ent.hunger <= d.food_restore) {
        ent.hunger = 0;
    } else {
        ent.hunger -= d.food_restore;
    }
    _ = syncSurvival(ent);
    return true;
}

pub fn formatMeters(ent: *const entity.Entity, writer: anytype) !void {
    try writer.print("hunger={} fatigue={} exhaustion={}", .{
        ent.hunger,
        ent.fatigue,
        conditions.exhaustionLevel(ent),
    });
}

test "starvation applies starving condition" {
    var ent: entity.Entity = undefined;
    ent.conditions = @import("types.zig").ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 10;
    ent.max_hp = 10;
    ent.hunger = hunger_max;
    ent.fatigue = 0;
    ent.sleeping = false;
    _ = syncStarving(&ent);
    try std.testing.expect(conditions.has(&ent, .starving));
    try std.testing.expectEqual(@as(u3, 0), conditions.exhaustionLevel(&ent));
}

test "eating clears starving" {
    var ent: entity.Entity = undefined;
    ent.conditions = @import("types.zig").ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 10;
    ent.max_hp = 10;
    ent.hunger = 80;
    ent.fatigue = 0;
    ent.sleeping = false;
    _ = syncStarving(&ent);
    try std.testing.expect(conditions.has(&ent, .starving));
    ent.hunger = 0;
    _ = syncStarving(&ent);
    try std.testing.expect(!conditions.has(&ent, .starving));
}

test "high fatigue reaches exhaustion 6" {
    var ent: entity.Entity = undefined;
    ent.conditions = @import("types.zig").ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 10;
    ent.max_hp = 10;
    ent.hunger = 0;
    ent.fatigue = 100;
    ent.sleeping = false;
    _ = syncExhaustion(&ent);
    try std.testing.expectEqual(@as(u3, 6), conditions.exhaustionLevel(&ent));
}

test "starving deals hp damage each tick" {
    var ent: entity.Entity = undefined;
    ent.conditions = @import("types.zig").ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 10;
    ent.max_hp = 10;
    ent.hunger = hunger_max;
    ent.fatigue = 0;
    ent.sleeping = false;
    var w: world.World = undefined;
    w.combat = null;
    onTick(&w, &ent);
    try std.testing.expectEqual(@as(u32, 9), ent.current_hp);
    try std.testing.expect(conditions.has(&ent, .starving));
}

test "food reduces hunger" {
    var hunger: u16 = 60;
    const restore = items.def(.rations).food_restore;
    if (hunger <= restore) hunger = 0 else hunger -= restore;
    try std.testing.expectEqual(@as(u16, 10), hunger);
}

test "exhaustion notice on level increase" {
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try printExhaustionNotice(0, 1, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "exhaustion level 1") != null);
}

test "exhaustion notice reports each crossed level" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try printExhaustionNotice(0, 3, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "exhaustion level 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "exhaustion level 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "exhaustion level 3") != null);
}

test "starving notice on apply and clear" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try printStarvingNotice(false, true, fbs.writer());
    try printStarvingNotice(true, false, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "you are starving") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "no longer starving") != null);
}

test "ticks increase hunger" {
    var ent: entity.Entity = undefined;
    ent.conditions = @import("types.zig").ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 10;
    ent.max_hp = 10;
    ent.hunger = 0;
    ent.fatigue = 0;
    ent.sleeping = false;
    var w: world.World = undefined;
    w.combat = null;
    onTick(&w, &ent);
    try std.testing.expectEqual(@as(u16, 1), ent.hunger);
}