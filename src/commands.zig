const std = @import("std");
const world = @import("world.zig");
const entity = @import("entity.zig");
const movement = @import("movement.zig");
const map_render = @import("map_render.zig");

pub const Command = union(enum) {
    look,
    time,
    move: movement.Direction,
    help,
    exit,
    unknown: []const u8,
};

pub const Result = union(enum) {
    continue_repl,
    exit_repl,
};

pub fn parseLine(line: []const u8) Command {
    var trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return .help;

    if (std.mem.eql(u8, trimmed, "look")) return .look;
    if (std.mem.eql(u8, trimmed, "time")) return .time;
    if (std.mem.eql(u8, trimmed, "help")) return .help;
    if (std.mem.eql(u8, trimmed, "exit")) return .exit;

    if (std.mem.startsWith(u8, trimmed, "move ")) {
        const arg = std.mem.trim(u8, trimmed[5..], " \t");
        if (movement.Direction.parse(arg)) |dir| return .{ .move = dir };
    }

    return .{ .unknown = trimmed };
}

pub fn execute(w: *world.World, player_id: entity.EntityId, cmd: Command, writer: anytype) !Result {
    switch (cmd) {
        .look => {
            try map_render.renderLook(w, player_id, writer);
        },
        .time => {
            try writer.print("time ticks={} time_of_day={d:.4}\n", .{
                w.game_clock.ticks,
                w.game_clock.time_of_day,
            });
        },
        .move => |dir| {
            const new_loc = movement.moveEntity(w, player_id, dir) catch |err| switch (err) {
                error.Blocked => {
                    try writer.print("You cannot move there.\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
            try writer.print("moved to ({},{})\n", .{ new_loc.x, new_loc.y });
        },
        .help => {
            try writer.print(
                \\commands: look, time, move <north|south|east|west>, help, exit
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

    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const cmd = parseLine("move east");
    switch (cmd) {
        .move => |_| {},
        else => return error.TestExpectedEqual,
    }

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&w, id, cmd, fbs.writer());

    try std.testing.expectEqual(@as(u64, 50), w.store.get(id).?.loc.y);
}

const loc = @import("loc.zig");