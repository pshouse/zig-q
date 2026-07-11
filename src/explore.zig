//! Explore-phase monster AI, traps, doors, and ambush combat entry.
const std = @import("std");
const world = @import("world.zig");
const entity = @import("entity.zig");
const loc = @import("loc.zig");
const movement = @import("movement.zig");
const combat = @import("combat.zig");
const conditions = @import("conditions.zig");
const perception = @import("perception.zig");
const pathfinding = @import("pathfinding.zig");
const world_objects = @import("world_objects.zig");
const doors = @import("doors.zig");
const items = @import("items.zig");
const survival = @import("survival.zig");
const character = @import("character.zig");

pub const chase_radius: u8 = 6;
/// Base DC for INT `disarm` / `pick` skill checks. Rogue gets −2 (owns INT skills).
pub const skill_dc_base: i32 = 15;
/// Explore turns a monster keeps pathing to the last-seen player tile after
/// LOS breaks (#35). Long enough to finish a chokepoint funnel; short enough
/// that fully escaping still works.
pub const chase_memory_turns: u8 = 4;

const patrol_dirs = [_]movement.Direction{ .east, .south, .west, .north };

fn isAlive(ent: *const entity.Entity) bool {
    return !conditions.isDead(ent);
}

fn isAdjacent(a: loc.Loc, b: loc.Loc) bool {
    const dx = @as(i64, @intCast(a.x)) - @as(i64, @intCast(b.x));
    const dy = @as(i64, @intCast(a.y)) - @as(i64, @intCast(b.y));
    const adx: u64 = @intCast(if (dx < 0) -dx else dx);
    const ady: u64 = @intCast(if (dy < 0) -dy else dy);
    return adx + ady == 1;
}

fn manhattan(a: loc.Loc, b: loc.Loc) u64 {
    const dx = @as(i64, @intCast(a.x)) - @as(i64, @intCast(b.x));
    const dy = @as(i64, @intCast(a.y)) - @as(i64, @intCast(b.y));
    const adx: u64 = @intCast(if (dx < 0) -dx else dx);
    const ady: u64 = @intCast(if (dy < 0) -dy else dy);
    return adx + ady;
}

fn hasLosToPlayer(w: *const world.World, monster: *const entity.Entity, player: *const entity.Entity) bool {
    if (manhattan(monster.loc, player.loc) > chase_radius) return false;
    return perception.hasLineOfSight(&w.terrain, monster.loc, player.loc);
}

fn patrolDirection(monster: *const entity.Entity) movement.Direction {
    return patrol_dirs[monster.ai_patrol_phase % patrol_dirs.len];
}

/// Update chase memory from current LOS, then choose a step. Mutates monster
/// memory fields. Returns null when adjacent (ready to ambush) or idle.
fn chooseMonsterDirection(
    w: *world.World,
    monster: *entity.Entity,
    player: *const entity.Entity,
) ?movement.Direction {
    if (conditions.has(monster, .frightened)) {
        const here = manhattan(monster.loc, player.loc);
        var best: ?movement.Direction = null;
        var best_dist: u64 = here;
        for (pathfinding.cardinal_dirs) |dir| {
            const next = movement.step(monster.loc, dir) orelse continue;
            if (!pathfinding.isPassable(w, next, monster.id)) continue;
            const dist = manhattan(next, player.loc);
            if (dist <= here) continue;
            if (dist > best_dist) {
                best_dist = dist;
                best = dir;
            }
        }
        return best;
    }
    if (isAdjacent(monster.loc, player.loc)) {
        monster.chase_memory_left = 0;
        monster.chase_last_seen = null;
        return null;
    }
    // #35: refresh memory while LOS holds; otherwise path to last-seen tile.
    if (hasLosToPlayer(w, monster, player)) {
        monster.chase_last_seen = player.loc;
        monster.chase_memory_left = chase_memory_turns;
        return pathfinding.firstStepToward(w, monster.loc, player.loc, monster.id, monster.last_move_dir);
    }
    if (monster.chase_memory_left > 0) {
        if (monster.chase_last_seen) |goal| {
            monster.chase_memory_left -= 1;
            if (monster.loc.x == goal.x and monster.loc.y == goal.y) {
                monster.chase_memory_left = 0;
                monster.chase_last_seen = null;
            } else {
                return pathfinding.firstStepToward(w, monster.loc, goal, monster.id, monster.last_move_dir);
            }
        } else {
            monster.chase_memory_left = 0;
        }
    }
    const dir = patrolDirection(monster);
    const next = movement.step(monster.loc, dir) orelse return null;
    if (!pathfinding.isPassable(w, next, monster.id)) return null;
    return dir;
}

fn applyTrapCondition(ent: *entity.Entity, label: []const u8) void {
    if (std.mem.eql(u8, label, "poison_trap") or std.mem.indexOf(u8, label, "poison") != null) {
        survival.applyPoison(ent);
        return;
    }
    if (std.mem.eql(u8, label, "snare_trap") or std.mem.indexOf(u8, label, "snare") != null) {
        conditions.apply(ent, .restrained);
        return;
    }
    survival.applyPoison(ent);
}

pub fn checkStepTraps(w: *world.World, player_id: entity.EntityId) bool {
    const ent = w.store.get(player_id) orelse return false;
    const obj = w.floor_objects.at(ent.loc) orelse return false;
    if (obj.kind != .trap) return false;
    applyTrapCondition(ent, obj.label);
    return true;
}

/// INT skill DC: base 15, Rogue −2. Deterministic — no draw.
pub fn skillDc(ent: *const entity.Entity) i32 {
    var dc: i32 = skill_dc_base;
    if (std.mem.eql(u8, ent.char.class.name, "rogue")) dc -= 2;
    return dc;
}

fn isAdjacentLoc(a: loc.Loc, b: loc.Loc) bool {
    return manhattan(a, b) == 1;
}

/// INT `disarm`: adjacent + already WIS-spotted trap. One d20 + INT mod ≥ DC.
/// Success removes the trap; failure triggers the normal trap effect (trap stays).
pub fn tryDisarm(w: *world.World, player_id: entity.EntityId) !enum { success, failed } {
    const player = w.store.get(player_id) orelse return error.EntityNotFound;
    var trap_pos: ?loc.Loc = null;
    for (w.floor_objects.objects.items) |obj| {
        if (obj.kind != .trap) continue;
        if (!obj.spotted) continue;
        const pos = loc.Loc.init(obj.x, obj.y);
        if (!isAdjacentLoc(player.loc, pos)) continue;
        trap_pos = pos;
        break;
    }
    const pos = trap_pos orelse return error.NoSpottedTrap;
    const obj = w.floor_objects.at(pos) orelse return error.NoSpottedTrap;

    const int_mod = character.abilityModifier(character.statByAbbr(player.char, "INT"));
    const roll: i32 = w.rng.rollDie(20);
    const dc = skillDc(player);
    if (roll + int_mod >= dc) {
        w.floor_objects.removeAt(w.allocator, pos);
        return .success;
    }
    // Failed disarm springs the trap on the disarmer (normal effect).
    applyTrapCondition(player, obj.label);
    return .failed;
}

/// INT `pick`: open an adjacent `.locked` door. One d20 + INT mod ≥ DC → `.open`.
pub fn tryPickLock(
    w: *world.World,
    player_id: entity.EntityId,
    dir: ?movement.Direction,
) !enum { success, failed } {
    const player = w.store.get(player_id) orelse return error.EntityNotFound;

    const target: loc.Loc = if (dir) |d|
        movement.step(player.loc, d) orelse return error.Blocked
    else blk: {
        // Bare `pick`: first adjacent locked door in N/S/E/W order.
        for (pathfinding.cardinal_dirs) |d| {
            const next = movement.step(player.loc, d) orelse continue;
            const tile = w.terrain.get(next) orelse continue;
            if (tile != .door) continue;
            const state = w.doors.resolve(&w.terrain, next) orelse .closed;
            if (state == .locked) break :blk next;
        }
        return error.NoLockedDoor;
    };

    const tile = w.terrain.get(target) orelse return error.NotADoor;
    if (tile != .door) return error.NotADoor;
    const state = w.doors.resolve(&w.terrain, target) orelse .closed;
    if (state != .locked) {
        return if (state == .open) error.AlreadyOpen else error.NotLocked;
    }

    const int_mod = character.abilityModifier(character.statByAbbr(player.char, "INT"));
    const roll: i32 = w.rng.rollDie(20);
    const dc = skillDc(player);
    if (roll + int_mod >= dc) {
        try w.doors.set(target, .open);
        return .success;
    }
    return .failed;
}

pub fn tryOpenDoor(
    w: *world.World,
    player_id: entity.EntityId,
    dir: movement.Direction,
) !void {
    const player = w.store.get(player_id) orelse return error.EntityNotFound;
    const target = movement.step(player.loc, dir) orelse return error.Blocked;
    const tile = w.terrain.get(target) orelse return error.NotADoor;
    if (tile != .door) return error.NotADoor;

    const state = w.doors.resolve(&w.terrain, target) orelse .closed;
    switch (state) {
        .open => return error.AlreadyOpen,
        .locked => {
            if (!player.inventory.has(.iron_key)) return error.DoorLocked;
            _ = player.inventory.remove(.iron_key, 1);
            try w.doors.set(target, .open);
        },
        .closed => try w.doors.set(target, .open),
    }
}

pub fn tryCloseDoor(
    w: *world.World,
    player_id: entity.EntityId,
    dir: movement.Direction,
) !void {
    const player = w.store.get(player_id) orelse return error.EntityNotFound;
    const target = movement.step(player.loc, dir) orelse return error.Blocked;
    const tile = w.terrain.get(target) orelse return error.NotADoor;
    if (tile != .door) return error.NotADoor;

    const state = w.doors.resolve(&w.terrain, target) orelse .closed;
    switch (state) {
        .open => try w.doors.set(target, .closed),
        .closed => return error.AlreadyClosed,
        .locked => return error.AlreadyClosed,
    }
}

/// One explore step per monster; returns true if a monster moved adjacent to the player.
pub fn runExploreMonsterTurns(w: *world.World, player_id: entity.EntityId, writer: anytype) !bool {
    if (combat.isInCombat(w)) return false;
    const player = w.store.get(player_id) orelse return false;
    if (conditions.isDead(player)) return false;

    var ids: [32]entity.EntityId = undefined;
    var n: usize = 0;
    for (w.store.entities.items) |ent| {
        if (!ent.is_monster or !isAlive(&ent)) continue;
        if (conditions.blocksMove(&ent)) continue;
        if (n < ids.len) {
            ids[n] = ent.id;
            n += 1;
        }
    }
    std.mem.sort(entity.EntityId, ids[0..n], {}, std.sort.asc(entity.EntityId));

    var moved_adjacent = false;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const mid = ids[i];
        // Spot-check a hidden player before the monster moves. Gated on player.hidden
        // so existing explore transcripts keep their exact draw order.
        if (w.store.get(player_id)) |p| {
            if (p.hidden) {
                if (w.store.get(mid)) |m| {
                    _ = try combat.trySpotHiddenPlayer(w, m, p, writer);
                }
            }
        }
        const monster = w.store.get(mid) orelse continue;
        const dir = chooseMonsterDirection(w, monster, player) orelse continue;
        const before = monster.loc;
        const after = movement.moveEntity(w, mid, dir) catch continue;
        if (w.store.get(mid)) |m| {
            m.last_move_dir = dir;
            m.ai_patrol_phase +%= 1;
            if (before.x != after.x or before.y != after.y) {
                try writer.print("{s} moved {s} to ({},{})\n", .{
                    m.name, movement.Direction.token(dir), after.x, after.y,
                });
            }
            if (isAdjacent(after, player.loc)) moved_adjacent = true;
        }
        if (moved_adjacent) return true;
    }
    return false;
}

pub fn tryAmbushOnAdjacent(w: *world.World, player_id: entity.EntityId, writer: anytype) !void {
    if (combat.isInCombat(w)) return;
    const player = w.store.get(player_id) orelse return;
    var best: ?entity.EntityId = null;
    for (w.store.entities.items) |ent| {
        if (!ent.is_monster or !isAlive(&ent)) continue;
        if (!isAdjacent(player.loc, ent.loc)) continue;
        if (best == null or ent.id < best.?) best = ent.id;
    }
    // Ambush: monster initiates — seats the monster as first actor (D2), then resolves
    // their opening swing(s) so the first-strike actually lands.
    if (best) |enemy| {
        try combat.enterCombat(w, player_id, enemy, enemy);
        try combat.resolveOpeningTurns(w, writer);
    }
}

pub fn afterPlayerExploreAction(w: *world.World, player_id: entity.EntityId, writer: anytype) !bool {
    if (combat.isInCombat(w)) return false;
    _ = try runExploreMonsterTurns(w, player_id, writer);
    // Always check adjacency after AI — not only when a monster *just* stepped in.
    // Sleep/rest next to a hostile must interrupt (Track 3); previously only
    // `moved_adjacent` triggered ambush, so standing-adjacent sleep was safe.
    try tryAmbushOnAdjacent(w, player_id, writer);
    return combat.isInCombat(w);
}

pub fn formatMonsterMove(w: *const world.World, id: entity.EntityId, writer: anytype) !void {
    const ent = w.store.get(id) orelse return;
    try writer.print("monster {s} at ({},{})\n", .{ ent.name, ent.loc.x, ent.loc.y });
}

test "frightened monster flees away from player" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const monster_id = try w.spawnMonster(.goblin, loc.Loc.init(52, 49), "goblin_0");
    if (w.store.get(monster_id)) |m| conditions.apply(m, .frightened);

    const before = w.store.get(monster_id).?.loc;
    var discard_buf: [128]u8 = undefined;
    var discard_stream = std.io.fixedBufferStream(&discard_buf);
    _ = try runExploreMonsterTurns(&w, player_id, discard_stream.writer());
    const monster = w.store.get(monster_id).?;
    try std.testing.expect(monster.loc.x != before.x or monster.loc.y != before.y);
    try std.testing.expect(!isAdjacent(monster.loc, w.store.get(player_id).?.loc));
}

test "chase memory pathing continues after LOS breaks" {
    // #35: after seeing the player, a monster keeps pathing to last-seen for
    // chase_memory_turns even without LOS (chokepoint baiting).
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    w.has_dungeon = true;
    // Open corridor with a wall blocking LOS between goblin and player.
    try w.terrain.set(loc.Loc.init(50, 50), .floor);
    try w.terrain.set(loc.Loc.init(50, 51), .wall); // LOS block
    try w.terrain.set(loc.Loc.init(50, 52), .floor);
    try w.terrain.set(loc.Loc.init(51, 50), .floor);
    try w.terrain.set(loc.Loc.init(51, 51), .floor); // path around the wall
    try w.terrain.set(loc.Loc.init(51, 52), .floor);

    const player_id = try w.spawnTestPlayer(loc.Loc.init(50, 50));
    const monster_id = try w.spawnMonster(.goblin, loc.Loc.init(50, 52), "goblin_0");
    // Seed memory as if LOS just broke mid-chase (last saw player at 50,50).
    if (w.store.get(monster_id)) |m| {
        m.chase_last_seen = loc.Loc.init(50, 50);
        m.chase_memory_left = chase_memory_turns;
    }
    try std.testing.expect(!hasLosToPlayer(&w, w.store.get(monster_id).?, w.store.get(player_id).?));
    const before = w.store.get(monster_id).?.loc;
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try runExploreMonsterTurns(&w, player_id, fbs.writer());
    const after = w.store.get(monster_id).?.loc;
    try std.testing.expect(after.x != before.x or after.y != before.y);
    try std.testing.expect(w.store.get(monster_id).?.chase_memory_left < chase_memory_turns);
}
