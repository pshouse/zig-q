const std = @import("std");
const rng = @import("rng.zig");

pub const Drop = enum { low, high };

pub const ThrowConfig = struct {
    n: u8 = 1,
    sides: u8 = 6,
    modifier: i32 = 0,
    drop: ?Drop = null,
};

pub const RollResult = struct {
    rolls: []const u8,
    sum: i32,
};

pub fn roll(r: *rng.SeededRng, config: ThrowConfig, buf: []u8) RollResult {
    std.debug.assert(buf.len >= config.n);
    var min: u8 = 255;
    var max: u8 = 0;
    var total: u32 = 0;

    var i: u8 = 0;
    while (i < config.n) : (i += 1) {
        const v = r.rollDie(config.sides);
        buf[i] = v;
        total += v;
        if (v < min) min = v;
        if (v > max) max = v;
    }

    if (config.drop) |d| {
        switch (d) {
            .low => total -= min,
            .high => total -= max,
        }
    }

    const signed = @as(i32, @intCast(total)) + config.modifier;
    return .{
        .rolls = buf[0..config.n],
        .sum = signed,
    };
}

test "4d6 drop low produces valid sum" {
    var r = rng.SeededRng.init(42);
    var buf: [4]u8 = undefined;
    const result = roll(&r, .{ .n = 4, .sides = 6, .drop = .low }, &buf);
    try std.testing.expectEqual(@as(usize, 4), result.rolls.len);
    for (result.rolls) |v| try std.testing.expect(v >= 1 and v <= 6);
    const manual_sum: u32 = result.rolls[0] + result.rolls[1] + result.rolls[2] + result.rolls[3];
    var min: u8 = 255;
    for (result.rolls) |v| {
        if (v < min) min = v;
    }
    try std.testing.expectEqual(@as(i32, @intCast(manual_sum - min)), result.sum);
}

test "same seed yields identical roll sequence" {
    var a = rng.SeededRng.init(7);
    var b = rng.SeededRng.init(7);
    var buf_a: [4]u8 = undefined;
    var buf_b: [4]u8 = undefined;
    const ra = roll(&a, .{ .n = 4, .sides = 6, .drop = .low }, &buf_a);
    const rb = roll(&b, .{ .n = 4, .sides = 6, .drop = .low }, &buf_b);
    try std.testing.expectEqualSlices(u8, ra.rolls, rb.rolls);
    try std.testing.expectEqual(ra.sum, rb.sum);
}