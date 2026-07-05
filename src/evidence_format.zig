//! Shared numeric evidence lines for generator/descend verification.
const std = @import("std");
const dungeon = @import("dungeon.zig");

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