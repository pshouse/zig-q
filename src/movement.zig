const std = @import("std");
const loc = @import("loc.zig");
const world = @import("world.zig");
const entity = @import("entity.zig");

pub const Direction = enum {
    north,
    south,
    east,
    west,

    pub fn parse(word: []const u8) ?Direction {
        if (std.mem.eql(u8, word, "north") or std.mem.eql(u8, word, "n")) return .north;
        if (std.mem.eql(u8, word, "south") or std.mem.eql(u8, word, "s")) return .south;
        if (std.mem.eql(u8, word, "east") or std.mem.eql(u8, word, "e")) return .east;
        if (std.mem.eql(u8, word, "west") or std.mem.eql(u8, word, "w")) return .west;
        return null;
    }

    pub fn token(dir: Direction) []const u8 {
        return switch (dir) {
            .north => "n",
            .south => "s",
            .east => "e",
            .west => "w",
        };
    }
};

/// Compound compass shorthand (north-then-west, etc.).
pub fn parseCompound(word: []const u8) ?[2]Direction {
    if (std.mem.eql(u8, word, "nw")) return .{ .north, .west };
    if (std.mem.eql(u8, word, "ne")) return .{ .north, .east };
    if (std.mem.eql(u8, word, "sw")) return .{ .south, .west };
    if (std.mem.eql(u8, word, "se")) return .{ .south, .east };
    return null;
}

pub fn step(from: loc.Loc, dir: Direction) ?loc.Loc {
    return switch (dir) {
        .north => if (from.x == 0) null else loc.Loc.init(from.x - 1, from.y),
        .south => loc.Loc.init(from.x + 1, from.y),
        .east => loc.Loc.init(from.x, from.y + 1),
        .west => if (from.y == 0) null else loc.Loc.init(from.x, from.y - 1),
    };
}

/// Moves entity on the sparse map, ticks the clock on success.
/// Exhaustion movement cost (beyond the free tile step):
/// - tier ≥ 3: always an extra clock tick (promised movement −1, for real)
/// - tiers 1–2: extra tick only on danger floors (floor ≥ 4), so frozen
///   floor 1–3 goldens (incl. `reference_crawl`) stay byte-identical
///
/// Race speed (Phase 2, floors ≥ 4 only — read `ent.char.race.speed`, never
/// write `ent.movement` so `stats` still prints movement: 30):
/// - speed < 30 (slow, dwarf): +1 extra tick per move
/// - speed > 30 (fast, elf): suppress one deep-floor extra-tick
/// - speed == 30 (neutral): unchanged
/// Total move cost is never less than 1 tick.
pub fn moveEntity(w: *world.World, id: entity.EntityId, dir: Direction) !loc.Loc {
    const ent = w.store.get(id) orelse return error.EntityNotFound;
    const old_loc = ent.loc;
    const new_loc = step(old_loc, dir) orelse return error.Blocked;
    if (w.has_dungeon) {
        if (w.terrain.get(new_loc)) |tile| {
            if (!tile.isWalkable()) return error.Blocked;
            if (tile == .door and w.doors.blocksAt(&w.terrain, new_loc)) return error.Blocked;
        }
    }
    if (w.isTileBlockedFor(new_loc, id)) return error.Blocked;

    w.tile_map.remove(old_loc, id);
    try w.tile_map.place(new_loc, id);
    ent.loc = new_loc;

    // Base move always costs 1 tick. Extras are clamped so cost stays ≥ 1.
    var extra: i32 = 0;
    if (!ent.is_monster) {
        const ex = @import("conditions.zig").exhaustionLevel(ent);
        if (ex >= 3) {
            extra += 1;
        } else if (ex >= 2 and w.floor_index >= 4) {
            // Gate at tier 2+: rest floors fatigue at 20 = tier 1, so an
            // ex>=1 gate made the deep-floor surcharge permanently on.
            extra += 1;
        }
        // Deep-floor race speed: floors ≥ 4 only (floors 1–3 goldens untouched).
        if (w.floor_index >= 4) {
            const speed = ent.char.race.speed;
            if (speed < 30) {
                extra += 1;
            } else if (speed > 30) {
                extra -= 1;
            }
        }
    }
    // Cap the deep-floor stack so a slow race cannot pay +3/+4 (race surcharge
    // is ungated by exhaustion). Dwarf → flat 2 ticks/move; elf/human → 1.
    if (w.floor_index >= 4 and extra > 1) extra = 1;
    if (extra < 0) extra = 0;

    w.tick();
    var i: i32 = 0;
    while (i < extra) : (i += 1) w.tick();
    return new_loc;
}

test "moveEntity updates loc and map occupancy" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 1);
    defer w.deinit();

    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const start = loc.Loc.init(49, 49);

    try std.testing.expectEqual(@as(usize, 1), w.tile_map.entityCountAt(start));
    try std.testing.expectEqual(@as(usize, 0), w.tile_map.entityCountAt(loc.Loc.init(49, 50)));

    const after = try moveEntity(&w, id, .east);
    try std.testing.expectEqual(loc.Loc.init(49, 50), after);
    try std.testing.expectEqual(@as(usize, 0), w.tile_map.entityCountAt(start));
    try std.testing.expectEqual(@as(usize, 1), w.tile_map.entityCountAt(after));
    try std.testing.expectEqual(after.x, w.store.get(id).?.loc.x);
    try std.testing.expectEqual(after.y, w.store.get(id).?.loc.y);
}

test "moveEntity advances clock" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 1);
    defer w.deinit();

    const id = try w.spawnTestPlayer(loc.Loc.init(10, 10));
    try std.testing.expectEqual(@as(u64, 0), w.game_clock.ticks);

    _ = try moveEntity(&w, id, .south);
    try std.testing.expectEqual(@as(u64, 1), w.game_clock.ticks);
}

test "moveEntity rejects dungeon wall" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 1);
    defer w.deinit();
    try w.loadFloor(1);

    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    try std.testing.expectError(error.Blocked, moveEntity(&w, id, .north));
}

test "moveEntity allows stepping onto corpse floor object" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    try w.floor_objects.addItem(allocator, .corpse, loc.Loc.init(50, 49), "goblin_0", null);

    const new_loc = try moveEntity(&w, id, .south);
    try std.testing.expectEqual(loc.Loc.init(50, 49), new_loc);
}

test "moveEntity allows stepping onto skeleton corpse" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    try w.floor_objects.addItem(allocator, .corpse, loc.Loc.init(50, 49), "skeleton_0", null);

    const new_loc = try moveEntity(&w, id, .south);
    try std.testing.expectEqual(loc.Loc.init(50, 49), new_loc);
}

// Phase 2: race.speed modulates extra ticks only on floors ≥ 4.
test "deep-floor race speed: slow pays +1, fast suppresses one extra, cost never < 1" {
    const allocator = std.testing.allocator;
    const conditions = @import("conditions.zig");

    // Floor 1: slow race still pays only the base tick (golden-safe floors 1–3).
    {
        var w = try world.World.init(allocator, 1);
        defer w.deinit();
        try w.loadFloor(1);
        const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
        w.store.get(id).?.char.race = w.races.items[1]; // dwarf speed 25
        try std.testing.expectEqual(@as(u8, 25), w.store.get(id).?.char.race.speed);
        _ = try moveEntity(&w, id, .east);
        try std.testing.expectEqual(@as(u64, 1), w.game_clock.ticks);
        // ent.movement is never written from race.speed
        try std.testing.expectEqual(@as(u8, 30), w.store.get(id).?.movement);
    }

    // Floor 4, no exhaustion:
    //   neutral (30) → 1 tick; slow (25) → 2; fast (35) → 1 (nothing to suppress)
    {
        var w = try world.World.init(allocator, 1);
        defer w.deinit();
        try w.loadFloor(1);
        w.floor_index = 4; // deep-floor gate without regenerating terrain
        const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));

        w.store.get(id).?.char.race = w.races.items[0]; // dragonborn 30
        w.game_clock.ticks = 0;
        _ = try moveEntity(&w, id, .east);
        const neutral_ticks = w.game_clock.ticks;
        try std.testing.expectEqual(@as(u64, 1), neutral_ticks);

        w.store.get(id).?.char.race = w.races.items[1]; // dwarf 25
        w.game_clock.ticks = 0;
        _ = try moveEntity(&w, id, .west);
        const slow_ticks = w.game_clock.ticks;
        try std.testing.expectEqual(@as(u64, 2), slow_ticks);

        w.store.get(id).?.char.race = w.races.items[2]; // elf 35
        w.game_clock.ticks = 0;
        _ = try moveEntity(&w, id, .east);
        const fast_ticks = w.game_clock.ticks;
        try std.testing.expectEqual(@as(u64, 1), fast_ticks);
        try std.testing.expect(fast_ticks < slow_ticks);
        try std.testing.expect(fast_ticks >= 1);
    }

    // Floor 4 + exhaustion tier 1 (v1.9.0): deep-floor surcharge gates at ex>=2,
    // so tier 1 only pays the race term. Human/elf → 1; dwarf → 2 (clamped stack).
    {
        var w = try world.World.init(allocator, 1);
        defer w.deinit();
        try w.loadFloor(1);
        w.floor_index = 4;
        const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));

        // Pin fatigue in tier-1 band so syncExhaustion keeps level 1 across ticks.
        w.store.get(id).?.fatigue = 25;
        _ = @import("survival.zig").syncExhaustion(w.store.get(id).?);
        try std.testing.expectEqual(@as(u3, 1), conditions.exhaustionLevel(w.store.get(id).?));

        w.store.get(id).?.char.race = w.races.items[3]; // human 30
        w.game_clock.ticks = 0;
        _ = try moveEntity(&w, id, .east);
        try std.testing.expectEqual(@as(u64, 1), w.game_clock.ticks);

        w.store.get(id).?.fatigue = 25;
        _ = @import("survival.zig").syncExhaustion(w.store.get(id).?);
        w.store.get(id).?.char.race = w.races.items[2]; // elf 35
        w.game_clock.ticks = 0;
        _ = try moveEntity(&w, id, .west);
        try std.testing.expectEqual(@as(u64, 1), w.game_clock.ticks);

        w.store.get(id).?.fatigue = 25;
        _ = @import("survival.zig").syncExhaustion(w.store.get(id).?);
        w.store.get(id).?.char.race = w.races.items[1]; // dwarf 25
        w.game_clock.ticks = 0;
        _ = try moveEntity(&w, id, .east);
        try std.testing.expectEqual(@as(u64, 2), w.game_clock.ticks);
    }

    // Floor 4 + exhaustion tier 2: surcharge is on, but deep-floor stack clamps to +1.
    // Dwarf would otherwise pay race+ex = 2 extras → 3 ticks; clamp keeps it at 2.
    {
        var w = try world.World.init(allocator, 1);
        defer w.deinit();
        try w.loadFloor(1);
        w.floor_index = 4;
        const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
        w.store.get(id).?.fatigue = 45; // tier 2 (< 62)
        _ = @import("survival.zig").syncExhaustion(w.store.get(id).?);
        try std.testing.expectEqual(@as(u3, 2), conditions.exhaustionLevel(w.store.get(id).?));
        w.store.get(id).?.char.race = w.races.items[1]; // dwarf 25
        w.game_clock.ticks = 0;
        _ = try moveEntity(&w, id, .east);
        try std.testing.expectEqual(@as(u64, 2), w.game_clock.ticks);
    }
}

test "defaultRaces: human at index 4, speed set is {25,30,35}" {
    const allocator = std.testing.allocator;
    const types = @import("types.zig");
    var races = try types.defaultRaces(allocator);
    defer types.deinitRaceList(allocator, &races);

    try std.testing.expectEqual(@as(usize, 4), races.items.len);
    try std.testing.expectEqualStrings("dragonborn", races.items[0].name);
    try std.testing.expectEqualStrings("dwarf", races.items[1].name);
    try std.testing.expectEqualStrings("elf", races.items[2].name);
    try std.testing.expectEqualStrings("human", races.items[3].name);
    try std.testing.expectEqual(@as(u8, 30), races.items[0].speed);
    try std.testing.expectEqual(@as(u8, 25), races.items[1].speed);
    try std.testing.expectEqual(@as(u8, 35), races.items[2].speed);
    try std.testing.expectEqual(@as(u8, 30), races.items[3].speed);
    try std.testing.expectEqual(@as(u64, 2), races.items[3].attr_bonuses.items[0].stat);
    try std.testing.expectEqualStrings("INT", races.items[3].attr_bonuses.items[0].abbr);
}

test "moveEntity rejects large corpse on tile" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    try w.floor_objects.addItem(allocator, .corpse, loc.Loc.init(50, 49), "dragon_0", null);

    try std.testing.expectError(error.Blocked, moveEntity(&w, id, .south));
}

test "moveEntity ignores dead entity still listed on tile map" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const monster_id = try w.spawnMonster(@import("monsters.zig").Kind.goblin, loc.Loc.init(50, 49), "goblin_0");
    const monster = w.store.get(monster_id).?;
    @import("conditions.zig").markDead(monster);

    const new_loc = try moveEntity(&w, player_id, .south);
    try std.testing.expectEqual(loc.Loc.init(50, 49), new_loc);
}

test "moveEntity rejects blocked tile" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 1);
    defer w.deinit();

    const a = try w.spawnTestPlayer(loc.Loc.init(5, 5));
    const b = try w.spawnTestPlayer(loc.Loc.init(5, 6));

    const a_loc = w.store.get(a).?.loc;
    const b_loc = w.store.get(b).?.loc;
    _ = a_loc;
    _ = b_loc;

    try std.testing.expectError(error.Blocked, moveEntity(&w, a, .east));
}
