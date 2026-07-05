//! Emits observable v1.0 reference-crawl evidence on the real command path.
const std = @import("std");
const dst = @import("dst.zig");
const version = @import("version.zig");

pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("=== evidence: v1.0 reference crawl (version={s}) ===\n", .{version.semver});

    var buf: [131072]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try dst.runNamedScenario(allocator, "reference_crawl", 42, fbs.writer());
    const out = fbs.getWritten();

    const markers = [_][]const u8{
        "descended to floor 2",
        "descended to floor 3",
        "look floor=3",
        "attack ",
        "saved slot",
        "loaded slot",
    };
    for (markers) |marker| {
        try writer.print("marker {s}: {}\n", .{ marker, std.mem.indexOf(u8, out, marker) != null });
    }
}

test "evidence v10 reference crawl markers" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(std.testing.allocator, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "marker descended to floor 3: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "marker saved slot: true") != null);
}