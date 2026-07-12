const std = @import("std");
const types = @import("types.zig");
const session = @import("session.zig");
const world = @import("world.zig");
const entity = @import("entity.zig");
const items = @import("items.zig");

/// True when the entity wields a heavy weapon (war axe, greatsword). Unarmed is light.
pub fn wieldingHeavy(ent: *const entity.Entity) bool {
    if (ent.inventory.weapon) |wid| return items.def(wid).heavy;
    return false;
}

/// Ability abbreviation used for TO-HIT. Class-routed seam (docs/CHARACTER_REWORK.md).
/// Rogue with a light/unarmed weapon routes through DEX (finesse); all others STR.
/// No RNG draws — only which modifier is read.
pub fn attackAbbr(ent: *const entity.Entity) []const u8 {
    return attackStatAbbr(ent);
}

/// Ability abbreviation used for DAMAGE modifier. Same routing as attackAbbr.
pub fn damageAbbr(ent: *const entity.Entity) []const u8 {
    return attackStatAbbr(ent);
}

fn attackStatAbbr(ent: *const entity.Entity) []const u8 {
    // Rogue finesse: DEX with light/unarmed only; heavy weapons revert to STR.
    if (std.mem.eql(u8, ent.char.class.name, "rogue") and !wieldingHeavy(ent)) return "DEX";
    // barbarian, fighter, monster, and any future STR class.
    return "STR";
}

/// Fighter discipline: damage-die natural 1 clamps to 2 (no-fumble). Pure; no draws.
pub fn disciplineFace(class_name: []const u8, face: u8) u8 {
    if (std.mem.eql(u8, class_name, "fighter") and face == 1) return 2;
    return face;
}

/// Rogue backstab gate: light/unarmed only. Pure — no draws.
pub fn canBackstabWeapon(ent: *const entity.Entity) bool {
    return std.mem.eql(u8, ent.char.class.name, "rogue") and !wieldingHeavy(ent);
}

pub fn assignStatPool(
    attributes: *std.ArrayList(types.Attribute),
    pool: session.StatPool,
    picks: [6]usize,
) !void {
    if (attributes.items.len != 6) return error.InvalidAttributeCount;
    for (picks, 0..) |pick, attr_idx| {
        if (pick < 1 or pick > 6) return error.InvalidPick;
        attributes.items[attr_idx].stat = @intCast(pool.rolls[pick - 1]);
    }
}

pub fn applyRaceBonuses(char: *types.Character) void {
    for (char.race.attr_bonuses.items) |bonus| {
        for (char.attributes.items) |*attr| {
            if (std.mem.eql(u8, attr.abbr, bonus.abbr)) {
                attr.stat += bonus.stat;
            }
        }
    }
}

pub fn abilityModifier(stat: u64) i32 {
    return @divFloor(@as(i32, @intCast(stat)) - 10, 2);
}

pub fn statByAbbr(char: *const types.Character, abbr: []const u8) u64 {
    for (char.attributes.items) |attr| {
        if (std.mem.eql(u8, attr.abbr, abbr)) return attr.stat;
    }
    return 0;
}

pub fn maxHpLevel1(char: *const types.Character) u32 {
    const con_mod = abilityModifier(statByAbbr(char, "CON"));
    const hp = @as(i32, char.class.hit_die) + con_mod;
    return @intCast(@max(hp, 1));
}

/// HP gained on each descend to a new deepest floor (v1.9.0). Pure; no RNG.
/// CON≤11 → +2, CON 12–13 → +3, CON 14+ → +4. Cap over max depth 5 is +16.
pub fn descendHpGrowth(char: *const types.Character) u32 {
    const con_mod = abilityModifier(statByAbbr(char, "CON"));
    const capped: i32 = @min(con_mod, 2);
    return @intCast(@max(2 + capped, 1));
}

pub fn armorClass(char: *const types.Character) u32 {
    const dex_mod = abilityModifier(statByAbbr(char, "DEX"));
    return @intCast(10 + dex_mod);
}

fn formatSheetBody(char: *const types.Character, writer: anytype) !void {
    for (char.attributes.items) |attr| {
        try writer.print("{s}: {}\n", .{ attr.abbr, attr.stat });
    }
    const hp = maxHpLevel1(char);
    const ac = armorClass(char);
    try writer.print("HP: {}\n", .{hp});
    try writer.print("AC: {}\n", .{ac});
}

pub fn formatStats(char: *const types.Character, writer: anytype) !void {
    try writer.print("character {s} race={s} class={s}\n", .{
        char.name,
        char.race.name,
        char.class.name,
    });
    try formatSheetBody(char, writer);
}

pub fn formatDraftStats(
    allocator: std.mem.Allocator,
    w: *world.World,
    draft: *const session.CreationDraft,
    writer: anytype,
) !void {
    const char = try session.draftBuildCharacter(allocator, w, draft, "George");
    defer {
        char.attributes.deinit(allocator);
        allocator.destroy(char);
    }
    try writer.print("character (draft) {s} race={s} class={s}\n", .{
        char.name,
        char.race.name,
        char.class.name,
    });
    try formatSheetBody(char, writer);
}

test "applyRaceBonuses increases matching attribute" {
    const allocator = std.testing.allocator;
    var attrs = try types.defaultAttributes(allocator);
    defer attrs.deinit(allocator);

    for (attrs.items) |*attr| attr.stat = 10;

    var bonuses: std.ArrayList(types.Attribute) = .empty;
    try bonuses.append(allocator, .{ .name = "con_bonus", .abbr = "CON", .stat = 2 });

    var char = types.Character{
        .name = "test",
        .attributes = attrs,
        .race = .{ .name = "dwarf", .speed = 25, .attr_bonuses = bonuses },
        .class = types.defaultClasses()[0],
    };
    defer char.race.attr_bonuses.deinit(allocator);

    applyRaceBonuses(&char);

    for (char.attributes.items) |attr| {
        if (std.mem.eql(u8, attr.abbr, "CON")) {
            try std.testing.expectEqual(@as(u64, 12), attr.stat);
            return;
        }
    }
    return error.TestExpectedEqual;
}

test "assignStatPool maps picks to attributes" {
    const allocator = std.testing.allocator;
    var attrs = try types.defaultAttributes(allocator);
    defer attrs.deinit(allocator);

    const pool: session.StatPool = .{ .rolls = .{ 13, 5, 12, 10, 14, 12 } };
    try assignStatPool(&attrs, pool, .{ 6, 5, 4, 3, 2, 1 });

    try std.testing.expectEqual(@as(u64, 12), attrs.items[0].stat);
    try std.testing.expectEqual(@as(u64, 14), attrs.items[1].stat);
    try std.testing.expectEqual(@as(u64, 10), attrs.items[2].stat);
}

test "abilityModifier floors toward negative infinity" {
    try std.testing.expectEqual(@as(i32, 0), abilityModifier(10));
    try std.testing.expectEqual(@as(i32, -1), abilityModifier(9));
    try std.testing.expectEqual(@as(i32, -2), abilityModifier(7));
    try std.testing.expectEqual(@as(i32, 2), abilityModifier(14));
}

test "descendHpGrowth scales by CON with cap" {
    const allocator = std.testing.allocator;

    // CON 10 → mod 0 → +2
    {
        var attrs = try types.defaultAttributes(allocator);
        defer attrs.deinit(allocator);
        for (attrs.items) |*a| a.stat = 10;
        const char = types.Character{
            .name = "t",
            .attributes = attrs,
            .race = .{ .name = "human", .speed = 30, .attr_bonuses = .empty },
            .class = types.defaultClasses()[0],
        };
        try std.testing.expectEqual(@as(u32, 2), descendHpGrowth(&char));
    }
    // CON 12 (dwarf-like +1 mod) → +3
    {
        var attrs = try types.defaultAttributes(allocator);
        defer attrs.deinit(allocator);
        for (attrs.items) |*a| a.stat = 10;
        for (attrs.items) |*a| {
            if (std.mem.eql(u8, a.abbr, "CON")) a.stat = 12;
        }
        const char = types.Character{
            .name = "t",
            .attributes = attrs,
            .race = .{ .name = "dwarf", .speed = 25, .attr_bonuses = .empty },
            .class = types.defaultClasses()[0],
        };
        try std.testing.expectEqual(@as(u32, 3), descendHpGrowth(&char));
    }
    // CON 14 → mod 2 → +4
    {
        var attrs = try types.defaultAttributes(allocator);
        defer attrs.deinit(allocator);
        for (attrs.items) |*a| a.stat = 10;
        for (attrs.items) |*a| {
            if (std.mem.eql(u8, a.abbr, "CON")) a.stat = 14;
        }
        const char = types.Character{
            .name = "t",
            .attributes = attrs,
            .race = .{ .name = "human", .speed = 30, .attr_bonuses = .empty },
            .class = types.defaultClasses()[0],
        };
        try std.testing.expectEqual(@as(u32, 4), descendHpGrowth(&char));
    }
    // CON 18 → mod 4, capped → +4
    {
        var attrs = try types.defaultAttributes(allocator);
        defer attrs.deinit(allocator);
        for (attrs.items) |*a| a.stat = 10;
        for (attrs.items) |*a| {
            if (std.mem.eql(u8, a.abbr, "CON")) a.stat = 18;
        }
        const char = types.Character{
            .name = "t",
            .attributes = attrs,
            .race = .{ .name = "human", .speed = 30, .attr_bonuses = .empty },
            .class = types.defaultClasses()[0],
        };
        try std.testing.expectEqual(@as(u32, 4), descendHpGrowth(&char));
    }
    // CON 8 → mod -1 → floor 1
    {
        var attrs = try types.defaultAttributes(allocator);
        defer attrs.deinit(allocator);
        for (attrs.items) |*a| a.stat = 10;
        for (attrs.items) |*a| {
            if (std.mem.eql(u8, a.abbr, "CON")) a.stat = 8;
        }
        const char = types.Character{
            .name = "t",
            .attributes = attrs,
            .race = .{ .name = "human", .speed = 30, .attr_bonuses = .empty },
            .class = types.defaultClasses()[0],
        };
        try std.testing.expectEqual(@as(u32, 1), descendHpGrowth(&char));
    }
}

test "attackAbbr and damageAbbr return STR for non-finesse classes and monsters" {
    const allocator = std.testing.allocator;
    const classes = [_][]const u8{ "barbarian", "fighter", "monster" };
    for (classes) |class_name| {
        var attrs = try types.defaultAttributes(allocator);
        defer attrs.deinit(allocator);
        var char = types.Character{
            .name = "t",
            .attributes = attrs,
            .race = .{ .name = "human", .speed = 30, .attr_bonuses = .empty },
            .class = .{ .name = class_name, .hit_die = 8 },
        };
        const ent = entity.Entity{
            .id = 0,
            .name = undefined,
            .loc = .{ .x = 0, .y = 0 },
            .char = &char,
            .conditions = types.ConditionSet.initEmpty(),
        };
        try std.testing.expectEqualStrings("STR", attackAbbr(&ent));
        try std.testing.expectEqualStrings("STR", damageAbbr(&ent));
    }
}

test "rogue finesse uses DEX unarmed/light and STR with heavy weapon" {
    const allocator = std.testing.allocator;
    var attrs = try types.defaultAttributes(allocator);
    defer attrs.deinit(allocator);
    var char = types.Character{
        .name = "t",
        .attributes = attrs,
        .race = .{ .name = "elf", .speed = 30, .attr_bonuses = .empty },
        .class = .{ .name = "rogue", .hit_die = 8 },
    };
    var ent = entity.Entity{
        .id = 0,
        .name = undefined,
        .loc = .{ .x = 0, .y = 0 },
        .char = &char,
        .conditions = types.ConditionSet.initEmpty(),
    };
    // Unarmed: light → DEX.
    try std.testing.expect(!wieldingHeavy(&ent));
    try std.testing.expectEqualStrings("DEX", attackAbbr(&ent));
    try std.testing.expectEqualStrings("DEX", damageAbbr(&ent));
    // Short sword: light → DEX.
    ent.inventory.weapon = .short_sword;
    try std.testing.expect(!wieldingHeavy(&ent));
    try std.testing.expectEqualStrings("DEX", attackAbbr(&ent));
    // Greatsword: heavy → STR.
    ent.inventory.weapon = .greatsword;
    try std.testing.expect(wieldingHeavy(&ent));
    try std.testing.expectEqualStrings("STR", attackAbbr(&ent));
    try std.testing.expectEqualStrings("STR", damageAbbr(&ent));
}

test "discipline clamps fighter damage face 1 to 2" {
    try std.testing.expectEqual(@as(u8, 2), disciplineFace("fighter", 1));
    try std.testing.expectEqual(@as(u8, 3), disciplineFace("fighter", 3));
    try std.testing.expectEqual(@as(u8, 1), disciplineFace("barbarian", 1));
    try std.testing.expectEqual(@as(u8, 1), disciplineFace("rogue", 1));
}

test "maxHpLevel1 with low con uses floor modifier" {
    const allocator = std.testing.allocator;
    var attrs = try types.defaultAttributes(allocator);
    defer attrs.deinit(allocator);
    for (attrs.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "CON")) attr.stat = 7;
    }
    const char = types.Character{
        .name = "t",
        .attributes = attrs,
        .race = .{ .name = "human", .speed = 30, .attr_bonuses = .empty },
        .class = .{ .name = "barbarian", .hit_die = 12 },
    };
    try std.testing.expectEqual(@as(u32, 10), maxHpLevel1(&char));
}

test "armorClass with low dex uses floor modifier" {
    const allocator = std.testing.allocator;
    var attrs = try types.defaultAttributes(allocator);
    defer attrs.deinit(allocator);
    for (attrs.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "DEX")) attr.stat = 9;
    }
    const char = types.Character{
        .name = "t",
        .attributes = attrs,
        .race = .{ .name = "human", .speed = 30, .attr_bonuses = .empty },
        .class = types.defaultClasses()[0],
    };
    try std.testing.expectEqual(@as(u32, 9), armorClass(&char));
}

test "maxHpLevel1 uses hit die and con modifier" {
    const allocator = std.testing.allocator;
    var attrs = try types.defaultAttributes(allocator);
    defer attrs.deinit(allocator);
    for (attrs.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "CON")) attr.stat = 14;
    }
    const char = types.Character{
        .name = "t",
        .attributes = attrs,
        .race = .{ .name = "human", .speed = 30, .attr_bonuses = .empty },
        .class = .{ .name = "barbarian", .hit_die = 12 },
    };
    try std.testing.expectEqual(@as(u32, 14), maxHpLevel1(&char));
}

test "armorClass uses dex modifier" {
    const allocator = std.testing.allocator;
    var attrs = try types.defaultAttributes(allocator);
    defer attrs.deinit(allocator);
    for (attrs.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "DEX")) attr.stat = 14;
    }
    const char = types.Character{
        .name = "t",
        .attributes = attrs,
        .race = .{ .name = "human", .speed = 30, .attr_bonuses = .empty },
        .class = types.defaultClasses()[0],
    };
    try std.testing.expectEqual(@as(u32, 12), armorClass(&char));
}

test "draft dwarf with con 7 yields hp 10 on real build path" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 2, 4, 3, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);

    const char = try session.draftBuildCharacter(allocator, &w, &draft, "George");
    defer {
        char.attributes.deinit(allocator);
        allocator.destroy(char);
    }
    try std.testing.expectEqual(@as(u64, 7), statByAbbr(char, "CON"));
    try std.testing.expectEqual(@as(u32, 10), maxHpLevel1(char));
}

pub const low_con_draft_sheet =
    \\character (draft) George race=dwarf class=barbarian
    \\STR: 12
    \\DEX: 14
    \\CON: 7
    \\INT: 10
    \\WIS: 12
    \\CHA: 13
    \\HP: 10
    \\AC: 12
    \\
;

test "formatDraftStats exact low-con dwarf barbarian sheet" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 2, 4, 3, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try formatDraftStats(allocator, &w, &draft, fbs.writer());
    try std.testing.expectEqualStrings(low_con_draft_sheet, fbs.getWritten());
}