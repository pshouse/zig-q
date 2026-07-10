const std = @import("std");
const loc = @import("loc.zig");
const terrain = @import("terrain.zig");
const rng = @import("rng.zig");
const monsters = @import("monsters.zig");
const items = @import("items.zig");

const TileEntry = struct {
    x: u64,
    y: u64,
    tile: terrain.Tile,
};

pub const Floor1Profile = enum {
    /// v0.8 regression layout: door (+) at (49,53) unreachable from spawn.
    v08,
    /// v0.9 playable layout: stairs (>) at south-east exit (50,51).
    v09,
};

/// Floor 1: small chamber around spawn (49,49). North wall blocks `move north`.
const floor1_tiles = [_]TileEntry{
    .{ .x = 47, .y = 47, .tile = .wall },
    .{ .x = 47, .y = 48, .tile = .wall },
    .{ .x = 47, .y = 49, .tile = .wall },
    .{ .x = 47, .y = 50, .tile = .wall },
    .{ .x = 47, .y = 51, .tile = .wall },
    .{ .x = 48, .y = 47, .tile = .wall },
    .{ .x = 48, .y = 48, .tile = .wall },
    .{ .x = 48, .y = 49, .tile = .wall },
    .{ .x = 48, .y = 50, .tile = .wall },
    .{ .x = 48, .y = 51, .tile = .wall },
    .{ .x = 49, .y = 47, .tile = .wall },
    .{ .x = 50, .y = 47, .tile = .wall },
    .{ .x = 51, .y = 47, .tile = .wall },
    .{ .x = 49, .y = 51, .tile = .wall },
    .{ .x = 50, .y = 51, .tile = .wall },
    .{ .x = 51, .y = 51, .tile = .wall },
    .{ .x = 51, .y = 48, .tile = .wall },
    .{ .x = 51, .y = 49, .tile = .wall },
    .{ .x = 51, .y = 50, .tile = .wall },
    .{ .x = 49, .y = 53, .tile = .door },
};

fn skipFloor1Tile(profile: Floor1Profile, entry: TileEntry) bool {
    if (profile != .v09) return false;
    // v0.9: replace far-east door and south-east wall with proper stairs.
    if (entry.x == 49 and entry.y == 53 and entry.tile == .door) return true;
    if (entry.x == 50 and entry.y == 51 and entry.tile == .wall) return true;
    return false;
}

pub fn loadFloor1(map: *terrain.TerrainMap, profile: Floor1Profile) !void {
    map.clear();
    for (floor1_tiles) |entry| {
        if (skipFloor1Tile(profile, entry)) continue;
        try map.set(loc.Loc.init(entry.x, entry.y), entry.tile);
    }
    if (profile == .v09) {
        try map.set(floor1_stairs_v09, .stairs);
    }
}

pub const floor1_spawn = loc.Loc.init(49, 49);
/// v0.8 regression descend trigger (door glyph).
pub const floor1_door_v08 = loc.Loc.init(49, 53);
/// v0.9 descend trigger at the chamber's south-east exit.
pub const floor1_stairs_v09 = loc.Loc.init(50, 51);

/// Moves from spawn to floor-1 stairs on the v0.9 layout: east, south, east.
pub fn walkSpawnToFloor1Stairs(w: *@import("world.zig").World, player_id: @import("entity.zig").EntityId) !void {
    const movement = @import("movement.zig");
    _ = try movement.moveEntity(w, player_id, .east);
    _ = try movement.moveEntity(w, player_id, .south);
    _ = try movement.moveEntity(w, player_id, .east);
}

pub fn floorSeed(world_seed: u64, floor_index: u32) u64 {
    return std.hash.Wyhash.hash(0, std.mem.asBytes(&world_seed)) ^
        (@as(u64, floor_index) *% 0x9E3779B97F4A7C15);
}

pub fn floorRng(world_seed: u64, floor_index: u32) rng.SeededRng {
    return rng.SeededRng.init(floorSeed(world_seed, floor_index));
}

fn trapSeed(world_seed: u64, floor_index: u32) u64 {
    return floorSeed(world_seed, floor_index) ^ 0xD1572A9B1E5F00D5;
}

pub fn trapRng(world_seed: u64, floor_index: u32) rng.SeededRng {
    return rng.SeededRng.init(trapSeed(world_seed, floor_index));
}

fn depthBonusSeed(world_seed: u64, floor_index: u32) u64 {
    return floorSeed(world_seed, floor_index) ^ 0xB005B005B005B005;
}

fn depthBonusRng(world_seed: u64, floor_index: u32) rng.SeededRng {
    return rng.SeededRng.init(depthBonusSeed(world_seed, floor_index));
}

fn eliteSeed(world_seed: u64, floor_index: u32) u64 {
    return floorSeed(world_seed, floor_index) ^ 0xE11FE11FE11FE11F;
}

/// Separate stream for elite upgrades on danger floors only — does not touch
/// floor-3 `depthBonusRng` draw positions (frozen golden safety).
pub fn eliteRng(world_seed: u64, floor_index: u32) rng.SeededRng {
    return rng.SeededRng.init(eliteSeed(world_seed, floor_index));
}

fn rationSeed(world_seed: u64, floor_index: u32) u64 {
    return floorSeed(world_seed, floor_index) ^ 0xF00DF00DF00DF00D;
}

/// Separate stream for the danger-floor guaranteed ration — like `eliteRng`,
/// drawn only when `dangerTier > 0`, so floors ≤ 3 consume nothing new.
fn rationRng(world_seed: u64, floor_index: u32) rng.SeededRng {
    return rng.SeededRng.init(rationSeed(world_seed, floor_index));
}

/// Depth tier for generated floors (0 on floor 1–2 baseline). Count scaling only.
fn depthTier(floor_index: u32) u32 {
    if (floor_index < 2) return 0;
    return @min(floor_index - 2, 6);
}

/// Danger tier for lethality bonuses. 0 on floors 1–3; 1 on floor 4; 2 on floor 5+.
/// Cap 2 (product max depth 5). All v1.6 teeth gate on this so pre-1.6 goldens stay frozen.
pub fn dangerTier(floor_index: u32) u32 {
    if (floor_index < 4) return 0;
    return @min(floor_index - 3, 2);
}

pub const GeneratedFloor = struct {
    spawn: loc.Loc,
    stairs_down: ?loc.Loc,
    walkable_count: usize,
    layout_hash: u64,
};

const grid_w: usize = 24;
const grid_h: usize = 16;
const origin_x: u64 = 40;
const origin_y: u64 = 40;

fn gridToLoc(gx: usize, gy: usize) loc.Loc {
    return loc.Loc.init(origin_x + gx, origin_y + gy);
}

fn carveRoom(cells: *[grid_h][grid_w]bool, x: usize, y: usize, w: usize, h: usize) void {
    var dy: usize = 0;
    while (dy < h) : (dy += 1) {
        var dx: usize = 0;
        while (dx < w) : (dx += 1) {
            const gx = x + dx;
            const gy = y + dy;
            if (gx < grid_w and gy < grid_h) cells[gy][gx] = true;
        }
    }
}

fn carveAt(cells: *[grid_h][grid_w]bool, position: loc.Loc) void {
    if (position.x < origin_x or position.y < origin_y) return;
    const gx = position.x - origin_x;
    const gy = position.y - origin_y;
    if (gx >= grid_w or gy >= grid_h) return;
    cells[@intCast(gy)][@intCast(gx)] = true;
}

fn carveCorridor(cells: *[grid_h][grid_w]bool, from: loc.Loc, to: loc.Loc) void {
    var x = from.x;
    var y = from.y;
    while (x != to.x) {
        carveAt(cells, loc.Loc.init(x, y));
        if (x < to.x) x += 1 else x -= 1;
    }
    while (y != to.y) {
        carveAt(cells, loc.Loc.init(x, y));
        if (y < to.y) y += 1 else y -= 1;
    }
    carveAt(cells, to);
}

pub fn generateFloor(map: *terrain.TerrainMap, world_seed: u64, floor_index: u32) !GeneratedFloor {
    map.clear();
    var cells = [_][grid_w]bool{[_]bool{false} ** grid_w} ** grid_h;

    var floor_rng = floorRng(world_seed, floor_index);
    const room_count = 3 + (floor_rng.nextU8() % 3);
    var room_centers: [6]loc.Loc = undefined;
    var centers_len: usize = 0;

    var attempt: u8 = 0;
    while (centers_len < room_count and attempt < 32) : (attempt += 1) {
        const rw: usize = 4 + (floor_rng.nextU8() % 4);
        const rh: usize = 3 + (floor_rng.nextU8() % 3);
        const rx: usize = @intCast(floor_rng.nextU8() % @as(u8, @intCast(grid_w - rw - 1)));
        const ry: usize = @intCast(floor_rng.nextU8() % @as(u8, @intCast(grid_h - rh - 1)));
        carveRoom(&cells, rx, ry, rw, rh);
        const cx = origin_x + rx + rw / 2;
        const cy = origin_y + ry + rh / 2;
        room_centers[centers_len] = loc.Loc.init(cx, cy);
        centers_len += 1;
    }

    var i: usize = 1;
    while (i < centers_len) : (i += 1) {
        carveCorridor(&cells, room_centers[i - 1], room_centers[i]);
    }

    var walkable: usize = 0;
    var hash: u64 = 0;
    var gy: usize = 0;
    while (gy < grid_h) : (gy += 1) {
        var gx: usize = 0;
        while (gx < grid_w) : (gx += 1) {
            const position = gridToLoc(gx, gy);
            if (cells[gy][gx]) {
                try map.set(position, .floor);
                walkable += 1;
                hash ^= std.hash.Wyhash.hash(hash, std.mem.asBytes(&position.x));
                hash ^= std.hash.Wyhash.hash(hash, std.mem.asBytes(&position.y));
            } else {
                try map.set(position, .wall);
            }
        }
    }

    const spawn = room_centers[0];
    const stairs_loc = room_centers[centers_len - 1];
    try map.set(stairs_loc, .stairs);

    return .{
        .spawn = spawn,
        .stairs_down = stairs_loc,
        .walkable_count = walkable,
        .layout_hash = hash,
    };
}

fn offsetLoc(base: loc.Loc, dx: i64, dy: i64) loc.Loc {
    const x = @as(i64, @intCast(base.x)) + dx;
    const y = @as(i64, @intCast(base.y)) + dy;
    return loc.Loc.init(
        @intCast(if (x < 0) 0 else x),
        @intCast(if (y < 0) 0 else y),
    );
}

pub const MonsterSpawn = struct {
    kind: monsters.Kind,
    name: []const u8,
    position: loc.Loc,
    danger_tier: u32 = 0,
};

pub const MonsterPlan = struct {
    spawns: [6]MonsterSpawn,
    count: usize,
};

// `slot` is the global spawn index (< MonsterPlan capacity of 6), so mapping each
// slot to a distinct suffix keeps every spawned monster's name unique. Collapsing
// higher slots to a shared name let two live monsters share a name, which made one
// of them untargetable by name (combat.findTarget stops at the first exact match).
fn monsterName(kind: monsters.Kind, slot: usize) []const u8 {
    return switch (kind) {
        .goblin => switch (slot) {
            0 => "goblin_0",
            1 => "goblin_1",
            2 => "goblin_2",
            3 => "goblin_3",
            4 => "goblin_4",
            else => "goblin_5",
        },
        .skeleton => switch (slot) {
            0 => "skeleton_0",
            1 => "skeleton_1",
            2 => "skeleton_2",
            3 => "skeleton_3",
            4 => "skeleton_4",
            else => "skeleton_5",
        },
        .hobgoblin => switch (slot) {
            0 => "hobgoblin_0",
            1 => "hobgoblin_1",
            2 => "hobgoblin_2",
            3 => "hobgoblin_3",
            4 => "hobgoblin_4",
            else => "hobgoblin_5",
        },
        .skeleton_warrior => switch (slot) {
            0 => "skeleton_warrior_0",
            1 => "skeleton_warrior_1",
            2 => "skeleton_warrior_2",
            3 => "skeleton_warrior_3",
            4 => "skeleton_warrior_4",
            else => "skeleton_warrior_5",
        },
    };
}

pub fn planMonsterSpawns(world_seed: u64, floor_index: u32, spawn: loc.Loc) MonsterPlan {
    var floor_rng = floorRng(world_seed, floor_index);
    _ = floor_rng.nextU8();
    _ = floor_rng.nextU8();

    var list: [6]MonsterSpawn = undefined;
    var count: usize = 0;
    const d_tier = dangerTier(floor_index);

    const goblin_count = 1 + (floor_rng.nextU8() % 2);
    var g: u8 = 0;
    while (g < goblin_count and count < list.len) : (g += 1) {
        const offset_x: i64 = @intCast((floor_rng.nextU8() % 3) + 1);
        const offset_y: i64 = @as(i64, @intCast(floor_rng.nextU8() % 3)) - 1;
        list[count] = .{
            .kind = .goblin,
            .name = monsterName(.goblin, count),
            .position = offsetLoc(spawn, offset_x, offset_y),
            .danger_tier = d_tier,
        };
        count += 1;
    }

    if ((floor_rng.nextU8() % 2) == 0 and count < list.len) {
        const offset_x: i64 = -@as(i64, @intCast((floor_rng.nextU8() % 2) + 1));
        const offset_y: i64 = @intCast(floor_rng.nextU8() % 2);
        list[count] = .{
            .kind = .skeleton,
            .name = monsterName(.skeleton, 0),
            .position = offsetLoc(spawn, offset_x, offset_y),
            .danger_tier = d_tier,
        };
        count += 1;
    }

    const tier = depthTier(floor_index);
    if (tier > 0) {
        var bonus_rng = depthBonusRng(world_seed, floor_index);
        var bonus: u32 = 0;
        while (bonus < tier and count < list.len) : (bonus += 1) {
            const kind: monsters.Kind = if ((bonus_rng.nextU8() % 2) == 0) .goblin else .skeleton;
            const offset_x: i64 = @intCast((bonus_rng.nextU8() % 6) + 2);
            const offset_y: i64 = @as(i64, @intCast(bonus_rng.nextU8() % 6)) - 3;
            list[count] = .{
                .kind = kind,
                .name = monsterName(kind, count),
                .position = offsetLoc(spawn, offset_x, offset_y),
                .danger_tier = d_tier,
            };
            count += 1;
        }
    }

    // Elite upgrades: separate stream, only when danger_tier > 0 (floor ≥ 4).
    // Does not consume depthBonusRng, so floor-3 paths stay byte-identical.
    if (d_tier > 0) {
        var elite_rng = eliteRng(world_seed, floor_index);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            // ~25% chance per spawn to upgrade to the elite of its family.
            if ((elite_rng.nextU8() % 4) != 0) continue;
            const upgraded: monsters.Kind = switch (list[i].kind) {
                .goblin => .hobgoblin,
                .skeleton => .skeleton_warrior,
                .hobgoblin, .skeleton_warrior => list[i].kind,
            };
            if (upgraded == list[i].kind) continue;
            list[i].kind = upgraded;
            list[i].name = monsterName(upgraded, i);
        }
    }

    return .{ .spawns = list, .count = count };
}

pub const LootSpawn = struct {
    item: items.Id,
    position: loc.Loc,
};

pub const LootPlan = struct {
    spawns: [8]LootSpawn,
    count: usize,
};

/// Deterministic walkable-tile retry for loot placement (#33). Primary rolled
/// tile first; if unwalkable, probe a fixed ring of offsets (no extra RNG draws
/// so successful paths keep identical draw order). When the primary is
/// walkable we keep it even if another loot already claims the tile — matching
/// pre-#33 stacking so frozen goldens (reference_crawl floor-2 look) stay
/// byte-identical. Returns null only when the whole neighbourhood is unwalkable.
fn resolveLootTile(
    map: *const terrain.TerrainMap,
    primary: loc.Loc,
    occupied: []const LootSpawn,
) ?loc.Loc {
    _ = occupied;
    if (map.isWalkable(primary)) return primary;
    // Fixed ring: same order every call; no RNG.
    const ring = [_][2]i64{
        .{ 1, 0 },  .{ 0, 1 },  .{ -1, 0 }, .{ 0, -1 },
        .{ 1, 1 },  .{ 1, -1 }, .{ -1, 1 }, .{ -1, -1 },
        .{ 2, 0 },  .{ 0, 2 },  .{ -2, 0 }, .{ 0, -2 },
        .{ 2, 1 },  .{ 1, 2 },  .{ -1, 2 }, .{ -2, 1 },
    };
    for (ring) |d| {
        const pos = offsetLoc(primary, d[0], d[1]);
        if (!map.isWalkable(pos)) continue;
        return pos;
    }
    return null;
}

fn lootPosTaken(occupied: []const LootSpawn, pos: loc.Loc) bool {
    for (occupied) |entry| {
        if (entry.position.x == pos.x and entry.position.y == pos.y) return true;
    }
    return false;
}

pub fn planFloorLoot(
    world_seed: u64,
    floor_index: u32,
    spawn: loc.Loc,
    map: *const terrain.TerrainMap,
) LootPlan {
    var floor_rng = floorRng(world_seed, floor_index);
    _ = floor_rng.nextU8();
    _ = floor_rng.nextU8();
    _ = floor_rng.nextU8();

    var list: [8]LootSpawn = undefined;
    var count: usize = 0;
    const d_tier = dangerTier(floor_index);
    // Floors 1–3: legacy bandage-rich base table (frozen goldens).
    // Floor ≥ 4: no free bandage in base; ration cap applies to all placements.
    const base_table = if (d_tier > 0)
        [_]items.Id{ .antidote, .rations, .leather_armour, .war_axe }
    else
        [_]items.Id{ .bandage, .antidote, .rations, .leather_armour };
    const legacy_candidates = [_]items.Id{ .bandage, .antidote, .rations, .leather_armour };
    var rations_placed: u8 = 0;
    // v1.7 #40: raised with deep_floor_guaranteed_rations so the floor can
    // actually host the guarantee (cap was 1 when guarantee became 2).
    const ration_cap: u8 = if (d_tier > 0) deep_floor_guaranteed_rations else 1;
    var c: usize = 0;
    while (c < base_table.len and count < list.len) : (c += 1) {
        // Consume the same offset draws as the legacy 4-slot loop so floor RNG
        // for walkability checks stays aligned on shallow floors; on danger floors
        // the table itself differs (intentional scarcity, not a frozen golden path).
        const offset_x: i64 = @intCast((floor_rng.nextU8() % 4) + 1);
        const offset_y: i64 = @as(i64, @intCast(floor_rng.nextU8() % 4)) - 2;
        const primary = offsetLoc(spawn, offset_x, offset_y);
        // Floors 1–3: silent-drop on unwalkable (frozen reference_crawl / goldens).
        // Danger floors (#33): retry a fixed ring so intended counts are met.
        const pos = if (d_tier > 0)
            (resolveLootTile(map, primary, list[0..count]) orelse continue)
        else blk: {
            if (!map.isWalkable(primary)) continue;
            break :blk primary;
        };
        var item = base_table[c];
        if (d_tier > 0 and item == .rations) {
            if (rations_placed >= ration_cap) item = .antidote;
            rations_placed +%= 1;
        }
        list[count] = .{ .item = item, .position = pos };
        count += 1;
    }

    const tier = depthTier(floor_index);
    if (tier > 0 and d_tier == 0) {
        // Legacy floor-3 path: keep depthBonusRng draws and bandage-rich table frozen.
        var bonus_rng = depthBonusRng(world_seed, floor_index);
        var attempt: u8 = 0;
        const max_attempts: u8 = @intCast(tier * 4);
        while (attempt < max_attempts and count < list.len) : (attempt += 1) {
            const pick = bonus_rng.nextU8() % @as(u8, @intCast(legacy_candidates.len));
            const offset_x: i64 = @intCast((bonus_rng.nextU8() % 8) + 1);
            const offset_y: i64 = @as(i64, @intCast(bonus_rng.nextU8() % 8)) - 4;
            const pos = offsetLoc(spawn, offset_x, offset_y);
            if (!map.isWalkable(pos)) continue;
            list[count] = .{ .item = legacy_candidates[pick], .position = pos };
            count += 1;
        }
    } else if (d_tier > 0) {
        // Danger floors: scarce heals, ration cap (shared with base), weapon roster.
        // #33: retry unwalkable primaries so intended deep-floor counts land.
        var bonus_rng = depthBonusRng(world_seed, floor_index);
        const deep_table = [_]items.Id{ .antidote, .rations, .leather_armour, .war_axe, .greatsword, .bandage };
        var attempt: u8 = 0;
        const max_attempts: u8 = @intCast(d_tier); // small cap replaces tier*4 glut
        while (attempt < max_attempts and count < list.len) : (attempt += 1) {
            const pick = bonus_rng.nextU8() % @as(u8, @intCast(deep_table.len));
            const offset_x: i64 = @intCast((bonus_rng.nextU8() % 8) + 1);
            const offset_y: i64 = @as(i64, @intCast(bonus_rng.nextU8() % 8)) - 4;
            const primary = offsetLoc(spawn, offset_x, offset_y);
            const pos = resolveLootTile(map, primary, list[0..count]) orelse continue;
            var item = deep_table[pick];
            if (item == .rations) {
                // The cap counts only rations actually placed: a skipped
                // (unwalkable) draw must not burn the cap and starve the floor.
                if (rations_placed >= ration_cap) item = .antidote;
                rations_placed +%= 1;
            }
            list[count] = .{ .item = item, .position = pos };
            count += 1;
        }
    }

    if (d_tier > 0) {
        // Survival floor: every danger floor guarantees at least
        // `deep_floor_guaranteed_rations` placed rations (#40). `ration_cap`
        // bounds food from above; this bounds it from below. Dedicated
        // `rationRng` stream + deterministic fallback: floors ≤ 3 draw nothing
        // new, frozen goldens stay byte-identical.
        var placed_rations: usize = 0;
        var li: usize = 0;
        while (li < count) : (li += 1) {
            if (list[li].item == .rations) placed_rations += 1;
        }
        const monster_plan = planMonsterSpawns(world_seed, floor_index, spawn);
        var food_rng = rationRng(world_seed, floor_index);
        while (placed_rations < deep_floor_guaranteed_rations and count < list.len) {
            var placed = false;
            var attempt: u8 = 0;
            while (attempt < 16 and !placed) : (attempt += 1) {
                const offset_x: i64 = @intCast((food_rng.nextU8() % 8) + 1);
                const offset_y: i64 = @as(i64, @intCast(food_rng.nextU8() % 8)) - 4;
                const pos = offsetLoc(spawn, offset_x, offset_y);
                if (!lootTileFree(map, &monster_plan, list[0..count], pos)) continue;
                list[count] = .{ .item = .rations, .position = pos };
                count += 1;
                placed_rations += 1;
                placed = true;
            }
            if (!placed) {
                const ring = [_][2]i64{
                    .{ 1, 0 },  .{ 0, 1 },  .{ -1, 0 }, .{ 0, -1 },
                    .{ 1, 1 },  .{ 1, -1 }, .{ -1, 1 }, .{ -1, -1 },
                    .{ 2, 0 },  .{ 0, 2 },  .{ -2, 0 }, .{ 0, -2 },
                };
                for (ring) |d| {
                    const pos = offsetLoc(spawn, d[0], d[1]);
                    if (!lootTileFree(map, &monster_plan, list[0..count], pos)) continue;
                    list[count] = .{ .item = .rations, .position = pos };
                    count += 1;
                    placed_rations += 1;
                    placed = true;
                    break;
                }
            }
            if (!placed) break; // map exhausted
        }
    }
    return .{ .spawns = list, .count = count };
}

/// A tile can host the guaranteed ration: walkable, no planned loot, and no
/// planned monster spawn (loot on an entity tile is skipped at placement).
fn lootTileFree(
    map: *const terrain.TerrainMap,
    monster_plan: *const MonsterPlan,
    placed: []const LootSpawn,
    pos: loc.Loc,
) bool {
    if (!map.isWalkable(pos)) return false;
    for (placed) |entry| {
        if (entry.position.x == pos.x and entry.position.y == pos.y) return false;
    }
    var i: usize = 0;
    while (i < monster_plan.count) : (i += 1) {
        const m = monster_plan.spawns[i].position;
        if (m.x == pos.x and m.y == pos.y) return false;
    }
    return true;
}

/// v1.7 #40: guaranteed rations placed on each danger floor (bounds food from
/// below after the ration_cap bounds it from above). Was 1; raised so a
/// provisioned direct-route player can refuel once per deep floor.
pub const deep_floor_guaranteed_rations: u8 = 2;

/// Clock ticks one player move costs on this floor in the survival steady state
/// for a rested player at `rest_fatigue_floor` (exhaustion tier 1).
/// v1.7 #40: deep-floor extra tick now starts at exhaustion tier 2
/// (`movement.deep_floor_extra_tick_exhaustion_min`), so a rested player pays
/// 1 tick/move even on floor ≥ 4. Tier 2+ still pays 2.
pub fn steadyMoveTicks(floor_index: u32) u64 {
    _ = floor_index;
    return 1;
}

pub const FloorEconomy = struct {
    floor_index: u32,
    /// Rations the loot plan actually places (walkability already applied).
    plan_rations: usize,
    plan_loot: usize,
    /// BFS shortest spawn->stairs path in moves; 0 with `stairs_reachable`
    /// means the spawn room's center doubles as the stairs tile.
    stairs_distance: usize,
    stairs_reachable: bool,
    /// stairs_distance * steadyMoveTicks: the floor's minimum hunger cost for a
    /// direct crossing with zero exploration, fights, or recovery actions.
    min_cross_ticks: u64,
};

/// Deterministic food-vs-ticks audit of a generated floor: food obtainable from
/// the loot plan vs the minimum clock cost of crossing spawn->stairs. Pure
/// function of (seed, floor_index), so sweeping seeds is cheap.
pub fn auditFloorEconomy(
    allocator: std.mem.Allocator,
    world_seed: u64,
    floor_index: u32,
) !FloorEconomy {
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    const gen = try generateFloor(&map, world_seed, floor_index);
    const loot = planFloorLoot(world_seed, floor_index, gen.spawn, &map);

    var rations: usize = 0;
    var i: usize = 0;
    while (i < loot.count) : (i += 1) {
        if (loot.spawns[i].item == .rations) rations += 1;
    }

    const maybe_dist = planDirectRoute(&map, gen.spawn, gen.stairs_down orelse gen.spawn, &.{});
    const dist = maybe_dist orelse 0;
    return .{
        .floor_index = floor_index,
        .plan_rations = rations,
        .plan_loot = loot.count,
        .stairs_distance = dist,
        .stairs_reachable = maybe_dist != null,
        .min_cross_ticks = @as(u64, dist) * steadyMoveTicks(floor_index),
    };
}

/// Cardinal step of a planned direct route (decoupled from movement.Direction
/// to keep dungeon free of a movement->world->dungeon import cycle). Uses the
/// engine compass from `movement.step`: north/south move along loc.x (−/+),
/// east/west along loc.y (+/−).
pub const RouteStep = enum { north, south, east, west };

/// BFS-plan the shortest walkable route `from` -> `to` on the generated grid.
/// Fills `buf` (when large enough) with the steps in walk order and returns the
/// route length, or null when unreachable. Pass an empty buffer to get only the
/// distance. Deterministic: fixed north/south/east/west expansion order.
pub fn planDirectRoute(
    map: *const terrain.TerrainMap,
    from: loc.Loc,
    to: loc.Loc,
    buf: []RouteStep,
) ?usize {
    var dist = [_][grid_w]i32{[_]i32{-1} ** grid_w} ** grid_h;
    var parent = [_][grid_w]?RouteStep{[_]?RouteStep{null} ** grid_w} ** grid_h;
    var queue: [grid_w * grid_h][2]usize = undefined;

    const fx = gridIndex(from) orelse return null;
    const tx = gridIndex(to) orelse return null;
    if (fx[0] == tx[0] and fx[1] == tx[1]) return 0;

    dist[fx[1]][fx[0]] = 0;
    queue[0] = fx;
    var head: usize = 0;
    var tail: usize = 1;
    outer: while (head < tail) : (head += 1) {
        const cur = queue[head];
        const d = dist[cur[1]][cur[0]];
        // Engine compass (movement.step): north/south are loc.x −/+, east/west
        // are loc.y +/−. Grid axis 0 tracks loc.x, axis 1 tracks loc.y.
        const steps = [_]struct { dx: i64, dy: i64, step: RouteStep }{
            .{ .dx = -1, .dy = 0, .step = .north },
            .{ .dx = 1, .dy = 0, .step = .south },
            .{ .dx = 0, .dy = 1, .step = .east },
            .{ .dx = 0, .dy = -1, .step = .west },
        };
        for (steps) |s| {
            const nx = @as(i64, @intCast(cur[0])) + s.dx;
            const ny = @as(i64, @intCast(cur[1])) + s.dy;
            if (nx < 0 or ny < 0 or nx >= grid_w or ny >= grid_h) continue;
            const ux: usize = @intCast(nx);
            const uy: usize = @intCast(ny);
            if (dist[uy][ux] != -1) continue;
            if (!map.isWalkable(gridToLoc(ux, uy))) continue;
            dist[uy][ux] = d + 1;
            parent[uy][ux] = s.step;
            queue[tail] = .{ ux, uy };
            tail += 1;
            if (ux == tx[0] and uy == tx[1]) break :outer;
        }
    }

    const total = dist[tx[1]][tx[0]];
    if (total < 0) return null;
    const len: usize = @intCast(total);

    if (buf.len >= len) {
        // Walk parents backwards from the goal, writing steps in forward order.
        var cx = tx[0];
        var cy = tx[1];
        var remaining = len;
        while (remaining > 0) : (remaining -= 1) {
            const step = parent[cy][cx] orelse return null;
            buf[remaining - 1] = step;
            switch (step) {
                .north => cx += 1,
                .south => cx -= 1,
                .east => cy -= 1,
                .west => cy += 1,
            }
        }
    }
    return len;
}

fn gridIndex(position: loc.Loc) ?[2]usize {
    if (position.x < origin_x or position.y < origin_y) return null;
    const gx = position.x - origin_x;
    const gy = position.y - origin_y;
    if (gx >= grid_w or gy >= grid_h) return null;
    return .{ @intCast(gx), @intCast(gy) };
}

pub const TrapSpawn = struct {
    label: []const u8,
    position: loc.Loc,
};

pub const TrapPlan = struct {
    spawns: [4]TrapSpawn,
    count: usize,
};

/// Cardinal neighbours of a tile (for cut-vertex / articulation checks).
const cardinal_offsets = [_][2]i64{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } };

/// Mapped walkable only — missing tiles are NOT walkable for graph purposes
/// (TerrainMap.isWalkable defaults missing → true, which would flood BFS off-map).
fn isMappedWalkable(map: *const terrain.TerrainMap, pos: loc.Loc) bool {
    const tile = map.get(pos) orelse return false;
    return tile.isWalkable();
}

fn walkableNeighborCount(map: *const terrain.TerrainMap, pos: loc.Loc) u8 {
    var n: u8 = 0;
    for (cardinal_offsets) |d| {
        const nb = offsetLoc(pos, d[0], d[1]);
        if (isMappedWalkable(map, nb)) n += 1;
    }
    return n;
}

/// Count mapped-walkable tiles reachable from `root` without stepping on `blocked`.
/// Pass `block_active=false` for the unrestricted count.
fn reachableWalkableCount(
    map: *const terrain.TerrainMap,
    root: loc.Loc,
    blocked: loc.Loc,
    block_active: bool,
) usize {
    if (!isMappedWalkable(map, root)) return 0;
    if (block_active and root.x == blocked.x and root.y == blocked.y) return 0;

    var visited: [512]loc.Loc = undefined;
    var vcount: usize = 0;
    var queue: [512]loc.Loc = undefined;
    var head: usize = 0;
    var tail: usize = 0;
    queue[tail] = root;
    tail += 1;
    visited[vcount] = root;
    vcount += 1;

    while (head < tail) : (head += 1) {
        const cur = queue[head];
        for (cardinal_offsets) |d| {
            const nb = offsetLoc(cur, d[0], d[1]);
            if (block_active and nb.x == blocked.x and nb.y == blocked.y) continue;
            if (!isMappedWalkable(map, nb)) continue;
            var seen = false;
            var i: usize = 0;
            while (i < vcount) : (i += 1) {
                if (visited[i].x == nb.x and visited[i].y == nb.y) {
                    seen = true;
                    break;
                }
            }
            if (seen) continue;
            if (vcount >= visited.len or tail >= queue.len) break;
            visited[vcount] = nb;
            vcount += 1;
            queue[tail] = nb;
            tail += 1;
        }
    }
    return vcount;
}

/// True when `pos` is a cut-vertex for spawn→stairs connectivity: removing it
/// disconnects the stairs from the spawn. These are sole-path chokepoints —
/// traps there force unavoidable damage (#43). Open rooms and bypassable
/// corridors return false. Stairs tile itself is also protected.
pub fn isWalkableCutVertex(
    map: *const terrain.TerrainMap,
    spawn: loc.Loc,
    pos: loc.Loc,
) bool {
    if (!isMappedWalkable(map, pos)) return false;
    if (pos.x == spawn.x and pos.y == spawn.y) return false;
    // Find stairs (or any descend trigger) on the map.
    var stairs: ?loc.Loc = null;
    var it = map.tiles.iterator();
    while (it.next()) |e| {
        if (e.value_ptr.* == .stairs) {
            stairs = e.key_ptr.*;
            break;
        }
    }
    const goal = stairs orelse return false;
    if (pos.x == goal.x and pos.y == goal.y) return true; // never trap the stairs
    // Reachable stairs without the tile?
    if (!isReachable(map, spawn, goal, pos, false)) return false; // stairs already unreachable
    if (!isReachable(map, spawn, goal, pos, true)) return true; // sole path through pos
    return false;
}

fn isReachable(
    map: *const terrain.TerrainMap,
    start: loc.Loc,
    goal: loc.Loc,
    blocked: loc.Loc,
    block_active: bool,
) bool {
    if (!isMappedWalkable(map, start)) return false;
    if (block_active and start.x == blocked.x and start.y == blocked.y) return false;
    if (start.x == goal.x and start.y == goal.y) return true;

    var visited: [512]loc.Loc = undefined;
    var vcount: usize = 0;
    var queue: [512]loc.Loc = undefined;
    var head: usize = 0;
    var tail: usize = 0;
    queue[tail] = start;
    tail += 1;
    visited[vcount] = start;
    vcount += 1;

    while (head < tail) : (head += 1) {
        const cur = queue[head];
        for (cardinal_offsets) |d| {
            const nb = offsetLoc(cur, d[0], d[1]);
            if (block_active and nb.x == blocked.x and nb.y == blocked.y) continue;
            if (!isMappedWalkable(map, nb)) continue;
            if (nb.x == goal.x and nb.y == goal.y) return true;
            var seen = false;
            var i: usize = 0;
            while (i < vcount) : (i += 1) {
                if (visited[i].x == nb.x and visited[i].y == nb.y) {
                    seen = true;
                    break;
                }
            }
            if (seen) continue;
            if (vcount >= visited.len or tail >= queue.len) break;
            visited[vcount] = nb;
            vcount += 1;
            queue[tail] = nb;
            tail += 1;
        }
    }
    return false;
}

pub fn planTrapSpawns(
    world_seed: u64,
    floor_index: u32,
    spawn: loc.Loc,
    map: *const terrain.TerrainMap,
) TrapPlan {
    if (floor_index < 2) return .{ .spawns = undefined, .count = 0 };

    var trap_rng = trapRng(world_seed, floor_index);
    const tier = depthTier(floor_index);
    const trap_cap: u8 = @intCast(1 + tier / 2);
    const trap_count = 1 + (trap_rng.nextU8() % trap_cap);

    var list: [4]TrapSpawn = undefined;
    var count: usize = 0;
    var attempt: u8 = 0;
    while (count < trap_count and attempt < 48) : (attempt += 1) {
        const offset_x: i64 = @intCast((trap_rng.nextU8() % 6) + 1);
        const offset_y: i64 = @as(i64, @intCast(trap_rng.nextU8() % 6)) - 3;
        const pos = offsetLoc(spawn, offset_x, offset_y);
        if (!map.isWalkable(pos)) continue;
        if (pos.x == spawn.x and pos.y == spawn.y) continue;
        // #43: never place a trap on a sole-path cut-vertex of the walkable graph.
        if (isWalkableCutVertex(map, spawn, pos)) continue;
        var dup: usize = 0;
        while (dup < count) : (dup += 1) {
            if (list[dup].position.x == pos.x and list[dup].position.y == pos.y) break;
        }
        if (dup < count) continue;
        list[count] = .{ .label = "poison_trap", .position = pos };
        count += 1;
    }
    return .{ .spawns = list, .count = count };
}

test "floor1 blocks north of spawn" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    try loadFloor1(&map, .v09);
    try std.testing.expect(!map.isWalkable(loc.Loc.init(48, 49)));
    try std.testing.expect(map.isWalkable(loc.Loc.init(49, 49)));
    try std.testing.expect(map.isWalkable(floor1_stairs_v09));
}

test "floor1 v08 blocks east corridor to door" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    try loadFloor1(&map, .v08);
    try std.testing.expect(!map.isWalkable(loc.Loc.init(49, 51)));
}

test "floor1 v09 stairs reachable from spawn via south-east exit" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    try loadFloor1(&map, .v09);
    try std.testing.expect(!map.isWalkable(loc.Loc.init(49, 51)));

    const path = [_]loc.Loc{
        loc.Loc.init(49, 50),
        loc.Loc.init(50, 50),
        floor1_stairs_v09,
    };
    for (path) |tile| try std.testing.expect(map.isWalkable(tile));

    const stairs_tile = map.get(floor1_stairs_v09) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(terrain.Tile.stairs, stairs_tile);
}

test "generated floor is deterministic for same seed" {
    const allocator = std.testing.allocator;
    var a = terrain.TerrainMap.init(allocator);
    defer a.deinit();
    var b = terrain.TerrainMap.init(allocator);
    defer b.deinit();

    const ga = try generateFloor(&a, 42, 2);
    const gb = try generateFloor(&b, 42, 2);
    try std.testing.expectEqual(ga.walkable_count, gb.walkable_count);
    try std.testing.expectEqual(ga.layout_hash, gb.layout_hash);
    try std.testing.expectEqual(ga.spawn.x, gb.spawn.x);
    try std.testing.expectEqual(ga.spawn.y, gb.spawn.y);
    @import("evidence_format.zig").printLayoutEvidence(42, 2, ga);
}

test "generated floor differs across floor index" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();

    const f2 = try generateFloor(&map, 99, 2);
    const f3 = try generateFloor(&map, 99, 3);
    try std.testing.expect(f2.layout_hash != f3.layout_hash or f2.walkable_count != f3.walkable_count);
}

test "monster spawn plan is deterministic" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    const gen = try generateFloor(&map, 42, 2);

    const a = planMonsterSpawns(42, 2, gen.spawn);
    const b = planMonsterSpawns(42, 2, gen.spawn);
    try std.testing.expectEqual(a.count, b.count);
    try std.testing.expectEqualStrings(a.spawns[0].name, b.spawns[0].name);
    try std.testing.expectEqual(a.spawns[0].position.x, b.spawns[0].position.x);
}

test "deeper floors scale monster and loot counts on seed 42" {
    const allocator = std.testing.allocator;
    var map2 = terrain.TerrainMap.init(allocator);
    defer map2.deinit();
    var map5 = terrain.TerrainMap.init(allocator);
    defer map5.deinit();

    const gen2 = try generateFloor(&map2, 42, 2);
    const gen5 = try generateFloor(&map5, 42, 5);
    const monsters2 = planMonsterSpawns(42, 2, gen2.spawn);
    const monsters5 = planMonsterSpawns(42, 5, gen5.spawn);
    const loot2 = planFloorLoot(42, 2, gen2.spawn, &map2);
    const loot5 = planFloorLoot(42, 5, gen5.spawn, &map5);

    // Monsters still scale with depth. Loot total can match or exceed shallow
    // floors once #33 retry fills intended slots; scarcity is in *heals*
    // (no free base bandage on danger floors) and fewer bonus rolls.
    try std.testing.expectEqual(@as(usize, 3), monsters2.count);
    try std.testing.expectEqual(@as(usize, 4), loot2.count);
    try std.testing.expect(monsters5.count > monsters2.count);
    try std.testing.expectEqual(@as(usize, 5), monsters5.count);
    try std.testing.expect(loot5.count >= 1); // #33: intended slots fill; ration floor holds
    var bandages5: usize = 0;
    var bi: usize = 0;
    while (bi < loot5.count) : (bi += 1) {
        if (loot5.spawns[bi].item == .bandage) bandages5 += 1;
    }
    // Danger base table has no bandage; bonus may add at most d_tier rolls.
    try std.testing.expect(bandages5 <= dangerTier(5));
    try std.testing.expectEqual(@as(u32, 2), dangerTier(5));
    try std.testing.expectEqual(@as(u32, 0), dangerTier(3));
}

test "eliteRng upgrades only on danger floors" {
    const allocator = std.testing.allocator;
    var map3 = terrain.TerrainMap.init(allocator);
    defer map3.deinit();
    const gen3 = try generateFloor(&map3, 42, 3);

    const plan3 = planMonsterSpawns(42, 3, gen3.spawn);
    var i: usize = 0;
    while (i < plan3.count) : (i += 1) {
        try std.testing.expect(!monsters.isElite(plan3.spawns[i].kind));
        try std.testing.expectEqual(@as(u32, 0), plan3.spawns[i].danger_tier);
    }

    // Search a band of seeds for a natural elite upgrade on floor 4 (eliteRng ~25%/spawn).
    var found_elite = false;
    var seed: u64 = 1;
    while (seed < 64) : (seed += 1) {
        var map = terrain.TerrainMap.init(allocator);
        defer map.deinit();
        const gen = try generateFloor(&map, seed, 4);
        const plan = planMonsterSpawns(seed, 4, gen.spawn);
        var j: usize = 0;
        while (j < plan.count) : (j += 1) {
            try std.testing.expectEqual(@as(u32, 1), plan.spawns[j].danger_tier);
            if (monsters.isElite(plan.spawns[j].kind)) {
                found_elite = true;
                // Name tracks the upgraded kind.
                try std.testing.expect(std.mem.indexOf(u8, plan.spawns[j].name, "hobgoblin") != null or
                    std.mem.indexOf(u8, plan.spawns[j].name, "skeleton_warrior") != null);
            }
        }
        if (found_elite) break;
    }
    try std.testing.expect(found_elite);
}

test "danger floor base loot has no free bandage glut" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    const gen = try generateFloor(&map, 42, 5);
    const loot = planFloorLoot(42, 5, gen.spawn, &map);
    var bandages: usize = 0;
    var rations: usize = 0;
    var i: usize = 0;
    while (i < loot.count) : (i += 1) {
        if (loot.spawns[i].item == .bandage) bandages += 1;
        if (loot.spawns[i].item == .rations) rations += 1;
    }
    // Base table drops bandage; deep bonus may add at most ~1-in-6.
    // Ration cap tracks deep_floor_guaranteed_rations (#40).
    try std.testing.expect(bandages <= 1);
    try std.testing.expect(rations <= deep_floor_guaranteed_rations);
}

test "danger floors always plan at least one ration and reachable stairs (seed sweep)" {
    // v1.6 survival floor: scarcity caps food from above (ration_cap), the
    // guaranteed ration bounds it from below. Before the guarantee, ~half of
    // all seeds generated zero food on floors whose steady move cost is
    // 2 ticks/move — starvation by seed roll (playtest seed 7, floor 4).
    const allocator = std.testing.allocator;
    var seed: u64 = 1;
    while (seed <= 64) : (seed += 1) {
        var floor: u32 = 4;
        while (floor <= 5) : (floor += 1) {
            const econ = try auditFloorEconomy(allocator, seed, floor);
            try std.testing.expect(econ.plan_rations >= deep_floor_guaranteed_rations);
            // Distance 0 is legal (seed 44 floor 4 spawns on the stairs tile);
            // unreachable stairs are not.
            try std.testing.expect(econ.stairs_reachable);
        }
    }
}

test "planDirectRoute matches audited stairs distance on seed 42 floor 4" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    const gen = try generateFloor(&map, 42, 4);
    const stairs = gen.stairs_down orelse return error.TestUnexpectedResult;

    var route: [512]RouteStep = undefined;
    const len = planDirectRoute(&map, gen.spawn, stairs, &route) orelse
        return error.TestUnexpectedResult;
    const econ = try auditFloorEconomy(allocator, 42, 4);
    try std.testing.expectEqual(econ.stairs_distance, len);

    // Replaying the route lands exactly on the stairs tile via walkable tiles
    // (engine compass: north/south move loc.x, east/west move loc.y).
    var at = gen.spawn;
    for (route[0..len]) |step| {
        at = switch (step) {
            .north => loc.Loc.init(at.x - 1, at.y),
            .south => loc.Loc.init(at.x + 1, at.y),
            .east => loc.Loc.init(at.x, at.y + 1),
            .west => loc.Loc.init(at.x, at.y - 1),
        };
        try std.testing.expect(map.isWalkable(at));
    }
    try std.testing.expectEqual(stairs.x, at.x);
    try std.testing.expectEqual(stairs.y, at.y);
}

test "trap spawn plan is deterministic and places poison traps" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    const gen = try generateFloor(&map, 42, 2);

    const a = planTrapSpawns(42, 2, gen.spawn, &map);
    const b = planTrapSpawns(42, 2, gen.spawn, &map);
    try std.testing.expect(a.count > 0);
    try std.testing.expectEqual(a.count, b.count);
    try std.testing.expectEqualStrings("poison_trap", a.spawns[0].label);
    try std.testing.expect(map.isWalkable(a.spawns[0].position));
    // Positions may shift when cut-vertices are skipped (#43); pin determinism only.
    try std.testing.expectEqual(a.spawns[0].position.x, b.spawns[0].position.x);
    try std.testing.expectEqual(a.spawns[0].position.y, b.spawns[0].position.y);
}

test "loot plan retries unwalkable primary tiles" {
    // #33: a rolled unwalkable primary must still place when a neighbour is free.
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    // Tiny room: spawn walkable, primary offset often wall; resolveLootTile should recover.
    try map.set(loc.Loc.init(50, 50), .floor);
    try map.set(loc.Loc.init(50, 51), .floor);
    try map.set(loc.Loc.init(50, 52), .floor);
    try map.set(loc.Loc.init(51, 50), .floor);
    try map.set(loc.Loc.init(51, 51), .floor);
    try map.set(loc.Loc.init(49, 50), .wall);
    try map.set(loc.Loc.init(49, 51), .wall);
    const spawn = loc.Loc.init(50, 50);
    // Sweep seeds; at least one danger-floor plan must place its base table items
    // (retry keeps count above the silent-drop baseline of zero on sparse rooms).
    var any_loot = false;
    var seed: u64 = 1;
    while (seed <= 32) : (seed += 1) {
        const plan = planFloorLoot(seed, 4, spawn, &map);
        if (plan.count > 0) any_loot = true;
    }
    try std.testing.expect(any_loot);
}

test "no trap on a spawn-to-stairs cut-vertex" {
    // #43: sole-path chokepoints (spawn↔stairs) must never host a trap.
    const allocator = std.testing.allocator;
    var seed: u64 = 1;
    var any_trap = false;
    while (seed <= 48) : (seed += 1) {
        var map = terrain.TerrainMap.init(allocator);
        defer map.deinit();
        const gen = try generateFloor(&map, seed, 2);
        const plan = planTrapSpawns(seed, 2, gen.spawn, &map);
        if (plan.count > 0) any_trap = true;
        var i: usize = 0;
        while (i < plan.count) : (i += 1) {
            try std.testing.expect(!isWalkableCutVertex(&map, gen.spawn, plan.spawns[i].position));
        }
    }
    try std.testing.expect(any_trap);
}

test "floor 1 has no trap plan" {
    const allocator = std.testing.allocator;
    var map = terrain.TerrainMap.init(allocator);
    defer map.deinit();
    try loadFloor1(&map, .v09);
    const plan = planTrapSpawns(42, 1, floor1_spawn, &map);
    try std.testing.expectEqual(@as(usize, 0), plan.count);
}
