const std = @import("std");
const types = @import("types.zig");
const session = @import("session.zig");

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

pub fn formatStats(char: *const types.Character, writer: anytype) !void {
    try writer.print("character {s} race={s} class={s}\n", .{
        char.name,
        char.race.name,
        char.class.name,
    });
    for (char.attributes.items) |attr| {
        try writer.print("{s}: {}\n", .{ attr.abbr, attr.stat });
    }
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