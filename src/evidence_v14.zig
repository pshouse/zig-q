//! Emits observable v1.4 survival-clock evidence on the real command path.
const std = @import("std");
const version = @import("version.zig");
const evidence_format = @import("evidence_format.zig");

pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    const gate = version.forGate(14);
    try writer.print("=== evidence: v1.4 survival clock (version={s}) ===\n", .{gate.emit});

    var version_line_buf: [64]u8 = undefined;
    const version_line = try version.versionLine(&version_line_buf, gate.emit);

    var survive_buf: [65536]u8 = undefined;
    const survive_out = try evidence_format.runScenario(allocator, "survive", 42, &survive_buf, gate);
    try writer.print("--- scenario survive ---\n", .{});
    try evidence_format.marker(writer, version_line, survive_out, version_line);
    try evidence_format.marker(writer, "hunger=", survive_out, "hunger=");
    try evidence_format.marker(writer, "ate rations", survive_out, "ate rations");
    try evidence_format.marker(writer, "rested", survive_out, "rested");
    try evidence_format.marker(writer, "saved slot", survive_out, "saved slot");

    var starve_buf: [65536]u8 = undefined;
    const starve_out = try evidence_format.runScenario(allocator, "starve", 42, &starve_buf, gate);
    try writer.print("--- scenario starve ---\n", .{});
    try evidence_format.marker(writer, "hunger=100", starve_out, "hunger=100");
    try evidence_format.marker(writer, "exhaustion=3", starve_out, "exhaustion=3");
    try evidence_format.marker(writer, "moved to", starve_out, "moved to");

    var sleep_buf: [65536]u8 = undefined;
    const sleep_out = try evidence_format.runScenario(allocator, "sleep_cycle", 42, &sleep_buf, gate);
    try writer.print("--- scenario sleep_cycle ---\n", .{});
    try evidence_format.marker(writer, "sleeping (unconscious)", sleep_out, "sleeping (unconscious)");
    try evidence_format.marker(writer, "slept", sleep_out, "slept");
    try evidence_format.marker(writer, "rested", sleep_out, "rested");

    var ref_surv_buf: [131072]u8 = undefined;
    const ref_surv_out = try evidence_format.runScenario(allocator, "reference_survive", 42, &ref_surv_buf, gate);
    try writer.print("--- scenario reference_survive ---\n", .{});
    try evidence_format.marker(writer, version_line, ref_surv_out, version_line);
    try evidence_format.marker(writer, "loaded slot", ref_surv_out, "loaded slot");

    var ref_header_buf: [64]u8 = undefined;
    const ref_header_line = try version.versionLine(&ref_header_buf, gate.reference_header);
    var ref_buf: [131072]u8 = undefined;
    const ref_out = try evidence_format.runScenario(allocator, "reference_crawl", 42, &ref_buf, gate);
    try writer.print("--- scenario reference_crawl ---\n", .{});
    try evidence_format.marker(writer, ref_header_line, ref_out, ref_header_line);
    try evidence_format.marker(writer, "attack ", ref_out, "attack ");
}

test "evidence v14 survival clock markers" {
    var buf: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(std.testing.allocator, fbs.writer());
    const out = fbs.getWritten();
    try evidence_format.expectMarkerLineTrue(out, "marker # version=1.4.0: true");
    try evidence_format.expectMarkerLineTrue(out, "marker # version=1.1.0: true");
    try evidence_format.expectMarkerLineTrue(out, "marker hunger=: true");
    try evidence_format.expectMarkerLineTrue(out, "marker ate rations: true");
    try evidence_format.expectMarkerLineTrue(out, "marker sleeping (unconscious): true");
    try evidence_format.expectMarkerLineTrue(out, "marker exhaustion=3: true");
    try evidence_format.expectMarkerLineTrue(out, "marker loaded slot: true");
}