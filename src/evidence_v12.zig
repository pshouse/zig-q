//! Emits observable v1.2 mundane-gear evidence on the real command path.
const std = @import("std");
const version = @import("version.zig");
const evidence_format = @import("evidence_format.zig");

pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    const gate = version.forGate(12);
    try writer.print("=== evidence: v1.2 mundane gear (version={s}) ===\n", .{gate.emit});

    var version_line_buf: [64]u8 = undefined;
    const version_line = try version.versionLine(&version_line_buf, gate.emit);

    var loot_buf: [65536]u8 = undefined;
    const loot_out = try evidence_format.runScenario(allocator, "loot_roundtrip", 42, &loot_buf, gate);
    try writer.print("--- scenario loot_roundtrip ---\n", .{});
    try evidence_format.marker(writer, version_line, loot_out, version_line);
    try evidence_format.marker(writer, "picked up bandage", loot_out, "picked up bandage");
    try evidence_format.marker(writer, "bandage x1", loot_out, "bandage x1");

    var gear_buf: [65536]u8 = undefined;
    const gear_out = try evidence_format.runScenario(allocator, "geared_brawl", 42, &gear_buf, gate);
    try writer.print("--- scenario geared_brawl ---\n", .{});
    try evidence_format.marker(writer, "equipped short sword", gear_out, "equipped short sword");
    try evidence_format.marker(writer, "equipped leather armour", gear_out, "equipped leather armour");
    try evidence_format.marker(writer, "attack ", gear_out, "attack ");

    var corpse_buf: [65536]u8 = undefined;
    const corpse_out = try evidence_format.runScenario(allocator, "corpse_loot", 42, &corpse_buf, gate);
    try writer.print("--- scenario corpse_loot ---\n", .{});
    try evidence_format.marker(writer, "is slain", corpse_out, "is slain");
    try evidence_format.marker(writer, "picked up short sword", corpse_out, "picked up short sword");

    var enc_buf: [65536]u8 = undefined;
    const enc_out = try evidence_format.runScenario(allocator, "encumbered", 42, &enc_buf, gate);
    try writer.print("--- scenario encumbered ---\n", .{});
    try evidence_format.marker(writer, "too encumbered to move", enc_out, "too encumbered to move");
    try evidence_format.marker(writer, "encumbrance: 50 of 40", enc_out, "encumbrance: 50 of 40");

    var ref_header_buf: [64]u8 = undefined;
    const ref_header_line = try version.versionLine(&ref_header_buf, gate.reference_header);
    var ref_buf: [131072]u8 = undefined;
    const ref_out = try evidence_format.runScenario(allocator, "reference_crawl", 42, &ref_buf, gate);
    try writer.print("--- scenario reference_crawl ---\n", .{});
    try evidence_format.marker(writer, ref_header_line, ref_out, ref_header_line);
    try evidence_format.marker(writer, "descended to floor 3", ref_out, "descended to floor 3");
    try evidence_format.markerAbsent(writer, "picked up", ref_out, "picked up");
}

test "evidence v12 gear markers" {
    var buf: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(std.testing.allocator, fbs.writer());
    const out = fbs.getWritten();
    try evidence_format.expectMarkerLineTrue(out, "marker # version=1.2.0: true");
    try evidence_format.expectMarkerLineTrue(out, "marker # version=1.1.0: true");
    try evidence_format.expectMarkerLineTrue(out, "marker picked up bandage: true");
    try evidence_format.expectMarkerLineTrue(out, "marker equipped short sword: true");
    try evidence_format.expectMarkerLineTrue(out, "marker picked up short sword: true");
    try evidence_format.expectMarkerLineTrue(out, "marker too encumbered to move: true");
    try evidence_format.expectMarkerLineTrue(out, "marker picked up: true");
}