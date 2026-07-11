const std = @import("std");
const types = @import("types.zig");
const session = @import("session.zig");
const world = @import("world.zig");
const entity = @import("entity.zig");

/// Ability abbreviation used for TO-HIT. Class-routed seam for Phase 0 of the
/// character rework (see docs/CHARACTER_REWORK.md / PR #58). All current classes
/// and monsters resolve to STR; a future `"rogue" => "DEX"` branch is a one-liner.
pub fn attackAbbr(ent: *const entity.Entity) []const u8 {
    return attackStatAbbr(ent.char.class.name);
}

/// Ability abbreviation used for DAMAGE modifier. Same routing as attackAbbr
/// today (both STR); kept separate so future phases can diverge if needed.
pub fn damageAbbr(ent: *const entity.Entity) []const u8 {
    return attackStatAbbr(ent.char.class.name);
}

fn attackStatAbbr(class_name: []const u8) []const u8 {
    // Explicit cases document the current roster; default covers monsters and
    // any future class that stays STR-based until a dedicated branch is added.
    if (std.mem.eql(u8, class_name, "barbarian")) return "STR";
    if (std.mem.eql(u8, class_name, "fighter")) return "STR";
    if (std.mem.eql(u8, class_name, "bard")) return "STR";
    // Future: if (std.mem.eql(u8, class_name, "rogue")) return "DEX";
    return "STR";
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

test "attackAbbr and damageAbbr return STR for current classes and monsters" {
    const allocator = std.testing.allocator;
    const classes = [_][]const u8{ "barbarian", "fighter", "bard", "monster" };
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