const std = @import("std");
const types = @import("types.zig");
const character = @import("character.zig");

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
        .current_hp = b.max_hp,
        .max_hp = b.max_hp,
        .damage_die = b.damage_die,
        .is_monster = true,
    };
    return char;
}

pub fn armorClass(char: *const types.Character) u32 {
    if (std.mem.eql(u8, char.name, "goblin")) return block(.goblin).ac;
    if (std.mem.eql(u8, char.name, "skeleton")) return block(.skeleton).ac;
    return character.armorClass(char);
}

test "goblin block has expected hp" {
    const b = block(.goblin);
    try std.testing.expectEqual(@as(u32, 7), b.max_hp);
    try std.testing.expectEqual(@as(u32, 15), b.ac);
}