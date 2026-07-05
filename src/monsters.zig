const std = @import("std");
const types = @import("types.zig");

pub const Kind = enum {
    goblin,
    skeleton,
};

pub const Block = struct {
    name: []const u8,
    str: u64,
    dex: u64,
    con: u64,
    max_hp: u32,
    ac: u32,
    damage_die: u8,
};

pub fn block(kind: Kind) Block {
    return switch (kind) {
        .goblin => .{
            .name = "goblin",
            .str = 8,
            .dex = 14,
            .con = 10,
            .max_hp = 7,
            .ac = 15,
            .damage_die = 6,
        },
        .skeleton => .{
            .name = "skeleton",
            .str = 10,
            .dex = 14,
            .con = 15,
            .max_hp = 13,
            .ac = 13,
            .damage_die = 6,
        },
    };
}

pub fn buildCharacter(allocator: std.mem.Allocator, kind: Kind) !*types.Character {
    const b = block(kind);
    const attrs = try types.defaultAttributes(allocator);
    for (attrs.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "STR")) attr.stat = b.str;
        if (std.mem.eql(u8, attr.abbr, "DEX")) attr.stat = b.dex;
        if (std.mem.eql(u8, attr.abbr, "CON")) attr.stat = b.con;
    }

    const char = try allocator.create(types.Character);
    char.* = .{
        .name = b.name,
        .attributes = attrs,
        .race = .{ .name = "monster", .speed = 30, .attr_bonuses = .empty },
        .class = .{ .name = "monster", .hit_die = 6 },
        .status = .exploring,
    };
    return char;
}

pub fn armorClass(kind: Kind) u32 {
    return block(kind).ac;
}

test "goblin block stats" {
    const b = block(.goblin);
    try std.testing.expectEqual(@as(u32, 7), b.max_hp);
    try std.testing.expectEqual(@as(u32, 15), b.ac);
}

test "skeleton block stats" {
    const b = block(.skeleton);
    try std.testing.expectEqual(@as(u32, 13), b.max_hp);
    try std.testing.expectEqual(@as(u32, 13), b.ac);
}

test "spawnMonster skeleton uses skeleton ac in combat" {
    const allocator = std.testing.allocator;
    var w = try @import("world.zig").World.init(allocator, 42);
    defer w.deinit();

    const player_id = try w.spawnTestPlayer(@import("loc.zig").Loc.init(49, 49));
    const skel_id = try w.spawnMonster(.skeleton, @import("loc.zig").Loc.init(50, 49), "skeleton_0");
    const skel = w.store.get(skel_id).?;
    try std.testing.expect(skel.is_monster);
    try std.testing.expectEqual(@as(u32, 13), @import("combat.zig").targetAc(skel));

    try @import("combat.zig").enterCombat(&w, player_id, skel_id);
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try @import("combat.zig").performAttack(&w, player_id, skel_id, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "vs AC 13") != null);
}