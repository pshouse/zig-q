//! Emits observable v0.9 generator/descend evidence on the real command path.
const std = @import("std");
const dungeon = @import("dungeon.zig");
const terrain = @import("terrain.zig");
const world = @import("world.zig");
const loc = @import("loc.zig");
const session = @import("session.zig");
const commands = @import("commands.zig");
const evidence_format = @import("evidence_format.zig");

fn countMonsters(w: *world.World) usize {
    var n: usize = 0;
    for (w.store.entities.items) |ent| {
        if (ent.is_monster) n += 1;
    }
    return n;
}

pub fn run(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("=== evidence: seeded floor generator ===\n");

    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    const gen = try dungeon.generateFloor(&map, 42, 2);
    var layout_buf: [256]u8 = undefined;
    const layout_line = try evidence_format.formatLayoutEvidence(&layout_buf, 42, 2, gen);
    try writer.writeAll(layout_line);
    try writer.print(" spawn=({},{})", .{ gen.spawn.x, gen.spawn.y });
    if (gen.stairs_down) |stairs| {
        try writer.print(" stairs=({},{})", .{ stairs.x, stairs.y });
    }
    try writer.writeAll("\n");

    const plan = dungeon.planMonsterSpawns(42, 2, gen.spawn);
    try writer.print("monster_plan_count={}\n", .{plan.count});
    var i: usize = 0;
    while (i < plan.count) : (i += 1) {
        try writer.print("monster_plan[{}]={s} at ({},{})\n", .{
            i,
            plan.spawns[i].name,
            plan.spawns[i].position.x,
            plan.spawns[i].position.y,
        });
    }

    try writer.writeAll("=== evidence: descend execute path ===\n");

    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    var draft: session.CreationDraft = .{};

    var ctx = commands.Context{
        .allocator = allocator,
        .w = &w,
        .draft = &draft,
    };
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);
    _ = try commands.execute(&ctx, .spawn, writer);
    var step: usize = 0;
    while (step < 4) : (step += 1) {
        _ = try commands.execute(&ctx, commands.parseLine("move east"), writer);
    }
    const ent = w.store.get(ctx.player_id) orelse return error.EntityNotFound;
    try writer.print("pre_descend floor_index={} player_at=({},{}) spawn=(49,49)\n", .{
        w.floor_index,
        ent.loc.x,
        ent.loc.y,
    });

    _ = try commands.execute(&ctx, .descend, writer);
    _ = try commands.execute(&ctx, .look, writer);

    var verify_map = terrain.TerrainMap.init(allocator);
    defer verify_map.deinit();
    const regen = try dungeon.generateFloor(&verify_map, 42, w.floor_index);
    var descend_buf: [256]u8 = undefined;
    const descend_line = try evidence_format.formatDescendEvidence(
        &descend_buf,
        w.floor_index,
        regen.layout_hash,
        regen.walkable_count,
        countMonsters(&w),
    );
    try writer.writeAll(descend_line);
    try writer.writeAll("\n");
}

test "evidence v09 generator and descend output" {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try run(std.testing.allocator, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "layout_hash=") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "walkable_count=") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "post_descend floor_index=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "look floor=2") != null);
}