//! Emits observable v1.6 depth-danger evidence on the real command path.
const std = @import("std");
const version = @import("version.zig");
const evidence_format = @import("evidence_format.zig");
const save_state = @import("save_state.zig");

pub fn runMigrationEvidence(allocator: std.mem.Allocator, writer: anytype) !void {
    _ = allocator;
    const ent = save_state.EntitySave{
        .id = 0,
        .name = "goblin_0",
        .x = 50,
        .y = 49,
        .movement = 30,
        .char_name = "goblin",
        .race_name = "monster",
        .class_name = "monster",
        .status = .exploring,
        .str = 8,
        .dex = 14,
        .con = 10,
        .int_stat = 10,
        .wis = 10,
        .cha = 10,
        .conditions_bits = 0,
        .current_hp = 10,
        .max_hp = 10,
        .damage_die = 6,
        .is_monster = true,
        .danger_tier = 2,
    };
    var entities = [_]save_state.EntitySave{ent};
    var save = save_state.WorldSave{
        .schema_version = save_state.schema_version_v3,
        .seed = 42,
        .rng_state = 1,
        .rng_offset = 0,
        .floor_index = 4,
        .has_dungeon = true,
        .clock_ticks = 0,
        .clock_time_of_day = 0,
        .clock_seconds_per_day = 120,
        .clock_update_rate = 5,
        .clock_time_multiplier = 1,
        .next_entity_id = 1,
        .player_id = 0,
        .entities = entities[0..],
        .map_cells = &.{},
        .combat = null,
    };
    save_state.migrateV3ToV4(&save);
    try writer.print("migration_v4 schema={} danger_tier={}\n", .{
        save.schema_version,
        save.entities[0].danger_tier,
    });
}

pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    const gate = version.forGate(16);
    try writer.print("=== evidence: v1.6 depth danger (version={s}) ===\n", .{gate.emit});

    var version_line_buf: [64]u8 = undefined;
    const version_line = try version.versionLine(&version_line_buf, gate.emit);

    var deadly_buf: [65536]u8 = undefined;
    const deadly_out = try evidence_format.runScenario(allocator, "deadly_floor", 42, &deadly_buf, gate);
    try writer.print("--- scenario deadly_floor ---\n", .{});
    try evidence_format.marker(writer, version_line, deadly_out, version_line);
    try evidence_format.marker(writer, "attack goblin_0->entity_0", deadly_out, "attack goblin_0->entity_0");
    try evidence_format.marker(writer, "mod=0", deadly_out, "mod=0");
    try evidence_format.marker(writer, "flees from combat", deadly_out, "flees from combat");

    var elite_buf: [65536]u8 = undefined;
    const elite_out = try evidence_format.runScenario(allocator, "elite_brawl", 42, &elite_buf, gate);
    try writer.print("--- scenario elite_brawl ---\n", .{});
    try evidence_format.marker(writer, "hobgoblin", elite_out, "hobgoblin");
    try evidence_format.marker(writer, "vs AC 17", elite_out, "vs AC 17");

    var scarce_buf: [65536]u8 = undefined;
    const scarce_out = try evidence_format.runScenario(allocator, "scarce_heals", 42, &scarce_buf, gate);
    try writer.print("--- scenario scarce_heals ---\n", .{});
    try evidence_format.marker(writer, "plan_bandages=1", scarce_out, "plan_bandages=1");
    try evidence_format.marker(writer, "depth_report floor=5 plan_monsters=5", scarce_out, "depth_report floor=5 plan_monsters=5");

    var save_buf: [131072]u8 = undefined;
    const save_out = try evidence_format.runScenario(allocator, "save_v4_roundtrip", 42, &save_buf, gate);
    try writer.print("--- scenario save_v4_roundtrip ---\n", .{});
    try evidence_format.marker(writer, "saved slot", save_out, "saved slot");
    try evidence_format.marker(writer, "loaded slot", save_out, "loaded slot");
    try evidence_format.marker(writer, "step report_danger goblin_0 danger_tier=1", save_out, "step report_danger goblin_0 danger_tier=1");

    try runMigrationEvidence(allocator, writer);

    var ref_header_buf: [64]u8 = undefined;
    const ref_header_line = try version.versionLine(&ref_header_buf, gate.reference_header);
    var ref_buf: [131072]u8 = undefined;
    const ref_out = try evidence_format.runScenario(allocator, "reference_crawl", 42, &ref_buf, gate);
    try writer.print("--- scenario reference_crawl ---\n", .{});
    try evidence_format.marker(writer, ref_header_line, ref_out, ref_header_line);
    try evidence_format.marker(writer, "descended to floor 2", ref_out, "descended to floor 2");
}

test "evidence v16 depth danger markers" {
    var buf: [65536]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(std.testing.allocator, fbs.writer());
    const out = fbs.getWritten();
    try evidence_format.expectMarkerLineTrue(out, "marker # version=1.6.0: true");
    try evidence_format.expectMarkerLineTrue(out, "marker # version=1.1.0: true");
    try evidence_format.expectMarkerLineTrue(out, "marker attack goblin_0->entity_0: true");
    try evidence_format.expectMarkerLineTrue(out, "marker mod=0: true");
    try evidence_format.expectMarkerLineTrue(out, "marker flees from combat: true");
    try evidence_format.expectMarkerLineTrue(out, "marker hobgoblin: true");
    try evidence_format.expectMarkerLineTrue(out, "marker vs AC 17: true");
    try evidence_format.expectMarkerLineTrue(out, "marker step report_danger goblin_0 danger_tier=1: true");
    try std.testing.expect(std.mem.indexOf(u8, out, "migration_v4 schema=4 danger_tier=0") != null);
}
