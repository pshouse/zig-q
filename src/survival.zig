//! Hunger, fatigue, and exhaustion progression on the action clock (mundane only).
const std = @import("std");
const entity = @import("entity.zig");
const world = @import("world.zig");
const conditions = @import("conditions.zig");
const items = @import("items.zig");
const character = @import("character.zig");

/// Base poison DoT duration in clock ticks before CON resist is applied.
pub const poison_base_duration: u16 = 10;
/// Floor: CON resist never shortens poison below this many ticks.
pub const poison_duration_floor: u16 = 1;

/// Deterministic poison duration: `max(floor, base − CON mod)`. No RNG draw.
/// High CON shortens the DoT; low CON lengthens it (mod can be negative).
pub fn poisonDuration(ent: *const entity.Entity) u16 {
    const con_mod = character.abilityModifier(character.statByAbbr(ent.char, "CON"));
    const adjusted: i32 = @as(i32, @intCast(poison_base_duration)) - con_mod;
    return @intCast(@max(@as(i32, @intCast(poison_duration_floor)), adjusted));
}

/// Apply the poisoned condition and set CON-scaled duration ticks.
pub fn applyPoison(ent: *entity.Entity) void {
    conditions.apply(ent, .poisoned);
    ent.poison_ticks_remaining = poisonDuration(ent);
}

/// Clear poison condition and remaining DoT ticks (antidote / expiry).
pub fn clearPoison(ent: *entity.Entity) void {
    conditions.remove(ent, .poisoned);
    ent.poison_ticks_remaining = 0;
}

/// Peak hunger (starving). Zero means sated.
pub const hunger_max: u16 = 100;
pub const fatigue_max: u16 = 100;

/// Hunger at or above this threshold applies the starving condition.
pub const starving_threshold: u16 = 75;

pub const rest_ticks: u32 = 6;
pub const sleep_ticks: u32 = 24;

pub const hunger_restore_food: u16 = 50;
pub const fatigue_restore_rest: u16 = 30;
/// Fatigue shed by the in-combat `catch breath` action. Partial, emergency relief:
/// less than a `rest`, and the turn still passes to the enemy, so it is a real tradeoff.
pub const fatigue_restore_catch_breath: u16 = 8;

/// Lowest fatigue a short `rest` can reach. A rest sheds `fatigue_restore_rest`
/// but never crosses below this floor, which sits at the top of exhaustion tier 1
/// (`fatigueExhaustion`): rest keeps you out of the penalty tiers (3+) but can never
/// fully clear exhaustion. Only `sleep` resets fatigue to 0, so sleep — despite its
/// ambush/unconscious risk — is the only route to a pristine, maximum-runway state.
pub const rest_fatigue_floor: u16 = 20;

/// Rations given at spawn so early floors are survivable before loot sources appear.
pub const starter_rations: u8 = 2;
/// One bandage in the starter kit for mundane out-of-combat healing.
pub const starter_bandage: u8 = 1;

pub fn initEntity(ent: *entity.Entity) void {
    ent.hunger = 0;
    ent.fatigue = 0;
}

pub fn giveStarterKit(allocator: std.mem.Allocator, ent: *entity.Entity) !void {
    if (ent.is_monster) return;
    try ent.inventory.add(allocator, .rations, starter_rations);
    try ent.inventory.add(allocator, .bandage, starter_bandage);
}

/// Recovery ceiling while exhausted: at exhaustion 4+ ("HP max halved") healing
/// cannot raise current HP above half max. This is a cap only — crossing into
/// the tier never drains HP the entity already has. It used to: onTick clamped
/// current HP to this value, so `sleep` (the only full fatigue reset, whose 24
/// ticks climb through tier 4 whenever it starts at fatigue >= 46) silently and
/// permanently cost half your HP — the cap recovered on waking, the HP did not.
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

/// Shed `amount` fatigue, clamped so fatigue never drops below `rest_fatigue_floor`
/// and is never *raised* (shedding while already below the floor is a no-op). Every
/// waking recovery action must route through this clamp so no combination of them
/// can reach fatigue 0 — that stays exclusive to `applySleep`.
fn shedFatigueFloored(ent: *entity.Entity, amount: u16) ExhaustionChange {
    const relieved = ent.fatigue -| amount;
    ent.fatigue = @min(ent.fatigue, @max(relieved, rest_fatigue_floor));
    return syncExhaustion(ent);
}

/// Apply a short rest's fatigue relief. Sheds `fatigue_restore_rest` down to the
/// floor: rest can lift you out of the penalty tiers but can never fully clear
/// exhaustion — that requires `applySleep`.
pub fn applyRest(ent: *entity.Entity) ExhaustionChange {
    return shedFatigueFloored(ent, fatigue_restore_rest);
}

/// Apply the in-combat `catch breath` fatigue relief. Sheds
/// `fatigue_restore_catch_breath` with the same floor as `applyRest` — otherwise
/// spamming it against a weak monster would out-recover `sleep` and hollow the
/// rest-vs-sleep distinction.
pub fn applyCatchBreath(ent: *entity.Entity) ExhaustionChange {
    return shedFatigueFloored(ent, fatigue_restore_catch_breath);
}

/// Apply a full sleep's fatigue reset. Sleep is the only action that returns
/// fatigue to 0 and thus fully clears exhaustion (see `rest_fatigue_floor`).
pub fn applySleep(ent: *entity.Entity) ExhaustionChange {
    ent.fatigue = 0;
    return syncExhaustion(ent);
}

pub fn exhaustionEffectHint(level: u3) ?[]const u8 {
    return switch (level) {
        // Tiers 1–2: rest floors at 20; on danger floors (4+) each move costs an extra tick.
        // Tier 3: attack disadvantage + movement −1 (display and extra move tick everywhere).
        1, 2 => "rest cannot fully clear this; deeper floors cost extra move ticks",
        3 => "disadvantage on attacks; movement -1",
        4 => "HP max halved; near collapse — sleep soon (rest cannot fully clear this)",
        // Level 5 is recoverable via sleep (#26); level 6 is death.
        5 => "collapsed — sleep to recover (or die at level 6)",
        6 => "risk of collapse",
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

pub fn printHpDotNotice(before_hp: u32, ent: *const entity.Entity, writer: anytype) !void {
    if (ent.current_hp >= before_hp) return;
    const loss = before_hp - ent.current_hp;
    if (conditions.has(ent, .poisoned) and conditions.has(ent, .starving)) {
        try writer.print("poison and starvation deal {} hp; hp={}/{}\n", .{
            loss, ent.current_hp, ent.max_hp,
        });
    } else if (conditions.has(ent, .poisoned)) {
        try writer.print("poison deals {} hp; hp={}/{}\n", .{
            loss, ent.current_hp, ent.max_hp,
        });
    } else if (conditions.has(ent, .starving)) {
        try writer.print("starvation deals {} hp; hp={}/{}\n", .{
            loss, ent.current_hp, ent.max_hp,
        });
    } else {
        try writer.print("lost {} hp; hp={}/{}\n", .{
            loss, ent.current_hp, ent.max_hp,
        });
    }
}

pub fn printSurvivalNotices(change: SurvivalChange, writer: anytype) !void {
    try printExhaustionNotice(change.exhaustion.before, change.exhaustion.after, writer);
    try printStarvingNotice(change.starving.before, change.starving.after, writer);
}

/// Resolve a survival death (DoT or exhaustion collapse) exactly like a
/// killing blow. Permadeath is authoritative regardless of combat state:
/// starving or succumbing to poison in the open must end the run, or the
/// player lingers as a walking dead actor. A monster mirrors the combat-kill
/// path (combat.performAttack): it drops a corpse and leaves the tile map, so
/// the fuzz DeadMonsterOnMap invariant and the corpse/loot economy hold when
/// a poisoned monster bleeds out on its own — not just when it is slain.
fn resolveDeath(w: *world.World, ent: *entity.Entity) void {
    if (ent.is_monster) {
        w.spawnCorpse(ent.name, ent.loc) catch {};
        w.tile_map.remove(ent.loc, ent.id);
    } else {
        w.markPlayerDead(ent.id);
    }
    conditions.markDead(ent);
}

fn applyHpDot(w: *world.World, ent: *entity.Entity, amount: u32) void {
    if (ent.current_hp == 0) return;
    ent.current_hp -|= amount;
    if (ent.current_hp == 0) resolveDeath(w, ent);
}

/// One poison DoT tick: damage, then decrement duration; clear when spent.
/// Lazy-inits remaining from CON when condition is present but ticks are 0
/// (save/load restores the condition bit but not the transient counter).
fn tickPoisonDot(w: *world.World, ent: *entity.Entity) void {
    if (!conditions.has(ent, .poisoned)) return;
    if (ent.poison_ticks_remaining == 0) {
        ent.poison_ticks_remaining = poisonDuration(ent);
    }
    applyHpDot(w, ent, 1);
    if (conditions.isDead(ent)) return;
    ent.poison_ticks_remaining -|= 1;
    if (ent.poison_ticks_remaining == 0) {
        clearPoison(ent);
    }
}

pub fn onTick(w: *world.World, ent: *entity.Entity) void {
    if (conditions.isDead(ent)) return;

    // Monsters are exempt from survival pressure: hunger and fatigue are
    // player-economy meters, and ticking them here dropped every monster dead
    // of exhaustion ~95 ticks after its floor spawned — corpseless (only the
    // combat kill path drops corpses) and untargetable. Poison DoT still
    // applies, so a trap-poisoned monster bleeds out as before.
    if (ent.is_monster) {
        tickPoisonDot(w, ent);
        return;
    }

    // Hunger still advances while asleep (time passes; you wake hungrier).
    // Fatigue does not: sleep is the full recovery action, and accruing fatigue
    // across the 24 sleep ticks used to drive tier-4 sleepers into tier-6
    // collapse (permadeath) before applySleep could reset the meter (#55).
    if (ent.hunger < hunger_max) ent.hunger += 1;
    if (!ent.sleeping and ent.fatigue < fatigue_max) ent.fatigue += 1;

    _ = syncStarving(ent);

    tickPoisonDot(w, ent);
    if (conditions.has(ent, .starving)) {
        // v1.6 balance: out of combat, starving drains 1 HP every other clock
        // tick (even ticks), doubling the window to reach food or stairs on
        // 2-tick-per-move danger floors. In combat the full 1 HP/tick stays —
        // fighting while starving remains as deadly as before. Clock parity is
        // saved state, so the rate is deterministic across save/load and
        // identical in REPL, DST, and fuzz.
        const dot_tick = w.combat != null or (w.game_clock.ticks % 2 == 0);
        if (dot_tick) applyHpDot(w, ent, 1);
    }

    _ = syncExhaustion(ent);
    // Deliberately no clamp of current HP to effectiveMaxHp here: the tier-4
    // halving caps recovery (see effectiveMaxHp), it does not confiscate HP.
    // HP loss from exhaustion comes only from the tier-6 collapse below.

    // Tier-6 collapse is waking-only. Belt-and-suspenders with the fatigue
    // accrual guard above: a sleeper must never die of exhaustion mid-sleep.
    if (!ent.sleeping and conditions.exhaustionLevel(ent) >= 6) {
        // Collapse from exhaustion ends the run whether or not a fight is in
        // progress. Unreachable for monsters (they exit above) but routed
        // through the same death path in case the exemption ever narrows.
        resolveDeath(w, ent);
    }
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

test "starving deals hp damage on even ticks out of combat" {
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
    w.game_clock = @import("clock.zig").Clock.init(0.0, 120.0, 5.0, 1.0);
    onTick(&w, &ent); // ticks=0: even -> DoT lands
    try std.testing.expectEqual(@as(u32, 9), ent.current_hp);
    try std.testing.expect(conditions.has(&ent, .starving));
    w.game_clock.ticks = 1;
    onTick(&w, &ent); // odd tick out of combat -> no starving DoT
    try std.testing.expectEqual(@as(u32, 9), ent.current_hp);
    w.game_clock.ticks = 2;
    onTick(&w, &ent);
    try std.testing.expectEqual(@as(u32, 8), ent.current_hp);
}

test "starving in combat deals hp damage every tick" {
    var ent: entity.Entity = undefined;
    ent.conditions = @import("types.zig").ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 10;
    ent.max_hp = 10;
    ent.hunger = hunger_max;
    ent.fatigue = 0;
    ent.sleeping = false;
    var w: world.World = undefined;
    var combat_state: @import("combat.zig").CombatState = undefined;
    w.combat = &combat_state; // onTick only null-checks; never dereferences
    w.game_clock = @import("clock.zig").Clock.init(0.0, 120.0, 5.0, 1.0);
    w.game_clock.ticks = 1; // odd tick: out of combat this would be skipped
    onTick(&w, &ent);
    try std.testing.expectEqual(@as(u32, 9), ent.current_hp);
    w.game_clock.ticks = 2;
    onTick(&w, &ent);
    try std.testing.expectEqual(@as(u32, 8), ent.current_hp);
}

test "starvation death outside combat is permadeath" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const id = try w.spawnTestPlayer(@import("loc.zig").Loc.init(49, 49));
    const ent = w.store.get(id).?;
    ent.hunger = hunger_max;
    ent.current_hp = 1;
    // Out-of-combat starving DoT lands on even clock ticks: tick 1 is skipped,
    // tick 2 kills. Two ticks bound the death instead of one (v1.6 half rate).
    w.tickAction(2);
    try std.testing.expect(conditions.isDead(ent));
    try std.testing.expect(w.isPlayerDead());
}

test "exhaustion collapse outside combat is permadeath" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const id = try w.spawnTestPlayer(@import("loc.zig").Loc.init(49, 49));
    const ent = w.store.get(id).?;
    ent.fatigue = fatigue_max;
    w.tick();
    try std.testing.expect(conditions.isDead(ent));
    try std.testing.expectEqual(@as(u32, 0), ent.current_hp);
    try std.testing.expect(w.isPlayerDead());
}

test "monsters are exempt from survival pressure" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const id = try w.spawnMonster(.goblin, @import("loc.zig").Loc.init(50, 49), "goblin_0");
    var i: u32 = 0;
    while (i < 200) : (i += 1) w.tick();
    const ent = w.store.get(id).?;
    try std.testing.expect(!conditions.isDead(ent));
    try std.testing.expectEqual(ent.max_hp, ent.current_hp);
    try std.testing.expectEqual(@as(u16, 0), ent.hunger);
    try std.testing.expectEqual(@as(u16, 0), ent.fatigue);
    try std.testing.expectEqual(@as(u3, 0), conditions.exhaustionLevel(ent));
    try std.testing.expect(!conditions.has(ent, .starving));
}

// Poison DoT deliberately still applies to monsters (the one survival pressure
// they keep): a trap-poisoned monster must bleed out even with the hunger/
// fatigue/exhaustion exemption above.
test "monster survival death does not trigger permadeath" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const id = try w.spawnMonster(.goblin, @import("loc.zig").Loc.init(50, 49), "goblin_0");
    const ent = w.store.get(id).?;
    conditions.apply(ent, .poisoned);
    ent.current_hp = 1;
    w.tick();
    try std.testing.expect(conditions.isDead(ent));
    try std.testing.expect(!w.isPlayerDead());
}

// A DoT death must look exactly like a combat kill: corpse floor object at the
// tile, monster off the tile map (glyph clears, tile stops counting as occupied).
test "monster poison death drops a corpse and frees its tile" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const position = @import("loc.zig").Loc.init(50, 49);
    const id = try w.spawnMonster(.goblin, position, "goblin_0");
    const ent = w.store.get(id).?;
    conditions.apply(ent, .poisoned);
    ent.current_hp = 1;
    w.tick();
    try std.testing.expect(conditions.isDead(ent));
    const corpse = w.floor_objects.at(position) orelse return error.MissingCorpse;
    try std.testing.expectEqual(@import("world_objects.zig").Kind.corpse, corpse.kind);
    try std.testing.expectEqualStrings("goblin_0", corpse.label);
    try std.testing.expectEqual(@as(usize, 0), w.tile_map.entityCountAt(position));
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

test "hp dot notice reports poison damage" {
    var ent: entity.Entity = undefined;
    ent.conditions = @import("types.zig").ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 9;
    ent.max_hp = 13;
    ent.hunger = 0;
    ent.fatigue = 0;
    ent.sleeping = false;
    conditions.apply(&ent, .poisoned);

    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try printHpDotNotice(10, &ent, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "poison deals 1 hp; hp=9/13") != null);
}

test "hp dot notice reports combined poison and starvation" {
    var ent: entity.Entity = undefined;
    ent.conditions = @import("types.zig").ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 8;
    ent.max_hp = 13;
    ent.hunger = hunger_max;
    ent.fatigue = 0;
    ent.sleeping = false;
    conditions.apply(&ent, .poisoned);
    conditions.apply(&ent, .starving);

    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try printHpDotNotice(10, &ent, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "poison and starvation deal 2 hp; hp=8/13") != null);
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

fn testEntity() entity.Entity {
    var ent: entity.Entity = undefined;
    ent.conditions = @import("types.zig").ConditionSet.initEmpty();
    ent.exhaustion_level = 0;
    ent.current_hp = 10;
    ent.max_hp = 10;
    ent.hunger = 0;
    ent.fatigue = 0;
    ent.sleeping = false;
    return ent;
}

test "rest sheds fatigue but floors at rest_fatigue_floor" {
    var ent = testEntity();
    ent.fatigue = 60; // exhaustion tier 3 (penalty tier)
    _ = applyRest(&ent);
    try std.testing.expectEqual(@as(u16, 30), ent.fatigue); // 60 - 30
    _ = applyRest(&ent);
    try std.testing.expectEqual(rest_fatigue_floor, ent.fatigue); // 30 - 30 -> floored at 20
    _ = applyRest(&ent);
    try std.testing.expectEqual(rest_fatigue_floor, ent.fatigue); // already at floor -> unchanged
    // Rest lifts you out of the penalty tiers but never fully clears exhaustion.
    try std.testing.expectEqual(@as(u3, 1), conditions.exhaustionLevel(&ent));
    try std.testing.expect(conditions.has(&ent, .exhaustion));
}

test "rest never raises fatigue that is already below the floor" {
    var ent = testEntity();
    ent.fatigue = 5;
    _ = applyRest(&ent);
    try std.testing.expectEqual(@as(u16, 5), ent.fatigue); // no-op, not raised to 20
    try std.testing.expectEqual(@as(u3, 0), conditions.exhaustionLevel(&ent));
}

test "catch breath sheds fatigue but floors at rest_fatigue_floor" {
    var ent = testEntity();
    ent.fatigue = 60;
    _ = applyCatchBreath(&ent);
    try std.testing.expectEqual(@as(u16, 52), ent.fatigue); // 60 - 8, above the floor
    ent.fatigue = 24;
    _ = applyCatchBreath(&ent);
    try std.testing.expectEqual(rest_fatigue_floor, ent.fatigue); // 24 - 8 -> floored at 20, not 16
    _ = applyCatchBreath(&ent);
    try std.testing.expectEqual(rest_fatigue_floor, ent.fatigue); // already at floor -> unchanged
}

test "catch breath never raises fatigue that is already below the floor" {
    var ent = testEntity();
    ent.fatigue = 10;
    _ = applyCatchBreath(&ent);
    try std.testing.expectEqual(@as(u16, 10), ent.fatigue); // no-op, not raised to 20
    try std.testing.expectEqual(@as(u3, 0), conditions.exhaustionLevel(&ent));
}

test "only sleep resets fatigue to zero and clears exhaustion" {
    var ent = testEntity();
    ent.fatigue = 80;
    // No amount of resting reaches level 0 — it bottoms out at the floor.
    var guard: u8 = 0;
    while (guard < 8) : (guard += 1) _ = applyRest(&ent);
    try std.testing.expectEqual(rest_fatigue_floor, ent.fatigue);
    try std.testing.expect(conditions.has(&ent, .exhaustion));
    // Sleep is the only full reset.
    _ = applySleep(&ent);
    try std.testing.expectEqual(@as(u16, 0), ent.fatigue);
    try std.testing.expectEqual(@as(u3, 0), conditions.exhaustionLevel(&ent));
    try std.testing.expect(!conditions.has(&ent, .exhaustion));
}

test "crossing exhaustion tier 4 halves the recovery cap but drains no hp" {
    var ent = testEntity();
    ent.fatigue = 69; // one tick below tier 4
    var w: world.World = undefined;
    w.combat = null;
    onTick(&w, &ent); // fatigue 70 -> exhaustion 4
    try std.testing.expectEqual(@as(u3, 4), conditions.exhaustionLevel(&ent));
    try std.testing.expectEqual(@as(u32, 5), effectiveMaxHp(&ent)); // cap halved (10 -> 5)...
    try std.testing.expectEqual(@as(u32, 10), ent.current_hp); // ...but current hp intact
}

test "sleeping does not accrue fatigue; applySleep resets and keeps hp" {
    // #55: cmdSleep used to tick 24 times *before* applySleep, and unguarded
    // onTick fatigue accrual climbed 60→84 (and at start ≥71, into tier 6 /
    // permadeath). Sleeping must freeze fatigue so sleep only ever reduces it.
    var ent = testEntity();
    ent.fatigue = 60;
    ent.sleeping = true;
    var w: world.World = undefined;
    w.combat = null;
    var i: u32 = 0;
    while (i < sleep_ticks) : (i += 1) onTick(&w, &ent);
    try std.testing.expectEqual(@as(u16, 60), ent.fatigue); // frozen while asleep
    ent.sleeping = false;
    _ = applySleep(&ent);
    try std.testing.expectEqual(@as(u16, 0), ent.fatigue);
    try std.testing.expectEqual(@as(u3, 0), conditions.exhaustionLevel(&ent));
    try std.testing.expectEqual(@as(u32, 10), ent.current_hp);
    try std.testing.expectEqual(@as(u32, 10), effectiveMaxHp(&ent));
}

test "sleep at high fatigue never collapses into permadeath" {
    // Bracketed lethal boundary under the old unguarded accrual: start ≥71
    // climbed to ≥95 mid-sleep → tier-6 resolveDeath. Sleep at 84 (observed
    // playtest death) and at fatigue_max must both recover cleanly.
    const allocator = std.testing.allocator;
    for ([_]u16{ 71, 84, fatigue_max }) |start_fatigue| {
        var w = try world.World.init(allocator, 42);
        defer w.deinit();
        const id = try w.spawnTestPlayer(@import("loc.zig").Loc.init(49, 49));
        const ent = w.store.get(id).?;
        const hp_before = ent.current_hp;
        ent.fatigue = start_fatigue;
        _ = syncExhaustion(ent);
        ent.sleeping = true;
        var i: u32 = 0;
        while (i < sleep_ticks) : (i += 1) {
            w.tick();
            try std.testing.expect(!conditions.isDead(ent));
            try std.testing.expectEqual(start_fatigue, ent.fatigue);
        }
        ent.sleeping = false;
        _ = applySleep(ent);
        try std.testing.expect(!conditions.isDead(ent));
        try std.testing.expect(!w.isPlayerDead());
        try std.testing.expectEqual(@as(u16, 0), ent.fatigue);
        try std.testing.expectEqual(@as(u3, 0), conditions.exhaustionLevel(ent));
        try std.testing.expectEqual(hp_before, ent.current_hp);
    }
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

test "poisonDuration shortens with high CON and floors at 1" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const id = try w.spawnTestPlayer(@import("loc.zig").Loc.init(49, 49));
    const ent = w.store.get(id).?;
    for (ent.char.attributes.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "CON")) attr.stat = 18; // +4
    }
    try std.testing.expectEqual(@as(u16, 6), poisonDuration(ent)); // 10 - 4
    for (ent.char.attributes.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "CON")) attr.stat = 30; // +10 → floor
    }
    try std.testing.expectEqual(poison_duration_floor, poisonDuration(ent));
    for (ent.char.attributes.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "CON")) attr.stat = 8; // -1 → lengthen
    }
    try std.testing.expectEqual(@as(u16, 11), poisonDuration(ent));
}

test "poison DoT expires after CON-scaled duration" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const id = try w.spawnTestPlayer(@import("loc.zig").Loc.init(49, 49));
    const ent = w.store.get(id).?;
    for (ent.char.attributes.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "CON")) attr.stat = 18; // duration 6
    }
    applyPoison(ent);
    try std.testing.expectEqual(@as(u16, 6), ent.poison_ticks_remaining);
    var i: u16 = 0;
    while (i < 6) : (i += 1) w.tick();
    try std.testing.expect(!conditions.has(ent, .poisoned));
    try std.testing.expectEqual(@as(u16, 0), ent.poison_ticks_remaining);
    try std.testing.expectEqual(ent.max_hp - 6, ent.current_hp);
}
