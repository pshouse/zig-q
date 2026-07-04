const std = @import("std");
const loc = @import("loc.zig");
const world = @import("world.zig");
const session = @import("session.zig");
const map_render = @import("map_render.zig");

pub const Step = union(enum) {
    roll_stats,
    spawn: struct { name: []const u8, x: u64, y: u64 },
    tick: u32,
    time,
    look,
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

pub const Harness = struct {
    allocator: std.mem.Allocator,
    w: world.World,
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
            .render_map => |cfg| {
                try writer.print("step render_map center=({},{}) radius={}\n", .{ cfg.x, cfg.y, cfg.radius });
                try map_render.renderViewport(&self.w, loc.Loc.init(cfg.x, cfg.y), cfg.radius, writer);
            },
        }
    }
};

pub fn runNamedScenario(allocator: std.mem.Allocator, name: []const u8, seed: u64, writer: anytype) !void {
    const scenario = if (std.mem.eql(u8, name, "bootstrap"))
        Scenario{ .name = "bootstrap", .seed = seed, .steps = default_scenario.steps }
    else
        return error.UnknownScenario;

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