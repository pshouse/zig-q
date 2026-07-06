//! Shared evidence formatting and marker checks for verification transcripts.
const std = @import("std");
const dungeon = @import("dungeon.zig");
const dst = @import("dst.zig");
const version = @import("version.zig");

pub fn runScenario(
    allocator: std.mem.Allocator,
    name: []const u8,
    seed: u64,
    buf: []u8,
    gate: version.GateConfig,
) ![]const u8 {
    const semver = gate.semverForScenario(name);
    var fbs = std.io.fixedBufferStream(buf);
    try dst.runNamedScenario(allocator, name, seed, fbs.writer(), semver);
    return fbs.getWritten();
}

pub fn marker(writer: anytype, label: []const u8, haystack: []const u8, needle: []const u8) !void {
    const found = std.mem.indexOf(u8, haystack, needle) != null;
    try writer.print("marker {s}: {}\n", .{ label, found });
}

pub fn markerAbsent(writer: anytype, label: []const u8, haystack: []const u8, needle: []const u8) !void {
    const absent = std.mem.indexOf(u8, haystack, needle) == null;
    try writer.print("marker {s}: {}\n", .{ label, absent });
}

pub fn expectMarkerTrue(haystack: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, haystack, needle) != null);
}

pub fn expectMarkerLineTrue(haystack: []const u8, line_needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, haystack, line_needle) != null);
}

pub fn formatLayoutEvidence(
    buf: []u8,
    seed: u64,
    floor_index: u32,
    gen: dungeon.GeneratedFloor,
) ![]const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    const w = fbs.writer();
    try w.print("floor_index={} seed={} layout_hash={} walkable_count={}", .{
        floor_index,
        seed,
        gen.layout_hash,
        gen.walkable_count,
    });
    return fbs.getWritten();
}

pub fn formatDescendEvidence(
    buf: []u8,
    floor_index: u32,
    layout_hash: u64,
    walkable_count: usize,
    monsters: usize,
) ![]const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    const w = fbs.writer();
    try w.print("post_descend floor_index={} layout_hash={} walkable_count={} monsters={}", .{
        floor_index,
        layout_hash,
        walkable_count,
        monsters,
    });
    return fbs.getWritten();
}

pub fn printLayoutEvidence(seed: u64, floor_index: u32, gen: dungeon.GeneratedFloor) void {
    var buf: [256]u8 = undefined;
    const line = formatLayoutEvidence(&buf, seed, floor_index, gen) catch return;
    std.debug.print("{s}\n", .{line});
}

pub fn printDescendEvidence(
    floor_index: u32,
    layout_hash: u64,
    walkable_count: usize,
    monsters: usize,
) void {
    var buf: [256]u8 = undefined;
    const line = formatDescendEvidence(&buf, floor_index, layout_hash, walkable_count, monsters) catch return;
    std.debug.print("{s}\n", .{line});
}