const std = @import("std");
const loc = @import("loc.zig");
const world = @import("world.zig");
const session = @import("session.zig");
const map_render = @import("map_render.zig");
const commands = @import("commands.zig");

pub const Step = union(enum) {
    roll_stats,
    creation_roll,
    assign_stats: [6]usize,
    choose_race: usize,
    choose_class: usize,
    creation_finish: []const u8,
    load_floor: u32,
    spawn: struct { name: []const u8, x: u64, y: u64 },
    tick: u32,
    time,
    look,
    command: []const u8,
    render_map: struct { x: u64, y: u64, radius: u8 },
};

pub const Scenario = struct {
    name: []const u8,
    seed: u64,
    steps: []const Step,
};

pub const default_scenario = Scenario{
    .name = "bootstrap",
    .seed = 42,
    .steps = &.{
        .roll_stats,
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .tick = 2 },
        .time,
        .{ .render_map = .{ .x = 49, .y = 49, .radius = 3 } },
        .look,
        .{ .tick = 1 },
        .time,
    },
};

pub const explore_scenario = Scenario{
    .name = "explore",
    .seed = 42,
    .steps = &.{
        .roll_stats,
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .command = "look" },
        .{ .command = "move east" },
        .{ .command = "look" },
        .{ .command = "time" },
        .{ .command = "exit" },
    },
};

pub const create_scenario = Scenario{
    .name = "create",
    .seed = 42,
    .steps = &.{
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

/// Harvested from transcripts/session-1783208416-seed42.txt (recorded playthrough).
pub const playthrough_scenario = Scenario{
    .name = "playthrough",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .command = "help" },
        .{ .command = "assign 5 1 6 2 3 4" },
        .{ .command = "race" },
        .{ .command = "race 1" },
        .{ .command = "stats" },
        .{ .command = "help" },
        .{ .command = "class" },
        .{ .command = "class 1" },
        .{ .command = "spawn" },
        .{ .command = "stats" },
        .{ .command = "l" },
        .{ .command = "look" },
        .{ .command = "m n" },
        .{ .command = "move n" },
        .{ .command = "move e" },
        .{ .command = "look" },
        .{ .command = "move e" },
        .{ .command = "move s" },
        .{ .command = "look" },
        .{ .command = "move nw" },
        .{ .command = "move w w" },
        .{ .command = "move w; move w" },
        .{ .command = "move w" },
        .{ .command = "move w" },
        .{ .command = "move w" },
        .{ .command = "look" },
        .{ .command = "time" },
        .{ .command = "move n" },
        .{ .command = "time" },
        .{ .command = "exit" },
    },
};

pub const crawl_start_scenario = Scenario{
    .name = "crawl_start",
    .seed = 42,
    .steps = &.{
        .{ .load_floor = 1 },
        .creation_roll,
        .{ .assign_stats = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .choose_race = 2 },
        .{ .choose_class = 1 },
        .{ .creation_finish = "George" },
        .{ .spawn = .{ .name = "entity_0", .x = 49, .y = 49 } },
        .look,
        .{ .command = "move north" },
        .{ .command = "stats" },
        .{ .command = "exit" },
    },
};

pub const Harness = struct {
    allocator: std.mem.Allocator,
    w: world.World,
    draft: session.CreationDraft = .{},
    player_id: u32 = std.math.maxInt(u32),
    last_pool: session.StatPool = undefined,

    pub fn init(allocator: std.mem.Allocator, seed: u64) !Harness {
        return .{
            .allocator = allocator,
            .w = try world.World.init(allocator, seed),
        };
    }

    pub fn deinit(self: *Harness) void {
        self.w.deinit();
    }

    pub fn runScenario(self: *Harness, scenario: Scenario, writer: anytype) !void {
        try writer.print("dst scenario={s} seed={}\n", .{ scenario.name, scenario.seed });

        if (self.w.seed != scenario.seed) {
            self.deinit();
            self.* = try Harness.init(self.allocator, scenario.seed);
        }

        for (scenario.steps) |step| {
            try self.runStep(step, writer);
        }

        const snap = self.w.snapshot();
        try writer.print("dst_end entities={} cells={} ticks={} rng_offset={}\n", .{
            snap.entity_count,
            snap.occupied_cells,
            snap.clock_ticks,
            snap.rng_offset,
        });
    }

    fn runStep(self: *Harness, step: Step, writer: anytype) !void {
        switch (step) {
            .roll_stats => {
                const boot = try session.bootstrapCharacter(self.allocator, &self.w, "George");
                self.w.stageCharacter(boot.character);
                self.last_pool = boot.pool;
                try writer.print("step roll_stats\n", .{});
                try session.formatStatPool(boot.pool, writer);
            },
            .creation_roll => {
                const pool = session.draftRoll(&self.w, &self.draft);
                self.last_pool = pool;
                try writer.print("step creation_roll\n", .{});
                try session.formatStatPool(pool, writer);
            },
            .assign_stats => |picks| {
                try session.draftAssign(&self.draft, picks);
                try writer.print("step assign_stats\n", .{});
            },
            .choose_race => |pick| {
                try session.draftChooseRace(&self.draft, pick);
                try writer.print("step choose_race pick={}\n", .{pick});
            },
            .choose_class => |pick| {
                try session.draftChooseClass(&self.draft, pick);
                try writer.print("step choose_class pick={}\n", .{pick});
            },
            .creation_finish => |name| {
                const char = try session.draftBuildCharacter(self.allocator, &self.w, &self.draft, name);
                self.w.stageCharacter(char);
                try writer.print("step creation_finish name={s}\n", .{name});
            },
            .load_floor => |floor| {
                try self.w.loadFloor(floor);
                try writer.print("step load_floor {}\n", .{floor});
            },
            .spawn => |s| {
                const position = loc.Loc.init(s.x, s.y);
                self.player_id = try self.w.spawnStagedPlayer(position, s.name);
                try writer.print("step spawn id={} at ({},{})\n", .{ self.player_id, s.x, s.y });
            },
            .tick => |n| {
                var i: u32 = 0;
                while (i < n) : (i += 1) self.w.tick();
                try writer.print("step tick count={} total={}\n", .{ n, self.w.game_clock.ticks });
            },
            .time => {
                try writer.print("step time ticks={} time_of_day={d:.4}\n", .{
                    self.w.game_clock.ticks,
                    self.w.game_clock.time_of_day,
                });
            },
            .look => {
                try writer.print("step look\n", .{});
                try map_render.renderLook(&self.w, self.player_id, writer);
            },
            .command => |line| {
                try writer.print("step command {s}\n", .{line});
                var ctx = commands.Context{
                    .allocator = self.allocator,
                    .w = &self.w,
                    .draft = &self.draft,
                    .player_id = self.player_id,
                };
                const result = try commands.executeLine(&ctx, line, writer);
                self.player_id = ctx.player_id;
                if (result == .exit_repl) {
                    try writer.print("step exit\n", .{});
                }
            },
            .render_map => |cfg| {
                try writer.print("step render_map center=({},{}) radius={}\n", .{ cfg.x, cfg.y, cfg.radius });
                try map_render.renderViewport(&self.w, loc.Loc.init(cfg.x, cfg.y), cfg.radius, writer);
            },
        }
    }
};

pub fn scenarioByName(name: []const u8, seed: u64) ?Scenario {
    if (std.mem.eql(u8, name, "bootstrap"))
        return Scenario{ .name = "bootstrap", .seed = seed, .steps = default_scenario.steps };
    if (std.mem.eql(u8, name, "explore"))
        return Scenario{ .name = "explore", .seed = seed, .steps = explore_scenario.steps };
    if (std.mem.eql(u8, name, "create"))
        return Scenario{ .name = "create", .seed = seed, .steps = create_scenario.steps };
    if (std.mem.eql(u8, name, "crawl_start"))
        return Scenario{ .name = "crawl_start", .seed = seed, .steps = crawl_start_scenario.steps };
    if (std.mem.eql(u8, name, "playthrough"))
        return Scenario{ .name = "playthrough", .seed = seed, .steps = playthrough_scenario.steps };
    return null;
}

pub fn runNamedScenario(allocator: std.mem.Allocator, name: []const u8, seed: u64, writer: anytype) !void {
    const scenario = scenarioByName(name, seed) orelse return error.UnknownScenario;

    var harness = try Harness.init(allocator, seed);
    defer harness.deinit();
    try harness.runScenario(scenario, writer);
}

test "dst bootstrap scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [4096]u8 = undefined;
    var buf_b: [4096]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "bootstrap", 42, fbs_a.writer());
    try runNamedScenario(allocator, "bootstrap", 42, fbs_b.writer());

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "dst explore scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [8192]u8 = undefined;
    var buf_b: [8192]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "explore", 42, fbs_a.writer());
    try runNamedScenario(allocator, "explore", 42, fbs_b.writer());

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "moved to") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "dst playthrough scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [65536]u8 = undefined;
    var buf_b: [65536]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "playthrough", 42, fbs_a.writer());
    try runNamedScenario(allocator, "playthrough", 42, fbs_b.writer());

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "dragonborn") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "look floor=1") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "dst crawl_start scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [16384]u8 = undefined;
    var buf_b: [16384]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "crawl_start", 42, fbs_a.writer());
    try runNamedScenario(allocator, "crawl_start", 42, fbs_b.writer());

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "look floor=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "HP:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "You cannot move there") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "dst create scenario is byte-identical across runs" {
    const allocator = std.testing.allocator;
    var buf_a: [8192]u8 = undefined;
    var buf_b: [8192]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runNamedScenario(allocator, "create", 42, fbs_a.writer());
    try runNamedScenario(allocator, "create", 42, fbs_b.writer());

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "dwarf") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "demo output is deterministic for fixed seed" {
    const allocator = std.testing.allocator;
    const demo = @import("demo.zig");

    var buf_a: [4096]u8 = undefined;
    var buf_b: [4096]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    _ = try demo.runDemo(allocator, 42, fbs_a.writer());
    _ = try demo.runDemo(allocator, 42, fbs_b.writer());

    try std.testing.expectEqualSlices(u8, fbs_a.getWritten(), fbs_b.getWritten());
}