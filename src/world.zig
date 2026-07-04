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
            1 => try dungeon.loadFloor1(&self.terrain),
            else => return error.UnknownFloor,
        }
        self.floor_index = index;
        self.has_dungeon = true;
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

    fn initCharacterHp(char: *types.Character) void {
        if (char.max_hp == 0) char.max_hp = character.maxHpLevel1(char);
        if (char.current_hp == 0) char.current_hp = char.max_hp;
    }

    /// Takes ownership of `character`; freed when the world is torn down.
    pub fn spawnPlayer(self: *World, char_ptr: *types.Character, position: loc.Loc, name: []const u8) !entity.EntityId {
        initCharacterHp(char_ptr);
        const id = self.next_entity_id;
        self.next_entity_id += 1;
        _ = try self.store.create(self.allocator, id, name, position, char_ptr);
        try self.tile_map.place(position, id);
        if (self.store.get(id)) |ent| ent.loc = position;
        return id;
    }

    pub fn spawnMonster(self: *World, kind: monsters.Kind, position: loc.Loc, name: []const u8) !entity.EntityId {
        const char_ptr = try monsters.buildCharacter(self.allocator, kind);
        return self.spawnPlayer(char_ptr, position, name);
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