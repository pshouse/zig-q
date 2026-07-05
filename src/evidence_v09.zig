//! Emits observable v0.9 generator/descend evidence on the real command path.
const std = @import("std");
const dungeon = @import("dungeon.zig");
const terrain = @import("terrain.zig");
const world = @import("world.zig");
const loc = @import("loc.zig");
const session = @import("session.zig");
const commands = @import("commands.zig");

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
    try writer.print("floor_index=2 seed=42 layout_hash={} walkable_count={} spawn=({},{})", .{
        gen.layout_hash,
        gen.walkable_count,
        gen.spawn.x,
        gen.spawn.y,
    });
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
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);

    const char = try session.draftBuildCharacter(allocator, &w, &draft, "George");
    w.stageCharacter(char);
    const door = loc.Loc.init(49, 53);

    var ctx = commands.Context{
        .allocator = allocator,
        .w = &w,
        .draft = &draft,
    };
    ctx.player_id = try w.spawnStagedPlayer(door, "entity_0");
    try writer.print("pre_descend floor_index={} player_at=({},{})\n", .{
        w.floor_index,
        door.x,
        door.y,
    });

    _ = try commands.execute(&ctx, .descend, writer);
    _ = try commands.execute(&ctx, .look, writer);

    var verify_map = terrain.TerrainMap.init(allocator);
    defer verify_map.deinit();
    const regen = try dungeon.generateFloor(&verify_map, 42, w.floor_index);
    try writer.print("post_descend floor_index={} layout_hash={} walkable_count={} monsters={}\n", .{
        w.floor_index,
        regen.layout_hash,
        regen.walkable_count,
        countMonsters(&w),
    });
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