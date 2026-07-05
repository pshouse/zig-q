const std = @import("std");
const loc = @import("loc.zig");
const world = @import("world.zig");
const entity = @import("entity.zig");
const terrain = @import("terrain.zig");


pub fn renderViewport(w: *const world.World, center: loc.Loc, radius: u8, writer: anytype) !void {
    const r0 = center.x;
    const c0 = center.y;
    const r_extent = @as(u64, radius);
    const c_extent = @as(u64, radius);

    var r: u64 = 0;
    while (r < r_extent * 2 + 1) : (r += 1) {
        var c: u64 = 0;
        while (c < c_extent * 2 + 1) : (c += 1) {
            const tile = loc.Loc.init(r0 -% r_extent +% r, c0 -% c_extent +% c);
            const count = w.tile_map.entityCountAt(tile);
            if (tile.x == center.x and tile.y == center.y) {
                try writer.print("@", .{});
            } else if (w.has_dungeon) {
                const t = w.terrain.get(tile) orelse terrain.Tile.floor;
                if (t == .wall or t == .door or t == .stairs) {
                    try writer.print("{c}", .{t.renderChar()});
                } else if (count > 0) {
                    try writer.print("*", .{});
                } else {
                    try writer.print(".", .{});
                }
            } else if (count > 0) {
                try writer.print("#", .{});
            } else {
                try writer.print(".", .{});
            }
        }
        try writer.print("\n", .{});
    }
}

fn inViewport(center: loc.Loc, radius: u8, position: loc.Loc) bool {
    const r_extent = @as(u64, radius);
    const dx = @as(i64, @intCast(center.x)) - @as(i64, @intCast(position.x));
    const dy = @as(i64, @intCast(center.y)) - @as(i64, @intCast(position.y));
    const adx: u64 = @intCast(if (dx < 0) -dx else dx);
    const ady: u64 = @intCast(if (dy < 0) -dy else dy);
    return adx <= r_extent and ady <= r_extent;
}

fn tileDistance(a: loc.Loc, b: loc.Loc) u64 {
    const dx = @as(i64, @intCast(a.x)) - @as(i64, @intCast(b.x));
    const dy = @as(i64, @intCast(a.y)) - @as(i64, @intCast(b.y));
    const adx: u64 = @intCast(if (dx < 0) -dx else dx);
    const ady: u64 = @intCast(if (dy < 0) -dy else dy);
    return adx + ady;
}

pub fn formatVisibleEntities(
    w: *const world.World,
    viewer_id: entity.EntityId,
    center: loc.Loc,
    radius: u8,
    writer: anytype,
) !void {
    var listed = false;
    for (w.store.entities.items) |ent| {
        if (ent.id == viewer_id) continue;
        if (ent.current_hp == 0 or ent.conditions.has(.dead)) continue;
        if (!inViewport(center, radius, ent.loc)) continue;
        if (!listed) {
            try writer.writeAll("visible:\n");
            listed = true;
        }
        const dist = tileDistance(center, ent.loc);
        try writer.print("  {s} ({s}) at ({},{}) distance={}\n", .{
            ent.name,
            ent.char.name,
            ent.loc.x,
            ent.loc.y,
            dist,
        });
    }
}

pub fn renderLook(
    w: *const world.World,
    player_id: entity.EntityId,
    list_nearby: bool,
    writer: anytype,
) !void {
    const ent = w.store.get(player_id) orelse return error.EntityNotFound;
    if (ent.conditions.has(.blinded)) {
        try writer.print("You cannot see in this condition.\n", .{});
        return;
    }
    if (w.has_dungeon) {
        try writer.print("look floor={} center=({},{}) radius=5\n", .{
            w.floor_index,
            ent.loc.x,
            ent.loc.y,
        });
    } else {
        try writer.print("look center=({},{}) radius=5\n", .{ ent.loc.x, ent.loc.y });
    }
    try renderViewport(w, ent.loc, 5, writer);
    if (list_nearby) try formatVisibleEntities(w, player_id, ent.loc, 5, writer);
}

test "center tile shows @ even when entity is present" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 1);
    defer w.deinit();

    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    _ = id;

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderViewport(&w, loc.Loc.init(49, 49), 1, fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "@") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "#") == null);
}

test "dungeon look shows walls" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 1);
    defer w.deinit();
    try w.loadFloor(1);
    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderLook(&w, id, false, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "look floor=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "#") != null);
}

test "look lists visible entity names when enabled" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    _ = try w.spawnMonster(@import("monsters.zig").Kind.goblin, loc.Loc.init(50, 49), "goblin_0");

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderLook(&w, id, true, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "visible:\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "goblin_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "(goblin)") != null);
}