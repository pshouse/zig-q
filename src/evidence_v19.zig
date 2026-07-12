//! v1.9.0 survival-clock easing + descend-milestone HP growth evidence
//! (docs/CLOCK_PROGRESSION.md).
const std = @import("std");
const version = @import("version.zig");
const evidence_format = @import("evidence_format.zig");

pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    const gate = version.forGate(19).?;
    try writer.print("=== evidence: v1.9 clock + descend HP growth (version={s}) ===\n", .{gate.emit});

    var version_line_buf: [64]u8 = undefined;
    const version_line = try version.versionLine(&version_line_buf, gate.emit);

    // Descend prints growth notice and max_hp climbs with depth (reference_crawl F1→F3).
    var ref_buf: [131072]u8 = undefined;
    const ref_out = try evidence_format.runScenario(allocator, "reference_crawl", 42, &ref_buf, gate);
    try writer.print("--- scenario reference_crawl ---\n", .{});
    try evidence_format.marker(writer, version_line, ref_out, version_line);
    try evidence_format.marker(writer, "descend growth notice", ref_out, "descend growth: max_hp +");
    // Two descends: base 13 +3 +3 → 19 on floor 3.
    try evidence_format.marker(writer, "max_hp climbs with depth (+3 → 16)", ref_out, "descend growth: max_hp +3 (16)");
    try evidence_format.marker(writer, "max_hp climbs with depth (+3 → 19)", ref_out, "descend growth: max_hp +3 (19)");
    // Clock lines frozen: fatigue/exhaustion reading at end of crawl.
    try evidence_format.marker(writer, "clock fatigue=26", ref_out, "fatigue=26");
    try evidence_format.marker(writer, "clock exhaustion=1", ref_out, "exhaustion=1");
    try evidence_format.marker(writer, "clock ticks=26", ref_out, "ticks=26");

    // Floor-4 dwarf: 2 ticks/move, exhaustion stays below tier 4 across ~30 moves.
    var dwarf_buf: [65536]u8 = undefined;
    const dwarf_out = try evidence_format.runScenario(allocator, "dwarf_deepfloor_clock", 42, &dwarf_buf, gate);
    try writer.print("--- scenario dwarf_deepfloor_clock ---\n", .{});
    try evidence_format.marker(writer, "race=dwarf", dwarf_out, "race=dwarf");
    // 30 moves × 2 ticks = 60.
    try evidence_format.marker(writer, "dwarf deep-floor ticks=60", dwarf_out, "ticks=60");
    try evidence_format.marker(writer, "exhaustion stays under tier 4", dwarf_out, "exhaustion=2");
    // Must not have reached the HP-halving tier during the traversal.
    const hit_tier4 = std.mem.indexOf(u8, dwarf_out, "exhaustion=4") != null or
        std.mem.indexOf(u8, dwarf_out, "exhaustion=5") != null or
        std.mem.indexOf(u8, dwarf_out, "exhaustion=6") != null;
    try writer.print("marker exhaustion_below_tier4: {}\n", .{!hit_tier4});

    // descend_crawl also prints growth on floor 2.
    var desc_buf: [65536]u8 = undefined;
    const desc_out = try evidence_format.runScenario(allocator, "descend_crawl", 42, &desc_buf, gate);
    try writer.print("--- scenario descend_crawl ---\n", .{});
    try evidence_format.marker(writer, "descend_crawl growth notice", desc_out, "descend growth: max_hp +");
}

test "evidence v19 clock and growth markers" {
    const allocator = std.testing.allocator;
    var buf: [262144]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(allocator, fbs.writer());
    const out = fbs.getWritten();
    try evidence_format.expectMarkerLineTrue(out, "marker descend growth notice: true");
    try evidence_format.expectMarkerLineTrue(out, "marker max_hp climbs with depth (+3 → 16): true");
    try evidence_format.expectMarkerLineTrue(out, "marker max_hp climbs with depth (+3 → 19): true");
    try evidence_format.expectMarkerLineTrue(out, "marker clock fatigue=26: true");
    try evidence_format.expectMarkerLineTrue(out, "marker clock exhaustion=1: true");
    try evidence_format.expectMarkerLineTrue(out, "marker clock ticks=26: true");
    try evidence_format.expectMarkerLineTrue(out, "marker race=dwarf: true");
    try evidence_format.expectMarkerLineTrue(out, "marker dwarf deep-floor ticks=60: true");
    try evidence_format.expectMarkerLineTrue(out, "marker exhaustion stays under tier 4: true");
    try evidence_format.expectMarkerLineTrue(out, "marker exhaustion_below_tier4: true");
    try evidence_format.expectMarkerLineTrue(out, "marker descend_crawl growth notice: true");
}
