const std = @import("std");
const loc = @import("loc.zig");
const world = @import("world.zig");
const session = @import("session.zig");
const map_render = @import("map_render.zig");

pub const DemoResult = struct {
    player_id: u32,
    pool: session.StatPool,
};

pub fn runDemo(allocator: std.mem.Allocator, seed: u64, writer: anytype) !DemoResult {
    var w = try world.World.init(allocator, seed);
    defer w.deinit();

    try writer.print("zig-q demo seed={}\n", .{seed});

    const boot = try session.bootstrapCharacter(allocator, &w, "George");
    try session.formatStatPool(boot.pool, writer);

    const start = loc.Loc.init(49, 49);
    const player_id = try w.spawnPlayer(boot.character, start, "entity_0");
    try writer.print("spawn player_id={} at ({},{}) race={s} class={s}\n", .{
        player_id,
        start.x,
        start.y,
        w.store.get(player_id).?.char.race.name,
        w.store.get(player_id).?.char.class.name,
    });

    if (w.store.get(player_id)) |ent| {
        ent.conditions.add(.prone);
        ent.conditions.add(.blinded);
    }

    var t: u32 = 0;
    while (t < 3) : (t += 1) {
        w.tick();
    }
    try writer.print("clock ticks={} time_of_day={d:.4}\n", .{ w.game_clock.ticks, w.game_clock.time_of_day });

    try writer.print("map viewport:\n", .{});
    try map_render.renderViewport(&w, start, 5, writer);

    try map_render.renderLook(&w, player_id, true, writer);

    const snap = w.snapshot();
    try writer.print("snapshot entities={} cells={} rng_offset={}\n", .{
        snap.entity_count,
        snap.occupied_cells,
        snap.rng_offset,
    });

    return .{ .player_id = player_id, .pool = boot.pool };
}