const std = @import("std");
const world = @import("world.zig");
const session = @import("session.zig");
const commands = @import("commands.zig");
const transcript = @import("transcript.zig");

pub const RunOpts = struct {
    record: ?transcript.RecordOpts = null,
};

pub fn runRepl(
    allocator: std.mem.Allocator,
    seed: u64,
    reader: anytype,
    stdout_writer: anytype,
    opts: RunOpts,
) !void {
    var w = try world.World.init(allocator, seed);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);

    var ctx = commands.Context{
        .allocator = allocator,
        .w = &w,
        .draft = &draft,
    };

    var recording: ?transcript.Session = null;
    defer if (recording) |*rec| rec.deinit();

    if (opts.record) |record_opts| {
        recording = try transcript.Session.open(allocator, seed, record_opts);
        try recording.?.writeHeader(seed);
    }

    var out = transcript.Output(@TypeOf(stdout_writer)){
        .stdout = stdout_writer,
        .session = if (recording) |*rec| rec else null,
    };

    try out.print("zig-q repl seed={}\n", .{seed});
    try session.formatStatPool(draft.pool, &out);
    try out.print("type 'help' for commands\n", .{});
    if (recording) |*rec| {
        try out.print("recording to {s}\n", .{rec.path()});
    }

    while (true) {
        try stdout_writer.print("> ", .{});
        const line = try readLine(allocator, reader) orelse break;
        defer allocator.free(line);

        if (recording) |*rec| try rec.logInput(line);

        const cmd = commands.parseLine(line);
        const result = try commands.execute(&ctx, cmd, &out);
        switch (result) {
            .continue_repl => {},
            .exit_repl => {
                try out.print("exiting...\n", .{});
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
    stdout_writer: anytype,
    opts: RunOpts,
) !void {
    var w = try world.World.init(allocator, seed);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);

    var ctx = commands.Context{
        .allocator = allocator,
        .w = &w,
        .draft = &draft,
    };

    var recording: ?transcript.Session = null;
    defer if (recording) |*rec| rec.deinit();

    if (opts.record) |record_opts| {
        recording = try transcript.Session.open(allocator, seed, record_opts);
        try recording.?.writeHeader(seed);
    }

    var out = transcript.Output(@TypeOf(stdout_writer)){
        .stdout = stdout_writer,
        .session = if (recording) |*rec| rec else null,
    };

    try out.print("zig-q repl seed={}\n", .{seed});
    try session.formatStatPool(draft.pool, &out);

    for (script) |line| {
        try out.print("> {s}\n", .{line});

        const cmd = commands.parseLine(line);
        const result = try commands.execute(&ctx, cmd, &out);
        switch (result) {
            .continue_repl => {},
            .exit_repl => {
                try out.print("exiting...\n", .{});
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

test "repl recording captures session transcript" {
    const allocator = std.testing.allocator;

    const path = "zig-q-repl-record-test.txt";
    defer std.fs.cwd().deleteFile(path) catch {};

    const script = [_][]const u8{ "help", "exit" };
    var out_buf: [1024]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&out_buf);

    try runReplScript(allocator, 42, &script, out_stream.writer(), .{
        .record = .{ .path = path },
    });

    const file = try std.fs.cwd().readFileAlloc(allocator, path, 4096);
    defer allocator.free(file);

    const stdout = out_stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, file, "# seed=42") != null);
    try std.testing.expect(std.mem.indexOf(u8, file, "> help") != null);
    try std.testing.expect(std.mem.indexOf(u8, file, "exiting...") != null);
    try std.testing.expect(std.mem.indexOf(u8, file, stdout) != null);
}

test "repl creation script is deterministic" {
    const allocator = std.testing.allocator;
    const script = [_][]const u8{
        "assign 6 5 4 3 2 1",
        "race 2",
        "class 1",
        "spawn",
        "stats",
        "exit",
    };

    var buf_a: [4096]u8 = undefined;
    var buf_b: [4096]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runReplScript(allocator, 42, &script, fbs_a.writer(), .{});
    try runReplScript(allocator, 42, &script, fbs_b.writer(), .{});

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "dwarf") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}