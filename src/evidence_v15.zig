//! Emits observable v1.5 crawl-completeness evidence on the real command path.
const std = @import("std");
const version = @import("version.zig");
const evidence_format = @import("evidence_format.zig");

pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    const gate = version.forGate(15).?;
    try writer.print("=== evidence: v1.5 crawl completeness (version={s}) ===\n", .{gate.emit});

    var version_line_buf: [64]u8 = undefined;
    const version_line = try version.versionLine(&version_line_buf, gate.emit);

    var heal_buf: [65536]u8 = undefined;
    const heal_out = try evidence_format.runScenario(allocator, "heal_bandage", 42, &heal_buf, gate);
    try writer.print("--- scenario heal_bandage ---\n", .{});
    try evidence_format.marker(writer, version_line, heal_out, version_line);
    try evidence_format.marker(writer, "used bandage; healed", heal_out, "used bandage; healed");
    try evidence_format.marker(writer, "HP:", heal_out, "HP:");

    var trap_buf: [131072]u8 = undefined;
    const trap_out = try evidence_format.runScenario(allocator, "trap_floor", 42, &trap_buf, gate);
    try writer.print("--- scenario trap_floor ---\n", .{});
    try evidence_format.marker(writer, "floor_object trap", trap_out, "floor_object trap");
    try evidence_format.marker(writer, "trap triggered", trap_out, "trap triggered");
    try evidence_format.marker(writer, "poisoned", trap_out, "poisoned");

    var deep_buf: [65536]u8 = undefined;
    const deep_out = try evidence_format.runScenario(allocator, "deep_floor", 42, &deep_buf, gate);
    try writer.print("--- scenario deep_floor ---\n", .{});
    // v1.6 intentionally cut floor-5 loot (was plan_loot=8); monster count marker unchanged.
    try evidence_format.marker(writer, "depth_report floor=5 plan_monsters=5", deep_out, "depth_report floor=5 plan_monsters=5");
    try evidence_format.marker(writer, "depth_report floor=2 plan_monsters=3 plan_loot=4", deep_out, "depth_report floor=2 plan_monsters=3 plan_loot=4");

    var ref_header_buf: [64]u8 = undefined;
    const ref_header_line = try version.versionLine(&ref_header_buf, gate.reference_header);
    var ref_buf: [131072]u8 = undefined;
    const ref_out = try evidence_format.runScenario(allocator, "reference_crawl", 42, &ref_buf, gate);
    try writer.print("--- scenario reference_crawl ---\n", .{});
    try evidence_format.marker(writer, ref_header_line, ref_out, ref_header_line);
    try evidence_format.marker(writer, "descended to floor 2", ref_out, "descended to floor 2");
}

test "evidence v15 crawl completeness markers" {
    var buf: [32768]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(std.testing.allocator, fbs.writer());
    const out = fbs.getWritten();
    try evidence_format.expectMarkerLineTrue(out, "marker # version=1.5.3: true");
    try evidence_format.expectMarkerLineTrue(out, "marker # version=1.1.0: true");
    try evidence_format.expectMarkerLineTrue(out, "marker used bandage; healed: true");
    try evidence_format.expectMarkerLineTrue(out, "marker floor_object trap: true");
    try evidence_format.expectMarkerLineTrue(out, "marker trap triggered: true");
    try evidence_format.expectMarkerLineTrue(out, "marker poisoned: true");
    try evidence_format.expectMarkerLineTrue(out, "marker depth_report floor=5 plan_monsters=5: true");
    try evidence_format.expectMarkerLineTrue(out, "marker depth_report floor=2 plan_monsters=3 plan_loot=4: true");
}
