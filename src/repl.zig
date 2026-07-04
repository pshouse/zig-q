const std = @import("std");
const world = @import("world.zig");
const loc = @import("loc.zig");
const session = @import("session.zig");
const commands = @import("commands.zig");

pub fn bootstrapPlayer(allocator: std.mem.Allocator, w: *world.World) !entity.EntityId {
    const boot = try session.bootstrapCharacter(allocator, w, "George");
    w.stageCharacter(boot.character);
    return w.spawnStagedPlayer(loc.Loc.init(49, 49), "entity_0");
}

const entity = @import("entity.zig");

pub fn runRepl(allocator: std.mem.Allocator, seed: u64, reader: anytype, writer: anytype) !void {
    var w = try world.World.init(allocator, seed);
    defer w.deinit();

    const player_id = try bootstrapPlayer(allocator, &w);
    try writer.print("zig-q repl seed={}\n", .{seed});
    try writer.print("type 'help' for commands\n", .{});

    while (true) {
        try writer.print("> ", .{});
        const line = try readLine(allocator, reader) orelse break;
        defer allocator.free(line);

        const cmd = commands.parseLine(line);
        const result = try commands.execute(&w, player_id, cmd, writer);
        switch (result) {
            .continue_repl => {},
            .exit_repl => {
                try writer.print("exiting...\n", .{});
                return;
            },
        }
    }
}

/// Drive REPL with a fixed script (for tests and DST-style verification).
pub fn runReplScript(
    allocator: std.mem.Allocator,
    seed: u64,
    script: []const []const u8,
    writer: anytype,
) !void {
    var w = try world.World.init(allocator, seed);
    defer w.deinit();

    const player_id = try bootstrapPlayer(allocator, &w);
    try writer.print("zig-q repl seed={}\n", .{seed});

    for (script) |line| {
        try writer.print("> {s}\n", .{line});
        const cmd = commands.parseLine(line);
        const result = try commands.execute(&w, player_id, cmd, writer);
        switch (result) {
            .continue_repl => {},
            .exit_repl => {
                try writer.print("exiting...\n", .{});
                return;
            },
        }
    }
}

fn readLine(allocator: std.mem.Allocator, reader: anytype) !?[]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    while (true) {
        var byte: [1]u8 = undefined;
        const n = reader.read(&byte) catch return error.ReadFailed;
        if (n == 0) {
            if (list.items.len == 0) return null;
            break;
        }
        if (byte[0] == '\n') break;
        if (byte[0] == '\r') continue;
        try list.append(allocator, byte[0]);
    }

    return try list.toOwnedSlice(allocator);
}

test "repl script is deterministic" {
    const allocator = std.testing.allocator;
    const script = [_][]const u8{ "look", "move east", "look", "time", "exit" };

    var buf_a: [4096]u8 = undefined;
    var buf_b: [4096]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runReplScript(allocator, 42, &script, fbs_a.writer());
    try runReplScript(allocator, 42, &script, fbs_b.writer());

    try std.testing.expectEqualSlices(u8, fbs_a.getWritten(), fbs_b.getWritten());
}