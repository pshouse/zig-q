const std = @import("std");
const dice = @import("dice.zig");
const types = @import("types.zig");
const world = @import("world.zig");

pub const StatPool = struct {
    rolls: [6]i32,
};

pub fn rollStatPool(w: *world.World) StatPool {
    var pool: StatPool = undefined;
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        var buf: [4]u8 = undefined;
        const result = dice.roll(&w.rng, .{ .n = 4, .sides = 6, .drop = .low }, &buf);
        pool.rolls[i] = result.sum;
    }
    return pool;
}

pub fn bootstrapCharacter(
    allocator: std.mem.Allocator,
    w: *world.World,
    name: []const u8,
) !struct { character: *types.Character, pool: StatPool } {
    const pool = rollStatPool(w);

    var attrs = try types.defaultAttributes(allocator);
    var i: usize = 0;
    while (i < attrs.items.len) : (i += 1) {
        attrs.items[i].stat = @intCast(pool.rolls[i]);
    }

    const char = try allocator.create(types.Character);
    char.* = .{
        .name = name,
        .attributes = attrs,
        .race = w.races.items[0],
        .class = types.defaultClasses()[0],
    };

    return .{ .character = char, .pool = pool };
}

pub fn formatStatPool(pool: StatPool, writer: anytype) !void {
    try writer.print("stat_rolls:", .{});
    for (pool.rolls, 0..) |roll, idx| {
        try writer.print(" {d}={}", .{ idx + 1, roll });
    }
    try writer.print("\n", .{});
}