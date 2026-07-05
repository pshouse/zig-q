//! Emits observable v0.7 combat evidence on the real command path (for verification capture).
const std = @import("std");
const world = @import("world.zig");
const loc = @import("loc.zig");
const session = @import("session.zig");
const commands = @import("commands.zig");
pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("=== evidence: melee math (execute attack) ===\n");
    try meleeEvidence(allocator, writer);

    try writer.writeAll("=== evidence: turn transition (execute end turn) ===\n");
    try turnEvidence(allocator, writer);

    try writer.writeAll("=== evidence: prone modifier (execute attack) ===\n");
    try proneEvidence(allocator, writer);

    try writer.writeAll("=== evidence: blinded attacker (execute attack) ===\n");
    try blindedEvidence(allocator, writer);

    try writer.writeAll("=== evidence: monster spawn and fight ===\n");
    try monsterEvidence(allocator, writer);

    try writer.writeAll("=== evidence: v0.6 stats HP format ===\n");
    try statsEvidence(allocator, writer);
}

fn meleeEvidence(allocator: std.mem.Allocator, writer: anytype) !void {
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    var ctx = try combatCtx(allocator, &w);
    _ = try commands.execute(&ctx, commands.parseLine("attack goblin_0"), writer);
}

fn turnEvidence(allocator: std.mem.Allocator, writer: anytype) !void {
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    var ctx = try combatCtx(allocator, &w);
    _ = try commands.execute(&ctx, commands.parseLine("attack goblin_0"), std.io.null_writer);
    _ = try commands.execute(&ctx, commands.parseLine("end turn"), writer);
}

fn proneEvidence(allocator: std.mem.Allocator, writer: anytype) !void {
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    var ctx = try combatCtx(allocator, &w);
    for (w.store.get(ctx.player_id).?.char.attributes.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "STR")) attr.stat = 14;
    }
    const goblin_id = monsterId(&w);
    w.store.get(goblin_id).?.conditions.add(.prone);
    _ = try commands.execute(&ctx, commands.parseLine("attack goblin_0"), writer);
}

fn blindedEvidence(allocator: std.mem.Allocator, writer: anytype) !void {
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    var ctx = try combatCtx(allocator, &w);
    w.store.get(ctx.player_id).?.conditions.add(.blinded);
    const offset_before = w.rng.offset;
    _ = try commands.execute(&ctx, commands.parseLine("attack goblin_0"), writer);
    try writer.print("blinded_rng_rolls={}\n", .{w.rng.offset - offset_before});
}

fn monsterEvidence(allocator: std.mem.Allocator, writer: anytype) !void {
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    const skel_id = try w.spawnMonster(.skeleton, loc.Loc.init(50, 49), "skeleton_0");
    try writer.print("spawn_monster id={} kind=skeleton at (50,49)\n", .{skel_id});
    var ctx = try combatCtx(allocator, &w);
    _ = try commands.execute(&ctx, commands.parseLine("attack skeleton_0"), writer);
}

fn statsEvidence(allocator: std.mem.Allocator, writer: anytype) !void {
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);
    var ctx = commands.Context{ .allocator = allocator, .w = &w, .draft = &draft };
    _ = try commands.execute(&ctx, .spawn, std.io.null_writer);
    _ = try commands.execute(&ctx, .stats, writer);
}

fn combatCtx(allocator: std.mem.Allocator, w: *world.World) !commands.Context {
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    _ = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");
    return .{
        .allocator = allocator,
        .w = w,
        .draft = &draft,
        .player_id = player_id,
    };
}

fn monsterId(w: *const world.World) u32 {
    for (w.store.entities.items) |ent| {
        if (ent.is_monster) return ent.id;
    }
    unreachable;
}

test "evidence run produces combat and stats lines" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(std.testing.allocator, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "attack ") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "roll=") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "turn:") != null or std.mem.indexOf(u8, out, "goblin_0->") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "mod=4") != null);
    const blinded_line = std.mem.indexOf(u8, out, "blinded_rng_rolls=") orelse return error.TestExpectedEqual;
    const rolls_start = blinded_line + "blinded_rng_rolls=".len;
    const rolls_end = std.mem.indexOfScalar(u8, out[rolls_start..], '\n') orelse out.len - rolls_start;
    const rolls = std.fmt.parseInt(u16, out[rolls_start .. rolls_start + rolls_end], 10) catch return error.TestExpectedEqual;
    try std.testing.expect(rolls >= 2);
    try std.testing.expect(std.mem.indexOf(u8, out, "spawn_monster") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "vs AC 13") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "HP: ") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "HP: 13") != null);
    const stats_hdr = std.mem.indexOf(u8, out, "=== evidence: v0.6 stats HP format ===") orelse return error.TestExpectedEqual;
    const stats = out[stats_hdr..];
    const hp_line = std.mem.indexOf(u8, stats, "HP: 13") orelse return error.TestExpectedEqual;
    const line_end = std.mem.indexOfScalar(u8, stats[hp_line..], '\n') orelse stats.len - hp_line;
    const hp_slice = stats[hp_line .. hp_line + line_end];
    try std.testing.expect(std.mem.indexOf(u8, hp_slice, "/") == null);
}