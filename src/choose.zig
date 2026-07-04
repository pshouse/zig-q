const std = @import("std");

pub fn pickIndex(count: usize, one_based: usize) !usize {
    if (one_based < 1 or one_based > count) return error.InvalidIndex;
    return one_based - 1;
}

test "pickIndex converts 1-based to 0-based" {
    try std.testing.expectEqual(@as(usize, 0), try pickIndex(3, 1));
    try std.testing.expectEqual(@as(usize, 2), try pickIndex(3, 3));
    try std.testing.expectError(error.InvalidIndex, pickIndex(3, 0));
}