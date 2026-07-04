const std = @import("std");
const world = @import("world.zig");
const entity = @import("entity.zig");
const loc = @import("loc.zig");
const movement = @import("movement.zig");
const map_render = @import("map_render.zig");
const session = @import("session.zig");
const character = @import("character.zig");

pub const Command = union(enum) {
    look,
    time,
    move: movement.Direction,
    help,
    exit,
    roll,
    assign: [6]usize,
    race: usize,
    class: usize,
    spawn,
    stats,
    unknown: []const u8,
};

pub const Result = union(enum) {
    continue_repl,
    exit_repl,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    w: *world.World,
    draft: *session.CreationDraft,
    player_id: entity.EntityId = entity.invalid_id,
};

pub fn parseLine(line: []const u8) Command {
    var trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return .help;

    if (std.mem.eql(u8, trimmed, "look")) return .look;
    if (std.mem.eql(u8, trimmed, "time")) return .time;
    if (std.mem.eql(u8, trimmed, "help")) return .help;
    if (std.mem.eql(u8, trimmed, "exit")) return .exit;
    if (std.mem.eql(u8, trimmed, "roll")) return .roll;
    if (std.mem.eql(u8, trimmed, "spawn")) return .spawn;
    if (std.mem.eql(u8, trimmed, "stats")) return .stats;

    if (std.mem.startsWith(u8, trimmed, "move ")) {
        const arg = std.mem.trim(u8, trimmed[5..], " \t");
        if (movement.Direction.parse(arg)) |dir| return .{ .move = dir };
    }

    if (parseSixPicks("assign ", trimmed)) |picks| return .{ .assign = picks };
    if (parseOnePick("race ", trimmed)) |pick| return .{ .race = pick };
    if (parseOnePick("class ", trimmed)) |pick| return .{ .class = pick };

    return .{ .unknown = trimmed };
}

fn parseSixPicks(prefix: []const u8, trimmed: []const u8) ?[6]usize {
    if (!std.mem.startsWith(u8, trimmed, prefix)) return null;
    var iter = std.mem.splitScalar(u8, trimmed[prefix.len..], ' ');
    var picks: [6]usize = undefined;
    for (&picks) |*pick| {
        const tok = iter.next() orelse return null;
        const t = std.mem.trim(u8, tok, " \t");
        if (t.len == 0) return null;
        pick.* = std.fmt.parseInt(usize, t, 10) catch return null;
    }
    return picks;
}

fn parseOnePick(prefix: []const u8, trimmed: []const u8) ?usize {
    if (!std.mem.startsWith(u8, trimmed, prefix)) return null;
    const arg = std.mem.trim(u8, trimmed[prefix.len..], " \t");
    if (arg.len == 0) return null;
    return std.fmt.parseInt(usize, arg, 10) catch null;
}

pub fn execute(ctx: *Context, cmd: Command, writer: anytype) !Result {
    switch (cmd) {
        .look => {
            const ent = ctx.w.store.get(ctx.player_id) orelse {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            };
            _ = ent;
            try map_render.renderLook(ctx.w, ctx.player_id, writer);
        },
        .time => {
            try writer.print("time ticks={} time_of_day={d:.4}\n", .{
                ctx.w.game_clock.ticks,
                ctx.w.game_clock.time_of_day,
            });
        },
        .move => |dir| {
            if (ctx.w.store.get(ctx.player_id) == null) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            const new_loc = movement.moveEntity(ctx.w, ctx.player_id, dir) catch |err| switch (err) {
                error.Blocked => {
                    try writer.print("You cannot move there.\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
            try writer.print("moved to ({},{})\n", .{ new_loc.x, new_loc.y });
        },
        .roll => {
            const pool = session.draftRoll(ctx.w, ctx.draft);
            try session.formatStatPool(pool, writer);
        },
        .assign => |picks| {
            session.draftAssign(ctx.draft, picks) catch |err| switch (err) {
                error.NoStatPool => {
                    try writer.print("roll stats first\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
            try writer.print("stats assigned\n", .{});
        },
        .race => |pick| {
            session.draftChooseRace(ctx.draft, pick) catch {
                try writer.print("invalid race pick (1-3)\n", .{});
                return .continue_repl;
            };
            try writer.print("race chosen\n", .{});
        },
        .class => |pick| {
            session.draftChooseClass(ctx.draft, pick) catch {
                try writer.print("invalid class pick (1-3)\n", .{});
                return .continue_repl;
            };
            try writer.print("class chosen\n", .{});
        },
        .spawn => {
            const char = session.draftBuildCharacter(ctx.allocator, ctx.w, ctx.draft, "George") catch |err| switch (err) {
                error.IncompleteDraft => {
                    try writer.print("complete creation first (roll, assign, race, class)\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
            ctx.w.stageCharacter(char);
            ctx.player_id = try ctx.w.spawnStagedPlayer(loc.Loc.init(49, 49), "entity_0");
            try writer.print("spawned id={} at (49,49)\n", .{ ctx.player_id });
        },
        .stats => {
            const ent = ctx.w.store.get(ctx.player_id) orelse {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            };
            try character.formatStats(ent.char, writer);
        },
        .help => {
            try writer.print(
                \\commands: roll, assign <6 picks>, race <1-3>, class <1-3>, spawn, stats
                \\         look, time, move <north|south|east|west>, help, exit
                \\
            , .{});
        },
        .exit => return .exit_repl,
        .unknown => |text| {
            try writer.print("unknown command: {s}\n", .{text});
        },
    }
    return .continue_repl;
}

test "parse and execute move changes position" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 7);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    var ctx = Context{
        .allocator = allocator,
        .w = &w,
        .draft = &draft,
        .player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49)),
    };

    const cmd = parseLine("move east");
    switch (cmd) {
        .move => |_| {},
        else => return error.TestExpectedEqual,
    }

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, cmd, fbs.writer());

    try std.testing.expectEqual(@as(u64, 50), w.store.get(ctx.player_id).?.loc.y);
}

test "spawn after creation shows dwarf con bonus in stats" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);

    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft };
    _ = try execute(&ctx, .spawn, std.io.null_writer);
    _ = try execute(&ctx, .stats, std.io.null_writer);

    const ent = w.store.get(ctx.player_id).?;
    for (ent.char.attributes.items) |attr| {
        if (std.mem.eql(u8, attr.abbr, "CON")) {
            try std.testing.expect(attr.stat >= 12);
            return;
        }
    }
    return error.TestExpectedEqual;
}