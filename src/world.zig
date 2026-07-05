const std = @import("std");
const rng = @import("rng.zig");
const types = @import("types.zig");
const clock = @import("clock.zig");
const loc = @import("loc.zig");
const entity = @import("entity.zig");
const map = @import("map.zig");
const terrain = @import("terrain.zig");
const dungeon = @import("dungeon.zig");
const character = @import("character.zig");
const combat = @import("combat.zig");
const monsters = @import("monsters.zig");

pub const World = struct {
    allocator: std.mem.Allocator,
    seed: u64,
    rng: rng.SeededRng,
    store: entity.EntityStore,
    tile_map: map.TileMap,
    terrain: terrain.TerrainMap,
    floor_index: u32 = 0,
    floor_spawn: loc.Loc = loc.Loc.init(49, 49),
    has_dungeon: bool = false,
    races: std.ArrayList(types.Race),
    game_clock: clock.Clock,
    next_entity_id: entity.EntityId,
    staged_character: ?*types.Character = null,
    combat: ?*combat.CombatState = null,

    pub fn init(allocator: std.mem.Allocator, seed: u64) !World {
        var races = try types.defaultRaces(allocator);
        errdefer types.deinitRaceList(allocator, &races);

        return .{
            .allocator = allocator,
            .seed = seed,
            .rng = rng.SeededRng.init(seed),
            .store = entity.EntityStore.init(),
            .tile_map = map.TileMap.init(allocator),
            .terrain = terrain.TerrainMap.init(allocator),
            .races = races,
            .game_clock = clock.Clock.init(0.45, 120.0, 5.0, 1.0),
            .next_entity_id = 0,
            .staged_character = null,
        };
    }

    pub fn deinit(self: *World) void {
        combat.endCombat(self);
        if (self.staged_character) |char| self.destroyCharacter(char);
        self.staged_character = null;
        self.store.deinit(self.allocator);
        self.tile_map.deinit();
        self.terrain.deinit();
        types.deinitRaceList(self.allocator, &self.races);
    }

    pub fn loadFloor(self: *World, index: u32) !void {
        switch (index) {
            1 => {
                try dungeon.loadFloor1(&self.terrain);
                self.floor_spawn = loc.Loc.init(49, 49);
            },
            else => {
                const gen = try dungeon.generateFloor(&self.terrain, self.seed, index);
                self.floor_spawn = gen.spawn;
            },
        }
        self.floor_index = index;
        self.has_dungeon = true;
    }

    pub fn placeFloorMonsters(self: *World) !void {
        if (self.floor_index < 2) return;
        const plan = dungeon.planMonsterSpawns(self.seed, self.floor_index, self.floor_spawn);
        var i: usize = 0;
        while (i < plan.count) : (i += 1) {
            const spawn = plan.spawns[i];
            if (!self.terrain.isWalkable(spawn.position)) continue;
            _ = try self.spawnMonster(spawn.kind, spawn.position, spawn.name);
        }
    }

    pub fn removeAllMonsters(self: *World) void {
        var to_remove: [32]entity.EntityId = undefined;
        var n: usize = 0;
        for (self.store.entities.items) |ent| {
            if (ent.is_monster and n < to_remove.len) {
                to_remove[n] = ent.id;
                n += 1;
            }
        }
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const id = to_remove[i];
            if (self.store.get(id)) |ent| {
                self.tile_map.remove(ent.loc, id);
            }
            self.store.remove(self.allocator, id);
        }
    }

    pub fn relocatePlayer(self: *World, player_id: entity.EntityId, position: loc.Loc) !void {
        const ent = self.store.get(player_id) orelse return error.EntityNotFound;
        self.tile_map.remove(ent.loc, player_id);
        ent.loc = position;
        try self.tile_map.place(position, player_id);
    }

    pub fn descend(self: *World, player_id: entity.EntityId) !void {
        const ent = self.store.get(player_id) orelse return error.EntityNotFound;
        const tile = self.terrain.get(ent.loc) orelse return error.NotOnStairs;
        if (!tile.isDescendTrigger()) return error.NotOnStairs;
        if (combat.isInCombat(self)) return error.InCombat;
        if (ent.char.status == .fighting) return error.InCombat;

        combat.endCombat(self);
        self.removeAllMonsters();

        const next_floor = self.floor_index + 1;
        try self.loadFloor(next_floor);
        try self.relocatePlayer(player_id, self.floor_spawn);
        try self.placeFloorMonsters();
        self.tick();
    }

    fn destroyCharacter(self: *World, char: *types.Character) void {
        char.attributes.deinit(self.allocator);
        self.allocator.destroy(char);
    }

    /// Takes ownership of `char`; freed on `deinit` (via entity store or staged discard).
    pub fn stageCharacter(self: *World, char: *types.Character) void {
        if (self.staged_character) |old| self.destroyCharacter(old);
        self.staged_character = char;
    }

    pub fn spawnStagedPlayer(self: *World, position: loc.Loc, name: []const u8) !entity.EntityId {
        const char = self.staged_character orelse return error.NoStagedCharacter;
        self.staged_character = null;
        return self.spawnPlayer(char, position, name);
    }

    fn initEntityCombat(ent: *entity.Entity) void {
        if (ent.is_monster) return;
        ent.max_hp = character.maxHpLevel1(ent.char);
        ent.current_hp = ent.max_hp;
        ent.damage_die = ent.char.class.hit_die;
    }

    /// Takes ownership of `character`; freed when the world is torn down.
    pub fn spawnPlayer(self: *World, char_ptr: *types.Character, position: loc.Loc, name: []const u8) !entity.EntityId {
        const id = self.next_entity_id;
        self.next_entity_id += 1;
        _ = try self.store.create(self.allocator, id, name, position, char_ptr);
        try self.tile_map.place(position, id);
        if (self.store.get(id)) |ent| {
            ent.loc = position;
            initEntityCombat(ent);
        }
        return id;
    }

    pub fn spawnMonster(self: *World, kind: monsters.Kind, position: loc.Loc, name: []const u8) !entity.EntityId {
        const b = monsters.block(kind);
        const char_ptr = try monsters.buildCharacter(self.allocator, kind);
        const id = try self.spawnPlayer(char_ptr, position, name);
        if (self.store.get(id)) |ent| {
            ent.is_monster = true;
            ent.max_hp = b.max_hp;
            ent.current_hp = b.max_hp;
            ent.damage_die = b.damage_die;
        }
        return id;
    }

    /// Test helper: allocates a character owned by the world until `deinit`.
    pub fn spawnTestPlayer(self: *World, position: loc.Loc) !entity.EntityId {
        const attrs = try types.defaultAttributes(self.allocator);
        const char = try self.allocator.create(types.Character);
        char.* = .{
            .name = "George",
            .attributes = attrs,
            .race = self.races.items[0],
            .class = types.defaultClasses()[0],
        };
        return self.spawnPlayer(char, position, "entity_0");
    }

    pub fn tick(self: *World) void {
        self.game_clock.tick();
    }

    pub fn snapshot(self: *const World) Snapshot {
        return .{
            .seed = self.seed,
            .entity_count = self.store.count(),
            .occupied_cells = self.tile_map.occupiedCellCount(),
            .clock_ticks = self.game_clock.ticks,
            .rng_offset = self.rng.offset,
        };
    }
};

pub const Snapshot = struct {
    seed: u64,
    entity_count: usize,
    occupied_cells: usize,
    clock_ticks: u64,
    rng_offset: u16,
};

test "world init place deinit lifecycle via single teardown path" {
    const allocator = std.testing.allocator;

    var world = try World.init(allocator, 42);
    defer world.deinit();

    const id = try world.spawnTestPlayer(loc.Loc.init(49, 49));
    try std.testing.expectEqual(@as(entity.EntityId, 0), id);
    try std.testing.expectEqual(@as(usize, 1), world.store.count());
    try std.testing.expectEqual(@as(usize, 1), world.tile_map.occupiedCellCount());
    try std.testing.expectEqual(@as(usize, 1), world.tile_map.entityCountAt(loc.Loc.init(49, 49)));
}

test "world deinit frees staged character" {
    const allocator = std.testing.allocator;
    var world = try World.init(allocator, 1);
    defer world.deinit();

    const boot = try @import("session.zig").bootstrapCharacter(allocator, &world, "George");
    world.stageCharacter(boot.character);
}

test "same seed yields identical world snapshot after spawn" {
    const allocator = std.testing.allocator;

    var a = try World.init(allocator, 99);
    defer a.deinit();
    var b = try World.init(allocator, 99);
    defer b.deinit();

    _ = try a.spawnTestPlayer(loc.Loc.init(49, 49));
    _ = try b.spawnTestPlayer(loc.Loc.init(49, 49));

    const sa = a.snapshot();
    const sb = b.snapshot();
    try std.testing.expectEqual(sa.seed, sb.seed);
    try std.testing.expectEqual(sa.entity_count, sb.entity_count);
    try std.testing.expectEqual(sa.occupied_cells, sb.occupied_cells);
    try std.testing.expectEqual(sa.clock_ticks, sb.clock_ticks);
    try std.testing.expectEqual(sa.rng_offset, sb.rng_offset);
}