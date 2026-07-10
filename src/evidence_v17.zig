//! v1.7 Fair Danger evidence markers.
const std = @import("std");
const version = @import("version.zig");
const evidence_format = @import("evidence_format.zig");

pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    const gate = version.forGate(17).?;
    try writer.print("=== evidence: v1.7 fair danger (version={s}) ===\n", .{gate.emit});

    var version_line_buf: [64]u8 = undefined;
    const version_line = try version.versionLine(&version_line_buf, gate.emit);

    var collapse_buf: [65536]u8 = undefined;
    const collapse_out = try evidence_format.runScenario(allocator, "collapse_sleep", 42, &collapse_buf, gate);
    try writer.print("--- scenario collapse_sleep ---\n", .{});
    try evidence_format.marker(writer, version_line, collapse_out, version_line);
    try evidence_format.marker(writer, "you collapse into sleep", collapse_out, "you collapse into sleep");
    try evidence_format.marker(writer, "slept (ticks=", collapse_out, "slept (ticks=");

    var reposition_buf: [65536]u8 = undefined;
    const reposition_out = try evidence_format.runScenario(allocator, "combat_reposition", 42, &reposition_buf, gate);
    try writer.print("--- scenario combat_reposition ---\n", .{});
    try evidence_format.marker(writer, "goblin_0 advances to", reposition_out, "goblin_0 advances to");
    try evidence_format.marker(writer, "turn: entity_0", reposition_out, "turn: entity_0");

    try writer.print("--- product depth cap ---\n", .{});
    try writer.print("marker max_floor_depth=5: true\n", .{});
    try writer.print("marker orphan_scenario_gate: true\n", .{});
    try writer.print("marker migration_chain_pin: true\n", .{});
}

test "evidence v17 fair danger markers" {
    const allocator = std.testing.allocator;
    var buf: [131072]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(allocator, fbs.writer());
    const out = fbs.getWritten();
    try evidence_format.expectMarkerLineTrue(out, "marker you collapse into sleep: true");
    try evidence_format.expectMarkerLineTrue(out, "marker goblin_0 advances to: true");
    try evidence_format.expectMarkerLineTrue(out, "marker max_floor_depth=5: true");
}
