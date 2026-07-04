const std = @import("std");

pub const Loc = struct {
    x: u64,
    y: u64,

    pub fn init(x: u64, y: u64) Loc {
        return .{ .x = x, .y = y };
    }
};

pub fn distSq(p1: Loc, p2: Loc) u64 {
    const dx = @as(i64, @intCast(p1.x)) - @as(i64, @intCast(p2.x));
    const dy = @as(i64, @intCast(p1.y)) - @as(i64, @intCast(p2.y));
    const ux = @as(u64, @intCast(dx * dx));
    const uy = @as(u64, @intCast(dy * dy));
    return ux + uy;
}

test "distSq zero for same point" {
    const p = Loc.init(3, 4);
    try std.testing.expectEqual(@as(u64, 0), distSq(p, p));
}