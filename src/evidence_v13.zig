//! Emits observable v1.3 living-dungeon evidence on the real command path.
const std = @import("std");
const version = @import("version.zig");
const evidence_format = @import("evidence_format.zig");

pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    const gate = version.forGate(13).?;
    try writer.print("=== evidence: v1.3 living dungeon (version={s}) ===\n", .{gate.emit});

    var version_line_buf: [64]u8 = undefined;
    const version_line = try version.versionLine(&version_line_buf, gate.emit);

    var hunt_buf: [65536]u8 = undefined;
    const hunt_out = try evidence_format.runScenario(allocator, "hunt", 42, &hunt_buf, gate);
    try writer.print("--- scenario hunt ---\n", .{});
    try evidence_format.marker(writer, version_line, hunt_out, version_line);
    try evidence_format.marker(writer, "hunt_goblin", hunt_out, "hunt_goblin");

    var flee_buf: [65536]u8 = undefined;
    const flee_out = try evidence_format.runScenario(allocator, "flee", 42, &flee_buf, gate);
    try writer.print("--- scenario flee ---\n", .{});
    try evidence_format.marker(writer, "flee_goblin", flee_out, "flee_goblin");

    var trap_buf: [65536]u8 = undefined;
    const trap_out = try evidence_format.runScenario(allocator, "trap_trigger", 42, &trap_buf, gate);
    try writer.print("--- scenario trap_trigger ---\n", .{});
    try evidence_format.marker(writer, "trap triggered", trap_out, "trap triggered");
    try evidence_format.marker(writer, "poison cleared", trap_out, "poison cleared");

    var door_buf: [65536]u8 = undefined;
    const door_out = try evidence_format.runScenario(allocator, "door_route", 42, &door_buf, gate);
    try writer.print("--- scenario door_route ---\n", .{});
    try evidence_format.marker(writer, "opened door", door_out, "opened door");

    var ambush_buf: [65536]u8 = undefined;
    const ambush_out = try evidence_format.runScenario(allocator, "ambush", 42, &ambush_buf, gate);
    try writer.print("--- scenario ambush ---\n", .{});
    try evidence_format.marker(writer, "ambush combat started", ambush_out, "ambush combat started");

    var ref_header_buf: [64]u8 = undefined;
    const ref_header_line = try version.versionLine(&ref_header_buf, gate.reference_header);
    var ref_buf: [131072]u8 = undefined;
    const ref_out = try evidence_format.runScenario(allocator, "reference_crawl", 42, &ref_buf, gate);
    try writer.print("--- scenario reference_crawl ---\n", .{});
    try evidence_format.marker(writer, ref_header_line, ref_out, ref_header_line);
    try evidence_format.marker(writer, "descended to floor 2", ref_out, "descended to floor 2");
}

test "evidence v13 living dungeon markers" {
    var buf: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(std.testing.allocator, fbs.writer());
    const out = fbs.getWritten();
    try evidence_format.expectMarkerLineTrue(out, "marker # version=1.3.0: true");
    try evidence_format.expectMarkerLineTrue(out, "marker # version=1.1.0: true");
    try evidence_format.expectMarkerLineTrue(out, "marker hunt_goblin: true");
    try evidence_format.expectMarkerLineTrue(out, "marker flee_goblin: true");
    try evidence_format.expectMarkerLineTrue(out, "marker trap triggered: true");
    try evidence_format.expectMarkerLineTrue(out, "marker poison cleared: true");
    try evidence_format.expectMarkerLineTrue(out, "marker opened door: true");
    try evidence_format.expectMarkerLineTrue(out, "marker ambush combat started: true");
}