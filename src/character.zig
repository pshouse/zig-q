const std = @import("std");
const types = @import("types.zig");
const session = @import("session.zig");
const world = @import("world.zig");

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
    return @divTrunc(@as(i32, @intCast(stat)) - 10, 2);
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

test "formatDraftStats shows hp and ac from draft" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try formatDraftStats(allocator, &w, &draft, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "character (draft)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "HP:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "AC:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "dwarf") != null);
}