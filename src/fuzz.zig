const std = @import("std");
const rng = @import("rng.zig");
const world = @import("world.zig");
const entity = @import("entity.zig");
const session = @import("session.zig");
const commands = @import("commands.zig");
const transcript = @import("transcript.zig");

pub const Config = struct {
    seed: u64 = 0,
    iterations: u32 = 10_000,
    max_commands: u8 = 32,
    world_seed: u64 = 42,
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

        var ctx = commands.Context{
            .allocator = a,
            .w = &w,
            .draft = &draft,
        };

        var out_buf: [8192]u8 = undefined;
        var out_stream = std.io.fixedBufferStream(&out_buf);
        var out = transcript.Output(@TypeOf(out_stream.writer())){
            .stdout = out_stream.writer(),
            .session = null,
        };

        try out.print("zig-q repl version={s} seed={}\n", .{ @import("version.zig").semver, cfg.world_seed });
        try session.formatStatPool(draft.pool, &out);

        var step: u32 = 0;
        while (step < cfg.max_commands) : (step += 1) {
            const line = try generateLine(a, &fuzz_rng);
            try script_lines.append(allocator, try allocator.dupe(u8, line));

            try out.print("> {s}\n", .{line});
            const cmd = commands.parseLine(line);
            const result = commands.execute(&ctx, cmd, &out) catch |err| {
                assertInvariants(&w, ctx.player_id) catch |inv_err| {
                    return failureReport(cfg.iterations, iteration, step, inv_err, &script_lines);
                };
                try out.print("fuzz tolerated error: {s}\n", .{@errorName(err)});
                continue;
            };

            assertInvariants(&w, ctx.player_id) catch |inv_err| {
                return failureReport(cfg.iterations, iteration, step, inv_err, &script_lines);
            };

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
        const cmd = commands.parseLine(line);
        const result = try commands.execute(&ctx, cmd, &out);
        try assertInvariants(&w, ctx.player_id);
        if (result == .exit_repl) return;
    }
}

pub fn assertInvariants(w: *world.World, player_id: entity.EntityId) !void {
    var on_map: usize = 0;
    for (w.store.entities.items) |ent| {
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

    if (w.has_dungeon) {
        for (w.store.entities.items) |ent| {
            if (!w.terrain.isWalkable(ent.loc)) return error.EntityInWall;
        }
    }
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
    const r = try run(std.testing.allocator, .{ .seed = 7, .iterations = 200 });
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