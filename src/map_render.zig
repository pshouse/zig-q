const std = @import("std");
const loc = @import("loc.zig");
const world = @import("world.zig");
const entity = @import("entity.zig");
const terrain = @import("terrain.zig");
const conditions = @import("conditions.zig");
const perception = @import("perception.zig");

const DescendTile = struct {
    pos: loc.Loc,
    tile: terrain.Tile,
};

fn findDescendTile(w: *const world.World) ?DescendTile {
    var it = w.terrain.tiles.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.isDescendTrigger()) {
            return .{ .pos = entry.key_ptr.*, .tile = entry.value_ptr.* };
        }
    }
    return null;
}

fn descendLabel(tile: terrain.Tile) []const u8 {
    return switch (tile) {
        .stairs => "stairs down",
        .door => "descend door",
        else => "descend tile",
    };
}

fn formatRelativeDir(from: loc.Loc, to: loc.Loc, writer: anytype) !void {
    const dx: i64 = @as(i64, @intCast(to.x)) - @as(i64, @intCast(from.x));
    const dy: i64 = @as(i64, @intCast(to.y)) - @as(i64, @intCast(from.y));
    if (dx == 0 and dy == 0) return;
    try writer.writeAll(" toward ");
    if (dx < 0) try writer.writeAll("north");
    if (dx > 0) {
        if (dx < 0) try writer.writeAll("-");
        try writer.writeAll("south");
    }
    if (dy != 0 and dx != 0) try writer.writeAll("-");
    if (dy < 0) try writer.writeAll("west");
    if (dy > 0) try writer.writeAll("east");
}

pub fn formatDescendHint(
    w: *const world.World,
    center: loc.Loc,
    radius: u8,
    writer: anytype,
) !void {
    const trigger = findDescendTile(w) orelse return;
    const label = descendLabel(trigger.tile);
    try writer.writeAll("descend:\n");
    if (center.x == trigger.pos.x and center.y == trigger.pos.y) {
        try writer.print("  you are on {s} (descend)\n", .{label});
        return;
    }
    const dist = tileDistance(center, trigger.pos);
    const in_view = inViewport(center, radius, trigger.pos);
    const has_los = !w.has_dungeon or perception.hasLineOfSight(&w.terrain, center, trigger.pos);
    if (in_view and has_los) {
        try writer.print("  {s} at ({},{}) distance={} (descend)\n", .{
            label, trigger.pos.x, trigger.pos.y, dist,
        });
    } else {
        try writer.print("  {s} at ({},{}) distance={}", .{
            label, trigger.pos.x, trigger.pos.y, dist,
        });
        try formatRelativeDir(center, trigger.pos, writer);
        try writer.writeAll(" (not in sight)\n");
    }
}


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

pub fn formatVisibleFloorObjects(
    w: *const world.World,
    center: loc.Loc,
    radius: u8,
    writer: anytype,
) !void {
    const items_mod = @import("items.zig");
    var listed = false;
    for (w.floor_objects.objects.items) |obj| {
        const pos = loc.Loc.init(obj.x, obj.y);
        if (!inViewport(center, radius, pos)) continue;
        if (!listed) {
            try writer.writeAll("nearby:\n");
            listed = true;
        }
        switch (obj.kind) {
            .item => {
                const name = if (obj.item) |id| items_mod.def(id).name else obj.label;
                try writer.print("  {s} at ({},{}) (get {s})\n", .{ name, obj.x, obj.y, name });
            },
            .corpse => {
                if (obj.item) |id| {
                    const loot_name = items_mod.def(id).name;
                    try writer.print("  corpse {s} at ({},{}) holds {s} (get from corpse)\n", .{
                        obj.label, obj.x, obj.y, loot_name,
                    });
                } else {
                    try writer.print("  corpse {s} at ({},{})\n", .{ obj.label, obj.x, obj.y });
                }
            },
            .trap => try writer.print("  trap at ({},{})\n", .{ obj.x, obj.y }),
        }
    }
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
        if (conditions.isDead(&ent)) continue;
        if (!inViewport(center, radius, ent.loc)) continue;
        if (w.has_dungeon and !perception.hasLineOfSight(&w.terrain, center, ent.loc)) continue;
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
    if (conditions.blocksLook(ent)) {
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
    const radius: u8 = 5;
    try renderViewport(w, ent.loc, radius, writer);
    if (w.has_dungeon) try formatDescendHint(w, ent.loc, radius, writer);
    if (list_nearby) {
        try formatVisibleFloorObjects(w, ent.loc, radius, writer);
        try formatVisibleEntities(w, player_id, ent.loc, radius, writer);
    }
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

test "look lists nearby floor items when enabled" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    try w.floor_objects.addItem(allocator, .item, loc.Loc.init(49, 50), "bandage", @import("items.zig").Id.bandage);

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderLook(&w, id, true, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "nearby:\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "bandage") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "(get bandage)") != null);
}

test "look hints at floor 1 stairs" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderLook(&w, id, false, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "descend:\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "stairs down") != null);
}

test "look reports standing on stairs" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    const stairs = @import("dungeon.zig").floor1_stairs_v09;
    const id = try w.spawnTestPlayer(stairs);

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderLook(&w, id, false, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "you are on stairs down") != null);
}

test "look hints at procedural floor stairs when out of sight" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(5);
    const id = try w.spawnTestPlayer(loc.Loc.init(49, 42));

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderLook(&w, id, false, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "descend:\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "stairs down at (") != null);
    try std.testing.expect(
        std.mem.indexOf(u8, out, "(not in sight)") != null or
            std.mem.indexOf(u8, out, "(descend)") != null,
    );
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