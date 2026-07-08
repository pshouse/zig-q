const std = @import("std");
const rng = @import("rng.zig");
const world = @import("world.zig");
const entity = @import("entity.zig");
const session = @import("session.zig");
const commands = @import("commands.zig");
const combat = @import("combat.zig");
const conditions = @import("conditions.zig");
const loc = @import("loc.zig");
const transcript = @import("transcript.zig");
const save_state = @import("save_state.zig");
const sqlite_store = @import("sqlite_store.zig");

pub const Config = struct {
    seed: u64 = 0,
    iterations: u32 = 10_000,
    max_commands: u8 = 32,
    world_seed: u64 = 42,
    db_path: []const u8 = "zig-q-fuzz.sqlite",
};

pub const Failure = struct {
    iteration: u32,
    step: u32,
    message: []const u8,
    script: []const []const u8,
};

pub const Report = struct {
    iterations: u32,
    failure: ?Failure = null,

    pub fn passed(self: Report) bool {
        return self.failure == null;
    }
};

const templates = [_][]const u8{
    "",
    "look",
    "time",
    "help",
    "exit",
    "roll",
    "spawn",
    "stats",
    "assign",
    "assign 1 2 3 4 5 6",
    "assign 6 5 4 3 2 1",
    "assign 0 0 0 0 0 0",
    "assign 9 9 9 9 9 9",
    "race",
    "race 0",
    "race 1",
    "race 2",
    "race 3",
    "race 99",
    "class",
    "class 1",
    "class 3",
    "class 99",
    "move north",
    "move south",
    "move east",
    "move west",
    "move north",
    "move north",
    "move south",
    "move up",
    "move ",
    "l",
    "stats before spawn",
    "attack",
    "attack goblin_0",
    "attack skeleton_0",
    "end turn",
    "save",
    "save 1",
    "load 1",
    "load 2",
    "descend",
    "wait",
    "conditions",
    "open north",
    "open south",
    "close north",
    "use antidote",
    "equip short sword",
    "drop short sword",
    "unequip weapon",
    "unequip armour",
    "unequip short sword",
    "take off armour",
};

pub fn run(allocator: std.mem.Allocator, cfg: Config) !Report {
    var fuzz_rng = rng.SeededRng.init(cfg.seed);
    var script_lines: std.ArrayList([]const u8) = .empty;
    defer {
        for (script_lines.items) |line| allocator.free(line);
        script_lines.deinit(allocator);
    }

    var iteration: u32 = 0;
    while (iteration < cfg.iterations) : (iteration += 1) {
        for (script_lines.items) |line| allocator.free(line);
        script_lines.clearRetainingCapacity();

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var w = try world.World.init(a, cfg.world_seed);
        defer w.deinit();
        try w.loadFloor(1);

        var draft: session.CreationDraft = .{};
        _ = session.draftRoll(&w, &draft);

        const fuzz_db = cfg.db_path;
        sqlite_store.deleteDb(fuzz_db);

        var ctx = commands.Context{
            .allocator = a,
            .w = &w,
            .draft = &draft,
            .save_path = fuzz_db,
        };

        var null_out: [1]u8 = undefined;
        var null_stream = std.io.fixedBufferStream(&null_out);

        var osc_tracker: OscillationTracker = .{};
        var step: u32 = 0;
        while (step < cfg.max_commands) : (step += 1) {
            const line = try generateLine(a, &fuzz_rng);
            try script_lines.append(allocator, try allocator.dupe(u8, line));

            const result = commands.executeLine(&ctx, line, null_stream.writer()) catch {
                assertInvariantsTracked(&w, ctx.player_id, &osc_tracker) catch |inv_err| {
                    return failureReport(cfg.iterations, iteration, step, inv_err, &script_lines);
                };
                continue;
            };

            if (ctx.player_id != entity.invalid_id and countLiveMonsters(&w) == 0) {
                _ = w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0") catch {};
                _ = w.spawnMonster(.skeleton, loc.Loc.init(49, 50), "skeleton_0") catch {};
            }

            assertInvariantsTracked(&w, ctx.player_id, &osc_tracker) catch |inv_err| {
                return failureReport(cfg.iterations, iteration, step, inv_err, &script_lines);
            };

            if (ctx.player_id != entity.invalid_id and (std.mem.eql(u8, line, "save") or std.mem.startsWith(u8, line, "save "))) {
                verifySaveRoundtrip(a, fuzz_db, &w, ctx.player_id) catch |inv_err| {
                    return failureReport(cfg.iterations, iteration, step, inv_err, &script_lines);
                };
            }

            switch (result) {
                .continue_repl => {},
                .exit_repl => break,
            }
        }
    }

    return .{ .iterations = cfg.iterations };
}

fn failureReport(
    iterations: u32,
    iteration: u32,
    step: u32,
    err: anyerror,
    script_lines: *const std.ArrayList([]const u8),
) Report {
    return .{
        .iterations = iterations,
        .failure = .{
            .iteration = iteration,
            .step = step,
            .message = @errorName(err),
            .script = script_lines.items,
        },
    };
}

pub fn runOne(
    allocator: std.mem.Allocator,
    world_seed: u64,
    script: []const []const u8,
) !void {
    var w = try world.World.init(allocator, world_seed);
    defer w.deinit();
    try w.loadFloor(1);

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);

    var ctx = commands.Context{
        .allocator = allocator,
        .w = &w,
        .draft = &draft,
    };

    var out_buf: [8192]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&out_buf);
    var out = transcript.Output(@TypeOf(out_stream.writer())){
        .stdout = out_stream.writer(),
        .session = null,
    };

    for (script) |line| {
        try out.print("> {s}\n", .{line});
        const result = try commands.executeLine(&ctx, line, &out);
        try assertInvariants(&w, ctx.player_id);
        if (result == .exit_repl) return;
    }
}

fn verifySaveRoundtrip(
    allocator: std.mem.Allocator,
    path: []const u8,
    w: *const world.World,
    player_id: entity.EntityId,
) !void {
    var before = try save_state.capture(allocator, w, player_id);
    defer before.deinit(allocator);

    var null_buf: [1]u8 = undefined;
    var null_stream = std.io.fixedBufferStream(&null_buf);
    try sqlite_store.saveSlot(allocator, path, 1, w, player_id, null_stream.writer());

    var loaded = try sqlite_store.loadSlot(allocator, path, 1, null_stream.writer());
    defer loaded.world.deinit();

    var after = try save_state.capture(allocator, &loaded.world, loaded.player_id);
    defer after.deinit(allocator);
    try save_state.expectEqual(&before, &after);
}

fn countLiveMonsters(w: *const world.World) usize {
    var n: usize = 0;
    for (w.store.entities.items) |ent| {
        if (ent.is_monster and !ent.conditions.has(.dead) and ent.current_hp > 0) n += 1;
    }
    return n;
}

pub const max_floor_depth: u32 = 5;

const OscillationTracker = struct {
    entries: [32]struct {
        id: entity.EntityId,
        ring: [4]loc.Loc,
        len: u8,
    } = undefined,
    count: u8 = 0,

    fn find(self: *OscillationTracker, id: entity.EntityId) *@TypeOf(self.entries[0]) {
        var i: u8 = 0;
        while (i < self.count) : (i += 1) {
            if (self.entries[i].id == id) return &self.entries[i];
        }
        const slot = &self.entries[self.count];
        slot.* = .{ .id = id, .ring = undefined, .len = 0 };
        self.count += 1;
        return slot;
    }

    pub fn record(self: *OscillationTracker, id: entity.EntityId, at: loc.Loc) !void {
        const slot = self.find(id);
        if (slot.len > 0 and slot.ring[(slot.len - 1) % 4].x == at.x and slot.ring[(slot.len - 1) % 4].y == at.y) return;
        slot.ring[slot.len % 4] = at;
        slot.len +%= 1;
        if (slot.len >= 4) {
            const a = slot.ring[(slot.len - 4) % 4];
            const b = slot.ring[(slot.len - 3) % 4];
            const c = slot.ring[(slot.len - 2) % 4];
            const d = slot.ring[(slot.len - 1) % 4];
            if (a.x == c.x and a.y == c.y and b.x == d.x and b.y == d.y and
                (a.x != b.x or a.y != b.y))
            {
                return error.PathOscillation;
            }
        }
    }
};

fn trackMonsterPositions(w: *world.World, tracker: *OscillationTracker) !void {
    for (w.store.entities.items) |ent| {
        if (!ent.is_monster or ent.conditions.has(.dead) or ent.current_hp == 0) continue;
        try tracker.record(ent.id, ent.loc);
    }
}

pub fn assertInvariants(w: *world.World, player_id: entity.EntityId) !void {
    return assertInvariantsTracked(w, player_id, null);
}

pub fn assertInvariantsTracked(
    w: *world.World,
    player_id: entity.EntityId,
    tracker: ?*OscillationTracker,
) !void {
    if (w.floor_index > max_floor_depth) return error.FloorDepthExceeded;

    var players: usize = 0;
    for (w.store.entities.items) |ent| {
        if (!ent.is_monster) players += 1;
    }
    if (players > 1) return error.TooManyPlayers;
    var on_map: usize = 0;
    for (w.store.entities.items) |*ent| {
        // HP must remain within [0, max_hp] (u32 guarantees >= 0; upper bound explicit).
        if (ent.max_hp > 0 and ent.current_hp > ent.max_hp) return error.HpAboveMax;
        if (ent.conditions.has(.dead) and ent.current_hp != 0) return error.DeadWithPositiveHp;
        if (!ent.conditions.has(.dead) and ent.max_hp > 0 and ent.current_hp == 0) return error.AliveWithZeroHp;
        on_map += 1;
        const list = w.tile_map.cells.get(ent.loc) orelse return error.EntityNotOnMap;
        var found = false;
        for (list.items) |eid| {
            if (eid == ent.id) found = true;
        }
        if (!found) return error.EntityLocMismatch;
    }

    if (on_map != w.store.count()) return error.EntityCountMismatch;
    if (w.store.count() < w.tile_map.occupiedCellCount()) return error.OrphanMapCell;

    if (player_id != entity.invalid_id and w.store.get(player_id) == null)
        return error.MissingPlayer;

    if (w.isPlayerDead()) {
        if (combat.isInCombat(w)) return error.DeadPlayerInCombat;
        if (player_id != entity.invalid_id) {
            const player = w.store.get(player_id) orelse return error.MissingPlayer;
            if (!conditions.isDead(player)) return error.DeadFlagMismatch;
        }
    }

    if (w.has_dungeon) {
        for (w.store.entities.items) |ent| {
            if (!w.terrain.isWalkable(ent.loc)) return error.EntityInWall;
        }
    }

    if (combat.isInCombat(w)) {
        if (combat.activeTurn(w)) |active| {
            const owner = w.store.get(active) orelse return error.InvalidTurnOwner;
            if (owner.char.status != .fighting) return error.InvalidFightingStatus;
            if (owner.current_hp == 0 or owner.conditions.has(.dead)) return error.DeadTurnOwner;
        }
    }

    if (tracker) |t| try trackMonsterPositions(w, t);
}

fn generateLine(allocator: std.mem.Allocator, fuzz_rng: *rng.SeededRng) ![]const u8 {
    const mode = fuzz_rng.nextU8() % 5;
    return switch (mode) {
        0 => try duplicateTemplate(allocator, fuzz_rng),
        1 => try mutateTemplate(allocator, fuzz_rng),
        else => try randomBytesLine(allocator, fuzz_rng),
    };
}

fn duplicateTemplate(allocator: std.mem.Allocator, fuzz_rng: *rng.SeededRng) ![]const u8 {
    const idx = fuzz_rng.nextU8() % templates.len;
    return try allocator.dupe(u8, templates[idx]);
}

fn mutateTemplate(allocator: std.mem.Allocator, fuzz_rng: *rng.SeededRng) ![]const u8 {
    const base = templates[fuzz_rng.nextU8() % templates.len];
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try list.appendSlice(allocator, base);

    const extra = fuzz_rng.nextU8() % 8;
    var i: u8 = 0;
    while (i < extra) : (i += 1) {
        const c = pickChar(fuzz_rng);
        try list.append(allocator, c);
    }

    return try list.toOwnedSlice(allocator);
}

fn randomBytesLine(allocator: std.mem.Allocator, fuzz_rng: *rng.SeededRng) ![]const u8 {
    const len = 1 + (fuzz_rng.nextU8() % 48);
    const buf = try allocator.alloc(u8, len);
    for (buf) |*b| b.* = pickChar(fuzz_rng);
    return buf;
}

fn pickChar(fuzz_rng: *rng.SeededRng) u8 {
    const roll = fuzz_rng.nextU8() % 100;
    if (roll < 50) return "abcdefghijklmnopqrstuvwxyz0123456789 "[fuzz_rng.nextU8() % 37];
    if (roll < 75) return @truncate(fuzz_rng.nextU8());
    return switch (fuzz_rng.nextU8() % 6) {
        0 => '\n',
        1 => '\t',
        2 => '\r',
        3 => 0,
        else => ' ',
    };
}

test "fuzz harness survives seeded iterations" {
    const r = try run(std.testing.allocator, .{
        .seed = 7,
        .iterations = 200,
        .db_path = "zig-q-fuzz-test.sqlite",
    });
    try std.testing.expect(r.passed());
}

test "parse fuzz does not crash on arbitrary bytes" {
    var fuzz_rng = rng.SeededRng.init(99);
    var buf: [64]u8 = undefined;
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        const len = 1 + (fuzz_rng.nextU8() % buf.len);
        for (buf[0..len]) |*b| b.* = pickChar(&fuzz_rng);
        _ = commands.parseLine(buf[0..len]);
    }
}

test "invariants reject hp outside zero max range" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const ent = w.store.get(id).?;
    ent.max_hp = 10;
    ent.current_hp = 11;
    try std.testing.expectError(error.HpAboveMax, assertInvariants(&w, id));

    ent.current_hp = 10;
    ent.conditions.add(.dead);
    try std.testing.expectError(error.DeadWithPositiveHp, assertInvariants(&w, id));

    ent.current_hp = 0;
    ent.conditions = @import("types.zig").ConditionSet.initEmpty();
    try std.testing.expectError(error.AliveWithZeroHp, assertInvariants(&w, id));
}

test "invariants hold for known creation script" {
    const script = [_][]const u8{
        "assign 6 5 4 3 2 1",
        "race 2",
        "class 1",
        "spawn",
        "move north",
        "stats",
        "exit",
    };
    try runOne(std.testing.allocator, 42, &script);
}