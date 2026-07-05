//! Integration tests that import only the public `zig_q` module surface.
const std = @import("std");
const zig_q = @import("zig_q");

fn stagePlayer(allocator: std.mem.Allocator, w: *zig_q.world.World) !zig_q.entity.EntityId {
    const boot = try zig_q.session.bootstrapCharacter(allocator, w, "George");
    w.stageCharacter(boot.character);
    return w.spawnStagedPlayer(zig_q.dungeon.floor1_spawn, "entity_0");
}

test "consumer world init spawn deinit" {
    const allocator = std.testing.allocator;
    var w = try zig_q.world.World.init(allocator, 42);
    defer w.deinit();

    try w.loadFloor(1);
    _ = try stagePlayer(allocator, &w);
    const snap = w.snapshot();
    try std.testing.expectEqual(@as(u32, 1), snap.floor_index);
    try std.testing.expectEqual(@as(usize, 1), snap.entity_count);
}

test "consumer multi-floor descend" {
    const allocator = std.testing.allocator;
    var w = try zig_q.world.World.init(allocator, 42);
    defer w.deinit();

    try w.loadFloor(1);
    const id = try stagePlayer(allocator, &w);
    _ = try zig_q.dungeon.walkSpawnToFloor1Stairs(&w, id);
    try w.descend(id);

    const snap = w.snapshot();
    try std.testing.expectEqual(@as(u32, 2), snap.floor_index);
    try std.testing.expect(snap.entity_count > 1);
}

test "consumer combat attack" {
    const allocator = std.testing.allocator;
    var w = try zig_q.world.World.init(allocator, 42);
    defer w.deinit();

    try w.loadFloor(1);
    const player = try stagePlayer(allocator, &w);
    _ = try w.spawnMonster(.goblin, zig_q.loc.Loc.init(50, 49), "goblin_0");

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try zig_q.combat.attack(&w, player, "goblin_0", fbs.writer());
    try std.testing.expect(zig_q.combat.isInCombat(&w));
}

test "consumer sqlite save load roundtrip" {
    const allocator = std.testing.allocator;
    const path = "zig-q-consumer-test.sqlite";
    zig_q.sqlite_store.deleteDb(path);
    defer zig_q.sqlite_store.deleteDb(path);

    var w = try zig_q.world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    const player = try stagePlayer(allocator, &w);
    _ = try zig_q.movement.moveEntity(&w, player, .east);

    try zig_q.sqlite_store.saveSlot(allocator, path, 1, &w, player, std.io.null_writer);
    const loaded = try zig_q.sqlite_store.loadSlot(allocator, path, 1, std.io.null_writer);
    var loaded_world = loaded.world;
    defer loaded_world.deinit();

    const snap = loaded_world.snapshot();
    try std.testing.expectEqual(@as(u32, 1), snap.floor_index);
    try std.testing.expectEqual(@as(u64, 42), snap.seed);
    try std.testing.expectEqual(@as(usize, 1), snap.entity_count);
}