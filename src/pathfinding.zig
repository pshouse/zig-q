//! Cardinal BFS pathfinding with deterministic tie-break and anti-oscillation.
const std = @import("std");
const loc = @import("loc.zig");
const movement = @import("movement.zig");
const world = @import("world.zig");
const entity = @import("entity.zig");
const doors = @import("doors.zig");

pub const cardinal_dirs = [_]movement.Direction{ .north, .south, .east, .west };

pub fn isPassable(w: *const world.World, at: loc.Loc, mover_id: entity.EntityId) bool {
    return isPassableToward(w, at, mover_id, null);
}

fn isPassableToward(
    w: *const world.World,
    at: loc.Loc,
    mover_id: entity.EntityId,
    goal: ?loc.Loc,
) bool {
    if (goal) |target| {
        if (at.x == target.x and at.y == target.y) return true;
    }
    if (w.has_dungeon) {
        if (w.terrain.get(at)) |tile| {
            if (!tile.isWalkable()) return false;
            if (tile == .door and w.doors.blocksAt(&w.terrain, at)) return false;
        }
    }
    if (w.tile_map.isBlockedFor(at, mover_id)) return false;
    return true;
}

fn reverseDir(dir: movement.Direction) movement.Direction {
    return switch (dir) {
        .north => .south,
        .south => .north,
        .east => .west,
        .west => .east,
    };
}

fn dirRank(dir: movement.Direction) u8 {
    return switch (dir) {
        .north => 0,
        .south => 1,
        .east => 2,
        .west => 3,
    };
}

const BfsResult = struct {
    dist: [64]i16,
    parent_dir: [64]?movement.Direction,
    queue: [64]loc.Loc,
};

fn locIndex(at: loc.Loc, origin: loc.Loc) ?usize {
    const dx = @as(i64, @intCast(at.x)) - @as(i64, @intCast(origin.x));
    const dy = @as(i64, @intCast(at.y)) - @as(i64, @intCast(origin.y));
    if (dx < 0 or dy < 0 or dx > 7 or dy > 7) return null;
    return @intCast(@as(usize, @intCast(dy)) * 8 + @as(usize, @intCast(dx)));
}

fn indexLoc(origin: loc.Loc, idx: usize) loc.Loc {
    const dy: u64 = @intCast(idx / 8);
    const dx: u64 = @intCast(idx % 8);
    return loc.Loc.init(origin.x + dx, origin.y + dy);
}

fn runBfs(
    w: *const world.World,
    start: loc.Loc,
    goal: loc.Loc,
    mover_id: entity.EntityId,
    result: *BfsResult,
) bool {
    const origin = loc.Loc.init(
        if (start.x < goal.x) start.x else goal.x,
        if (start.y < goal.y) start.y else goal.y,
    );

    @memset(&result.dist, -1);
    @memset(&result.parent_dir, null);

    const start_idx = locIndex(start, origin) orelse return false;
    const goal_idx = locIndex(goal, origin) orelse return false;

    var head: usize = 0;
    var tail: usize = 0;
    result.queue[tail] = start;
    tail += 1;
    result.dist[start_idx] = 0;

    while (head < tail) : (head += 1) {
        const current = result.queue[head];
        const current_idx = locIndex(current, origin) orelse continue;
        if (current_idx == goal_idx) return true;

        const current_dist = result.dist[current_idx];
        for (cardinal_dirs) |dir| {
            const next = movement.step(current, dir) orelse continue;
            const next_idx = locIndex(next, origin) orelse continue;
            if (result.dist[next_idx] != -1) continue;
            if (!isPassableToward(w, next, mover_id, goal)) continue;
            result.dist[next_idx] = current_dist + 1;
            result.parent_dir[next_idx] = dir;
            result.queue[tail] = next;
            tail += 1;
        }
    }
    return result.dist[goal_idx] != -1;
}

fn pickFirstStep(
    w: *const world.World,
    start: loc.Loc,
    goal: loc.Loc,
    mover_id: entity.EntityId,
    avoid_reverse: ?movement.Direction,
    maximize: bool,
) ?movement.Direction {
    if (start.x == goal.x and start.y == goal.y) return null;

    var bfs: BfsResult = undefined;
    if (!runBfs(w, start, goal, mover_id, &bfs)) return null;

    const origin = loc.Loc.init(
        if (start.x < goal.x) start.x else goal.x,
        if (start.y < goal.y) start.y else goal.y,
    );
    var best_dir: ?movement.Direction = null;
    var best_dist: i16 = if (maximize) -1 else std.math.maxInt(i16);
    var best_rank: u8 = 255;

    for (cardinal_dirs) |dir| {
        const next = movement.step(start, dir) orelse continue;
        const next_idx = locIndex(next, origin) orelse continue;
        const dist = bfs.dist[next_idx];
        if (dist < 0) continue;

        const better = if (maximize)
            dist > best_dist or (dist == best_dist and dirRank(dir) < best_rank)
        else
            dist < best_dist or (dist == best_dist and dirRank(dir) < best_rank);

        if (!better) continue;
        best_dist = dist;
        best_rank = dirRank(dir);
        best_dir = dir;
    }

    if (best_dir) |dir| {
        if (avoid_reverse) |last| {
            if (dir == reverseDir(last)) {
                var alt_dir: ?movement.Direction = null;
                var alt_dist: i16 = best_dist;
                var alt_rank: u8 = 255;
                for (cardinal_dirs) |candidate| {
                    if (candidate == dir) continue;
                    const next = movement.step(start, candidate) orelse continue;
                    const next_idx = locIndex(next, origin) orelse continue;
                    const dist = bfs.dist[next_idx];
                    if (dist < 0) continue;
                    const better = if (maximize)
                        dist > alt_dist or (dist == alt_dist and dirRank(candidate) < alt_rank)
                    else
                        dist < alt_dist or (dist == alt_dist and dirRank(candidate) < alt_rank);
                    if (!better) continue;
                    alt_dist = dist;
                    alt_rank = dirRank(candidate);
                    alt_dir = candidate;
                }
                if (alt_dir) |alt| {
                    if (alt_dist == best_dist) return alt;
                }
            }
        }
    }

    return best_dir;
}

pub fn firstStepToward(
    w: *const world.World,
    start: loc.Loc,
    goal: loc.Loc,
    mover_id: entity.EntityId,
    avoid_reverse: ?movement.Direction,
) ?movement.Direction {
    return pickFirstStep(w, start, goal, mover_id, avoid_reverse, false);
}

pub fn firstStepAway(
    w: *const world.World,
    start: loc.Loc,
    threat: loc.Loc,
    mover_id: entity.EntityId,
    avoid_reverse: ?movement.Direction,
) ?movement.Direction {
    return pickFirstStep(w, start, threat, mover_id, avoid_reverse, true);
}

test "bfs picks north before west on equal steps" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 1);
    defer w.deinit();

    const start = loc.Loc.init(50, 50);
    const goal = loc.Loc.init(49, 49);
    const dir = firstStepToward(&w, start, goal, entity.invalid_id, null);
    try std.testing.expectEqual(movement.Direction.north, dir.?);
}

test "closed door blocks path" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 1);
    defer w.deinit();
    w.has_dungeon = true;
    try w.terrain.set(loc.Loc.init(49, 50), .door);
    try w.doors.set(loc.Loc.init(49, 50), .closed);
    try w.terrain.set(loc.Loc.init(48, 49), .wall);
    try w.terrain.set(loc.Loc.init(48, 50), .wall);
    try w.terrain.set(loc.Loc.init(48, 51), .wall);
    try w.terrain.set(loc.Loc.init(50, 49), .wall);
    try w.terrain.set(loc.Loc.init(50, 50), .wall);
    try w.terrain.set(loc.Loc.init(50, 51), .wall);

    const start = loc.Loc.init(49, 49);
    const goal = loc.Loc.init(49, 51);
    const blocked = firstStepToward(&w, start, goal, entity.invalid_id, null);
    try std.testing.expect(blocked == null);
}