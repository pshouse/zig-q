const std = @import("std");
const types = @import("types.zig");

pub const Kind = enum {
    goblin,
    skeleton,
    hobgoblin,
    skeleton_warrior,
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
        .hobgoblin => .{
            .name = "hobgoblin",
            .str = 13,
            .dex = 12,
            .con = 12,
            .max_hp = 16,
            .ac = 16,
            .damage_die = 6,
        },
        .skeleton_warrior => .{
            .name = "skeleton_warrior",
            .str = 13,
            .dex = 12,
            .con = 14,
            .max_hp = 20,
            .ac = 15,
            .damage_die = 8,
        },
    };
}

/// True for elite kinds that only spawn on danger floors (floor ≥ 4).
pub fn isElite(kind: Kind) bool {
    return switch (kind) {
        .hobgoblin, .skeleton_warrior => true,
        .goblin, .skeleton => false,
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

/// Viewport glyph for a live monster of this kind. Lowercase letters are
/// reserved for monsters (`@` player, `*` other entities, `#`/`.`/`>`/`+`
/// terrain); adding a Kind forces a glyph choice here.
pub fn glyph(kind: Kind) u8 {
    return switch (kind) {
        .goblin => 'g',
        .skeleton => 's',
        .hobgoblin => 'h',
        .skeleton_warrior => 'w',
    };
}

/// Entities carry their kind only as `char.name` (set from `block().name`,
/// preserved verbatim across save/load), so the renderer resolves glyphs by
/// name. Returns null for non-monster names.
pub fn glyphForName(name: []const u8) ?u8 {
    const kind = std.meta.stringToEnum(Kind, name) orelse return null;
    return glyph(kind);
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

test "every kind maps block name to its enum tag" {
    // glyphForName resolves via the tag name while entities store block().name;
    // the two must stay identical or spawned monsters lose their glyph.
    for (std.enums.values(Kind)) |kind| {
        try std.testing.expectEqualStrings(@tagName(kind), block(kind).name);
    }
}

test "glyph mapping per kind" {
    try std.testing.expectEqual(@as(u8, 'g'), glyph(.goblin));
    try std.testing.expectEqual(@as(u8, 's'), glyph(.skeleton));
    try std.testing.expectEqual(@as(u8, 'h'), glyph(.hobgoblin));
    try std.testing.expectEqual(@as(u8, 'w'), glyph(.skeleton_warrior));
    try std.testing.expectEqual(@as(?u8, 'g'), glyphForName("goblin"));
    try std.testing.expectEqual(@as(?u8, 's'), glyphForName("skeleton"));
    try std.testing.expectEqual(@as(?u8, 'h'), glyphForName("hobgoblin"));
    try std.testing.expectEqual(@as(?u8, 'w'), glyphForName("skeleton_warrior"));
    try std.testing.expectEqual(@as(?u8, null), glyphForName("George"));
}

test "elite blocks are tougher than base kin" {
    try std.testing.expect(block(.hobgoblin).max_hp > block(.goblin).max_hp);
    try std.testing.expect(block(.skeleton_warrior).max_hp > block(.skeleton).max_hp);
    try std.testing.expect(isElite(.hobgoblin));
    try std.testing.expect(!isElite(.goblin));
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

    try @import("combat.zig").enterCombat(&w, player_id, skel_id, player_id);
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try @import("combat.zig").performAttack(&w, player_id, skel_id, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "vs AC 13") != null);
}
