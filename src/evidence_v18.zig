//! v1.8 Character rework evidence markers (docs/CHARACTER_REWORK.md Phase 5).
const std = @import("std");
const version = @import("version.zig");
const evidence_format = @import("evidence_format.zig");

pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    const gate = version.forGate(18).?;
    try writer.print("=== evidence: v1.8 character rework (version={s}) ===\n", .{gate.emit});

    var version_line_buf: [64]u8 = undefined;
    const version_line = try version.versionLine(&version_line_buf, gate.emit);

    // Phase 1: rogue finesse — light weapon routes to-hit through DEX (mod=4 at DEX 18).
    var finesse_buf: [65536]u8 = undefined;
    const finesse_out = try evidence_format.runScenario(allocator, "rogue_finesse", 42, &finesse_buf, gate);
    try writer.print("--- scenario rogue_finesse ---\n", .{});
    try evidence_format.marker(writer, version_line, finesse_out, version_line);
    try evidence_format.marker(writer, "rogue finesse DEX mod=4", finesse_out, "mod=4");
    try evidence_format.marker(writer, "rogue heavy reverts STR mod=0", finesse_out, "mod=0");
    try evidence_format.marker(writer, "equipped short sword", finesse_out, "equipped short sword");

    // Phase 1: reckless — advantage toggle + −4 AC until next turn.
    var reckless_buf: [65536]u8 = undefined;
    const reckless_out = try evidence_format.runScenario(allocator, "reckless", 42, &reckless_buf, gate);
    try writer.print("--- scenario reckless ---\n", .{});
    try evidence_format.marker(writer, "reckless on", reckless_out, "reckless on");
    try evidence_format.marker(writer, "reckless AC -4 (vs AC 6)", reckless_out, "vs AC 6");
    try evidence_format.marker(writer, "reckless clears (vs AC 10)", reckless_out, "vs AC 10");

    // Phase 1: fighter guard + discipline/second wind (class specials).
    var guard_buf: [65536]u8 = undefined;
    const guard_out = try evidence_format.runScenario(allocator, "guard", 42, &guard_buf, gate);
    try writer.print("--- scenario guard ---\n", .{});
    try evidence_format.marker(writer, "raises guard (+2 AC)", guard_out, "raises guard (+2 AC)");

    var discipline_buf: [65536]u8 = undefined;
    const discipline_out = try evidence_format.runScenario(allocator, "discipline_second_wind", 42, &discipline_buf, gate);
    try writer.print("--- scenario discipline_second_wind ---\n", .{});
    try evidence_format.marker(writer, "second wind: healed", discipline_out, "second wind: healed");

    // Phase 2: human race +2 INT; elf deep-floor speed suppresses extra move ticks.
    var human_buf: [65536]u8 = undefined;
    const human_out = try evidence_format.runScenario(allocator, "human_create", 42, &human_buf, gate);
    try writer.print("--- scenario human_create ---\n", .{});
    try evidence_format.marker(writer, "race=human", human_out, "race=human");
    try evidence_format.marker(writer, "human +2 INT (INT: 14)", human_out, "INT: 14");

    var elf_buf: [65536]u8 = undefined;
    const elf_out = try evidence_format.runScenario(allocator, "elf_speed_deepfloor", 42, &elf_buf, gate);
    try writer.print("--- scenario elf_speed_deepfloor ---\n", .{});
    try evidence_format.marker(writer, "race=elf", elf_out, "race=elf");
    // Four deep-floor moves cost 4 ticks (fast race suppresses danger-floor extra tick).
    try evidence_format.marker(writer, "elf deep-floor ticks=4", elf_out, "ticks=4");

    // Phase 3: INT disarm/pick; CHA intimidate → frightened flee (no attack).
    var disarm_buf: [65536]u8 = undefined;
    const disarm_out = try evidence_format.runScenario(allocator, "disarm_pick", 42, &disarm_buf, gate);
    try writer.print("--- scenario disarm_pick ---\n", .{});
    try evidence_format.marker(writer, "disarmed trap", disarm_out, "disarmed trap");
    try evidence_format.marker(writer, "picked lock", disarm_out, "picked lock");

    var intimidate_buf: [65536]u8 = undefined;
    const intimidate_out = try evidence_format.runScenario(allocator, "intimidate_flee", 42, &intimidate_buf, gate);
    try writer.print("--- scenario intimidate_flee ---\n", .{});
    try evidence_format.marker(writer, "is frightened", intimidate_out, "is frightened");
    try evidence_format.marker(writer, "frightened flees", intimidate_out, "flees to");
    // After fright, monster must not attack on that turn.
    const fright_pos = std.mem.indexOf(u8, intimidate_out, "is frightened");
    const no_attack_while_frightened = if (fright_pos) |p|
        std.mem.indexOf(u8, intimidate_out[p..], "attack goblin_0->entity_0") == null
    else
        false;
    try writer.print("marker frightened_no_attack: {}\n", .{no_attack_while_frightened});

    // Phase 4: sneak → hidden; backstab extra die.
    var sneak_buf: [65536]u8 = undefined;
    const sneak_out = try evidence_format.runScenario(allocator, "sneak_hidden", 42, &sneak_buf, gate);
    try writer.print("--- scenario sneak_hidden ---\n", .{});
    try evidence_format.marker(writer, "you are hidden", sneak_out, "you are hidden");

    var backstab_buf: [131072]u8 = undefined;
    const backstab_out = try evidence_format.runScenario(allocator, "rogue_backstab", 42, &backstab_buf, gate);
    try writer.print("--- scenario rogue_backstab ---\n", .{});
    try evidence_format.marker(writer, "backstab extra die", backstab_out, "backstab +");
}

test "evidence v18 character rework markers" {
    const allocator = std.testing.allocator;
    var buf: [262144]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(allocator, fbs.writer());
    const out = fbs.getWritten();
    try evidence_format.expectMarkerLineTrue(out, "marker rogue finesse DEX mod=4: true");
    try evidence_format.expectMarkerLineTrue(out, "marker reckless on: true");
    try evidence_format.expectMarkerLineTrue(out, "marker reckless AC -4 (vs AC 6): true");
    try evidence_format.expectMarkerLineTrue(out, "marker disarmed trap: true");
    try evidence_format.expectMarkerLineTrue(out, "marker picked lock: true");
    try evidence_format.expectMarkerLineTrue(out, "marker is frightened: true");
    try evidence_format.expectMarkerLineTrue(out, "marker frightened_no_attack: true");
    try evidence_format.expectMarkerLineTrue(out, "marker you are hidden: true");
    try evidence_format.expectMarkerLineTrue(out, "marker backstab extra die: true");
    try evidence_format.expectMarkerLineTrue(out, "marker race=human: true");
    try evidence_format.expectMarkerLineTrue(out, "marker human +2 INT (INT: 14): true");
    try evidence_format.expectMarkerLineTrue(out, "marker elf deep-floor ticks=4: true");
}
