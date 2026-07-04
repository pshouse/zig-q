const std = @import("std");
const loc = @import("loc.zig");
const world = @import("world.zig");
const entity = @import("entity.zig");

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
            if (count > 0) {
                try writer.print("#", .{});
            } else if (tile.x == center.x and tile.y == center.y) {
                try writer.print("@", .{});
            } else {
                try writer.print(".", .{});
            }
        }
        try writer.print("\n", .{});
    }
}

pub fn renderLook(w: *world.World, player_id: entity.EntityId, writer: anytype) !void {
    const ent = w.store.get(player_id) orelse return error.EntityNotFound;
    if (ent.conditions.has(.blinded)) {
        try writer.print("You cannot see in this condition.\n", .{});
        return;
    }
    try writer.print("look center=({},{}) radius=5\n", .{ ent.loc.x, ent.loc.y });
    try renderViewport(w, ent.loc, 5, writer);
    w.tick();
}