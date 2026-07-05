//! Emits observable v0.8 save/load evidence on the real command path.
const std = @import("std");
const world = @import("world.zig");
const loc = @import("loc.zig");
const session = @import("session.zig");
const commands = @import("commands.zig");
const sqlite_store = @import("sqlite_store.zig");

pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    const path = "zig-q-evidence-v08.sqlite";
    sqlite_store.deleteDb(path);

    try writer.writeAll("=== evidence: save/load roundtrip (execute path) ===\n");

    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);

    var ctx = commands.Context{
        .allocator = allocator,
        .w = &w,
        .draft = &draft,
        .save_path = path,
    };
    _ = try commands.execute(&ctx, .spawn, std.io.null_writer);
    _ = try commands.execute(&ctx, commands.parseLine("move east"), std.io.null_writer);
    _ = try commands.execute(&ctx, .save, writer);
    _ = try commands.execute(&ctx, commands.parseLine("load 1"), writer);
    _ = try commands.execute(&ctx, .look, writer);
    _ = try commands.execute(&ctx, .stats, writer);

    const snap = w.snapshot();
    try writer.print("snapshot seed={} entities={} rng_offset={} ticks={}\n", .{
        snap.seed,
        snap.entity_count,
        snap.rng_offset,
        snap.clock_ticks,
    });
}

test "evidence v08 save load output" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(std.testing.allocator, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "saved slot") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "loaded slot") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "snapshot seed=42") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "HP: ") != null);
}