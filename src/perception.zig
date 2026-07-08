//! Line-of-sight on the cardinal grid (Bresenham) and trap spotting checks.
const std = @import("std");
const loc = @import("loc.zig");
const terrain = @import("terrain.zig");
const rng = @import("rng.zig");

/// Base DC to spot a trap at distance 0; +1 per tile of Manhattan distance.
pub const trap_spot_dc_base: i32 = 12;

fn tileBlocksLos(map: *const terrain.TerrainMap, at: loc.Loc) bool {
    if (map.get(at)) |tile| return tile == .wall;
    return false;
}

pub fn hasLineOfSight(map: *const terrain.TerrainMap, from: loc.Loc, to: loc.Loc) bool {
    if (from.x == to.x and from.y == to.y) return true;

    if (from.x == to.x) {
        const y0: i64 = @intCast(from.y);
        const y1: i64 = @intCast(to.y);
        const step: i64 = if (y0 < y1) 1 else -1;
        var y = y0 + step;
        while (y != y1) : (y += step) {
            if (tileBlocksLos(map, loc.Loc.init(from.x, @intCast(y)))) return false;
        }
        return true;
    }
    if (from.y == to.y) {
        const x0: i64 = @intCast(from.x);
        const x1: i64 = @intCast(to.x);
        const step: i64 = if (x0 < x1) 1 else -1;
        var x = x0 + step;
        while (x != x1) : (x += step) {
            if (tileBlocksLos(map, loc.Loc.init(@intCast(x), from.y))) return false;
        }
        return true;
    }

    var x0: i64 = @intCast(from.x);
    var y0: i64 = @intCast(from.y);
    const x1: i64 = @intCast(to.x);
    const y1: i64 = @intCast(to.y);

    const dx: i64 = @intCast(@abs(x1 - x0));
    const dy: i64 = @intCast(@abs(y1 - y0));
    const sx: i64 = if (x0 < x1) 1 else -1;
    const sy: i64 = if (y0 < y1) 1 else -1;
    var err: i64 = if (dx > dy) @divTrunc(dx, 2) else -@divTrunc(dy, 2);

    while (true) {
        if (x0 == x1 and y0 == y1) return true;
        const at = loc.Loc.init(@intCast(x0), @intCast(y0));
        if (!(at.x == from.x and at.y == from.y)) {
            if (tileBlocksLos(map, at)) return false;
        }
        if (x0 == x1 and y0 == y1) break;
        const e2 = err * 2;
        if (e2 > -dy) {
            err -= dy;
            x0 += sx;
        }
        if (e2 < dx) {
            err += dx;
            y0 += sy;
        }
    }
    return true;
}

pub fn inRadius(center: loc.Loc, target: loc.Loc, radius: u8) bool {
    const r_extent = @as(u64, radius);
    const dx = @as(i64, @intCast(center.x)) - @as(i64, @intCast(target.x));
    const dy = @as(i64, @intCast(center.y)) - @as(i64, @intCast(target.y));
    const adx: u64 = @intCast(if (dx < 0) -dx else dx);
    const ady: u64 = @intCast(if (dy < 0) -dy else dy);
    return adx <= r_extent and ady <= r_extent;
}

pub fn manhattanDistance(a: loc.Loc, b: loc.Loc) u64 {
    const dx = @as(i64, @intCast(a.x)) - @as(i64, @intCast(b.x));
    const dy = @as(i64, @intCast(a.y)) - @as(i64, @intCast(b.y));
    const adx: u64 = @intCast(if (dx < 0) -dx else dx);
    const ady: u64 = @intCast(if (dy < 0) -dy else dy);
    return adx + ady;
}

/// d20 + WIS mod vs DC (base + distance). Consumes one RNG roll.
pub fn spotTrapCheck(wis_mod: i32, distance: u64, rng_state: *rng.SeededRng) bool {
    const roll: i32 = rng_state.rollDie(20);
    const dc = trap_spot_dc_base + @as(i32, @intCast(distance));
    return roll + wis_mod >= dc;
}

test "axis aligned south has los in open chamber" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    try std.testing.expect(hasLineOfSight(&map, loc.Loc.init(49, 49), loc.Loc.init(50, 49)));
}

test "spotTrapCheck uses d20 plus wis mod against distance-scaled dc" {
    var rng_state = rng.SeededRng.init(42);
    // mod +11 at distance 0: DC 12, worst roll 1 still succeeds.
    try std.testing.expect(spotTrapCheck(11, 0, &rng_state));
    rng_state = rng.SeededRng.init(42);
    // mod -4 at distance 6: DC 18, best roll 20 still fails.
    try std.testing.expect(!spotTrapCheck(-4, 6, &rng_state));
}

test "wall blocks los" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    try map.set(loc.Loc.init(50, 49), .wall);
    try std.testing.expect(!hasLineOfSight(&map, loc.Loc.init(49, 49), loc.Loc.init(51, 49)));
    try std.testing.expect(hasLineOfSight(&map, loc.Loc.init(49, 48), loc.Loc.init(51, 48)));
}