//! Hunger, fatigue, and exhaustion progression on the action clock (mundane only).
const std = @import("std");
const entity = @import("entity.zig");
const world = @import("world.zig");
const conditions = @import("conditions.zig");
const items = @import("items.zig");

/// Peak hunger (starving). Zero means sated.
pub const hunger_max: u16 = 100;
pub const fatigue_max: u16 = 100;

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

fn starvationExhaustion(hunger: u16) u3 {
    if (hunger >= hunger_max) return 3;
    if (hunger >= 90) return 2;
    if (hunger >= 75) return 1;
    return 0;
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
    const from_hunger = starvationExhaustion(ent.hunger);
    const from_fatigue = fatigueExhaustion(ent.fatigue);
    var level: u32 = @max(from_hunger, from_fatigue);
    // Prolonged starvation at peak hunger escalates toward level 6.
    if (ent.hunger >= hunger_max) {
        level +%= @min(@as(u32, ent.fatigue) / 30, 3);
    }
    return @intCast(@min(level, 6));
}

pub fn syncExhaustion(ent: *entity.Entity) void {
    const level = computeExhaustion(ent);
    conditions.setExhaustion(ent, level);
    if (level >= 5) {
        conditions.apply(ent, .unconscious);
    } else if (!ent.sleeping) {
        conditions.remove(ent, .unconscious);
    }
}

pub fn onTick(w: *world.World, ent: *entity.Entity) void {
    if (conditions.isDead(ent)) return;

    if (ent.hunger < hunger_max) ent.hunger += 1;
    if (ent.fatigue < fatigue_max) ent.fatigue += 1;

    if (conditions.has(ent, .poisoned) and ent.current_hp > 0) {
        ent.current_hp -= 1;
        if (ent.current_hp == 0) {
            if (w.combat) |c| {
                if (ent.id == c.player_id) w.markPlayerDead(ent.id);
            }
            conditions.markDead(ent);
        }
    }

    syncExhaustion(ent);
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
    syncExhaustion(ent);
    return true;
}

pub fn formatMeters(ent: *const entity.Entity, writer: anytype) !void {
    try writer.print("hunger={} fatigue={} exhaustion={}", .{
        ent.hunger,
        ent.fatigue,
        conditions.exhaustionLevel(ent),
    });
}

test "starvation raises exhaustion" {
    var ent: entity.Entity = undefined;
    ent.conditions = @import("types.zig").ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 10;
    ent.max_hp = 10;
    ent.hunger = hunger_max;
    ent.fatigue = 0;
    ent.sleeping = false;
    syncExhaustion(&ent);
    try std.testing.expectEqual(@as(u3, 3), conditions.exhaustionLevel(&ent));
}

test "prolonged starvation reaches exhaustion 6" {
    var ent: entity.Entity = undefined;
    ent.conditions = @import("types.zig").ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 10;
    ent.max_hp = 10;
    ent.hunger = hunger_max;
    ent.fatigue = 90;
    ent.sleeping = false;
    syncExhaustion(&ent);
    try std.testing.expectEqual(@as(u3, 6), conditions.exhaustionLevel(&ent));
}

test "food reduces hunger" {
    var hunger: u16 = 60;
    const restore = items.def(.rations).food_restore;
    if (hunger <= restore) hunger = 0 else hunger -= restore;
    try std.testing.expectEqual(@as(u16, 10), hunger);
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