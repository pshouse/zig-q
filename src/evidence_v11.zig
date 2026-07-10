//! Emits observable v1.1 foundation evidence on the real command path.
const std = @import("std");
const version = @import("version.zig");
const save_state = @import("save_state.zig");
const evidence_format = @import("evidence_format.zig");

pub fn runMigrationEvidence(allocator: std.mem.Allocator, writer: anytype) !void {
    var save = save_state.WorldSave{
        .schema_version = save_state.schema_version_v1,
        .seed = 42,
        .rng_state = 1,
        .rng_offset = 0,
        .floor_index = 1,
        .has_dungeon = true,
        .clock_ticks = 0,
        .clock_time_of_day = 0,
        .clock_seconds_per_day = 120,
        .clock_update_rate = 5,
        .clock_time_multiplier = 1,
        .next_entity_id = 1,
        .player_id = 0,
        .entities = &.{},
        .map_cells = &.{},
        .combat = null,
    };
    try save_state.migrateV1ToV2(&save, allocator);
    try writer.print("migration schema={} floor_objects={} player_dead={}\n", .{
        save.schema_version,
        save.floor_objects.len,
        save.player_dead,
    });
    for (save.entities) |*ent| {
        try writer.print("entity exhaustion_level={}\n", .{ent.exhaustion_level});
    }
}

pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    const gate = version.forGate(11).?;
    try writer.print("=== evidence: v1.1 foundation (version={s}) ===\n", .{gate.emit});

    var version_line_buf: [64]u8 = undefined;
    const version_line = try version.versionLine(&version_line_buf, gate.emit);

    var ambush_buf: [65536]u8 = undefined;
    const ambush_out = try evidence_format.runScenario(allocator, "ambush", 42, &ambush_buf, gate);
    try writer.print("--- scenario ambush ---\n", .{});
    try evidence_format.marker(writer, version_line, ambush_out, version_line);
    try evidence_format.marker(writer, "ambush combat started", ambush_out, "ambush combat started");

    var perm_buf: [65536]u8 = undefined;
    const perm_out = try evidence_format.runScenario(allocator, "permadeath", 42, &perm_buf, gate);
    try writer.print("--- scenario permadeath ---\n", .{});
    try evidence_format.marker(writer, "you are dead (permadeath)", perm_out, "you are dead (permadeath)");
    try evidence_format.marker(writer, "status: dead (permadeath)", perm_out, "status: dead (permadeath)");

    var save_buf: [65536]u8 = undefined;
    const save_out = try evidence_format.runScenario(allocator, "save_v2_roundtrip", 42, &save_buf, gate);
    try writer.print("--- scenario save_v2_roundtrip ---\n", .{});
    try evidence_format.marker(writer, "floor_object corpse", save_out, "floor_object corpse");
    try evidence_format.marker(writer, "poisoned", save_out, "poisoned");
    try evidence_format.marker(writer, "exhaustion=3", save_out, "exhaustion=3");

    var los_buf: [65536]u8 = undefined;
    const los_out = try evidence_format.runScenario(allocator, "los_peek", 42, &los_buf, gate);
    try writer.print("--- scenario los_peek ---\n", .{});
    try evidence_format.marker(writer, "near_goblin", los_out, "near_goblin");
    try evidence_format.markerAbsent(writer, "far_goblin hidden", los_out, "  far_goblin (goblin)");

    var cond_buf: [65536]u8 = undefined;
    const cond_out = try evidence_format.runScenario(allocator, "conditions_brawl", 42, &cond_buf, gate);
    try writer.print("--- scenario conditions_brawl ---\n", .{});
    try evidence_format.marker(writer, "mod=4", cond_out, "mod=4");
    try evidence_format.marker(writer, "conditions: none", cond_out, "conditions: none");

    var ref_header_buf: [64]u8 = undefined;
    const ref_header_line = try version.versionLine(&ref_header_buf, gate.reference_header);
    var ref_buf: [131072]u8 = undefined;
    const ref_out = try evidence_format.runScenario(allocator, "reference_crawl", 42, &ref_buf, gate);
    try writer.print("--- scenario reference_crawl ---\n", .{});
    try evidence_format.marker(writer, ref_header_line, ref_out, ref_header_line);
    try evidence_format.marker(writer, "descended to floor 2", ref_out, "descended to floor 2");
    try evidence_format.marker(writer, "saved slot", ref_out, "saved slot");
}

test "evidence v11 foundation markers" {
    var buf: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(std.testing.allocator, fbs.writer());
    const out = fbs.getWritten();
    try evidence_format.expectMarkerLineTrue(out, "marker ambush combat started: true");
    try evidence_format.expectMarkerLineTrue(out, "marker # version=1.1.0: true");
    try evidence_format.expectMarkerLineTrue(out, "marker you are dead (permadeath): true");
    try evidence_format.expectMarkerLineTrue(out, "marker floor_object corpse: true");
    try evidence_format.expectMarkerLineTrue(out, "marker poisoned: true");
    try evidence_format.expectMarkerLineTrue(out, "marker exhaustion=3: true");
    try evidence_format.expectMarkerLineTrue(out, "marker near_goblin: true");
    try evidence_format.expectMarkerLineTrue(out, "marker far_goblin hidden: true");
}

test "migration v1 to v2 evidence" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try runMigrationEvidence(std.testing.allocator, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "migration schema=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "floor_objects=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "player_dead=false") != null);
}