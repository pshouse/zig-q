const std = @import("std");
const world = @import("world.zig");
const session = @import("session.zig");
const commands = @import("commands.zig");
const transcript = @import("transcript.zig");
const version = @import("version.zig");

pub const RunOpts = struct {
    record: ?transcript.RecordOpts = null,
    semver: ?[]const u8 = null,
    playtest: bool = false,
    /// Force explore AI on even when stdin is piped (--live-ai). AI draws come from
    /// the seeded stream in a fixed order, so scripted runs stay byte-identical.
    live_ai: bool = false,
};

pub const ReplCli = struct {
    seed: u64 = 42,
    record: ?transcript.RecordOpts = null,
    semver: ?[]const u8 = null,
    playtest: bool = false,
    live_ai: bool = false,
};

/// Parse REPL args after `--repl`: `[seed] [--record [path]]` in any order.
/// A numeric token after `--record` is the seed (default transcript path).
/// Use a path with separators or extension to set a custom transcript file.
pub fn parseReplCli(args: []const []const u8) !ReplCli {
    var result: ReplCli = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--record")) {
            if (i + 1 < args.len and args[i + 1][0] != '-') {
                const next = args[i + 1];
                if (looksLikeRecordPath(next)) {
                    result.record = .{ .path = next, .semver = result.semver };
                    i += 1;
                } else {
                    result.record = .{ .semver = result.semver };
                    result.seed = try std.fmt.parseInt(u64, next, 10);
                    i += 1;
                }
            } else {
                result.record = .{ .semver = result.semver };
            }
            continue;
        }
        if (std.mem.eql(u8, arg, "--semver")) {
            if (i + 1 >= args.len) return error.UnknownArgument;
            result.semver = args[i + 1];
            if (result.record) |*rec| rec.semver = result.semver;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--playtest")) {
            result.playtest = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--live-ai")) {
            result.live_ai = true;
            continue;
        }
        if (arg[0] == '-') return error.UnknownArgument;
        result.seed = try std.fmt.parseInt(u64, arg, 10);
    }
    return result;
}

fn looksLikeRecordPath(text: []const u8) bool {
    if (std.mem.indexOfAny(u8, text, "/\\.")) |_| return true;
    for (text) |c| {
        if (c < '0' or c > '9') return true;
    }
    return false;
}

pub fn runRepl(
    allocator: std.mem.Allocator,
    seed: u64,
    reader: anytype,
    stdout_writer: anytype,
    opts: RunOpts,
) !void {
    var w = try world.World.init(allocator, seed);
    defer w.deinit();
    try w.loadFloor(1);
    // Piped scripts skip explore AI so ambush does not block scripted verification paths.
    // --live-ai opts back in for scripted co-op sessions that want a living dungeon.
    w.explore_ai_on_move = std.fs.File.stdin().isTty() or opts.live_ai;

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);

    var ctx = commands.Context{
        .allocator = allocator,
        .w = &w,
        .draft = &draft,
        .help_profile = .repl_v11,
        .playtest = opts.playtest,
    };

    var recording: ?transcript.Session = null;
    defer if (recording) |*rec| rec.deinit();

    const semver = opts.semver;
    if (opts.record) |record_opts| {
        recording = try transcript.Session.open(allocator, seed, record_opts);
        try recording.?.writeHeader(seed, record_opts.semver orelse semver);
    }

    var out = transcript.Output(@TypeOf(stdout_writer)){
        .stdout = stdout_writer,
        .session = if (recording) |*rec| rec else null,
    };

    try out.print("zig-q repl version={s} seed={} floor={}\n", .{
        version.resolve(semver),
        seed,
        w.floor_index,
    });
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

        const result = try commands.executeLine(&ctx, line, &out);
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
    try w.loadFloor(1);
    w.explore_ai_on_move = opts.live_ai;

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);

    var ctx = commands.Context{
        .allocator = allocator,
        .w = &w,
        .draft = &draft,
        .help_profile = .repl_v11,
        .playtest = opts.playtest,
    };

    var recording: ?transcript.Session = null;
    defer if (recording) |*rec| rec.deinit();

    const semver = opts.semver;
    if (opts.record) |record_opts| {
        recording = try transcript.Session.open(allocator, seed, record_opts);
        try recording.?.writeHeader(seed, record_opts.semver orelse semver);
    }

    var out = transcript.Output(@TypeOf(stdout_writer)){
        .stdout = stdout_writer,
        .session = if (recording) |*rec| rec else null,
    };

    try out.print("zig-q repl version={s} seed={} floor={}\n", .{
        version.resolve(semver),
        seed,
        w.floor_index,
    });
    try session.formatStatPool(draft.pool, &out);

    for (script) |line| {
        try out.print("> {s}\n", .{line});

        const result = try commands.executeLine(&ctx, line, &out);
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

test "parseReplCli treats --record 42 as seed not path" {
    const cli = try parseReplCli(&.{ "--record", "42" });
    try std.testing.expectEqual(@as(u64, 42), cli.seed);
    try std.testing.expect(cli.record != null);
    try std.testing.expect(cli.record.?.path == null);
}

test "parseReplCli accepts seed before --record" {
    const cli = try parseReplCli(&.{ "99", "--record" });
    try std.testing.expectEqual(@as(u64, 99), cli.seed);
    try std.testing.expect(cli.record != null);
}

test "parseReplCli accepts custom transcript path" {
    const cli = try parseReplCli(&.{ "42", "--record", "transcripts/foo.txt" });
    try std.testing.expectEqual(@as(u64, 42), cli.seed);
    try std.testing.expectEqualStrings("transcripts/foo.txt", cli.record.?.path.?);
}

test "parseReplCli accepts --semver override" {
    const cli = try parseReplCli(&.{ "42", "--record", "--semver", "0.6.0-dev" });
    try std.testing.expectEqualStrings("0.6.0-dev", cli.semver.?);
    try std.testing.expectEqualStrings("0.6.0-dev", cli.record.?.semver.?);
}

test "parseReplCli gates playtest behind --playtest" {
    const on = try parseReplCli(&.{ "42", "--playtest" });
    try std.testing.expectEqual(@as(u64, 42), on.seed);
    try std.testing.expect(on.playtest);
    const off = try parseReplCli(&.{"42"});
    try std.testing.expect(!off.playtest);
}

test "parseReplCli gates live AI behind --live-ai" {
    const on = try parseReplCli(&.{ "42", "--live-ai" });
    try std.testing.expectEqual(@as(u64, 42), on.seed);
    try std.testing.expect(on.live_ai);
    const off = try parseReplCli(&.{"42"});
    try std.testing.expect(!off.live_ai);
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
    const ver_line = try std.fmt.allocPrint(allocator, "# version={s}", .{@import("version.zig").semver});
    defer allocator.free(ver_line);
    try std.testing.expect(std.mem.indexOf(u8, file, ver_line) != null);
    try std.testing.expect(std.mem.indexOf(u8, file, "# seed=42") != null);
    try std.testing.expect(std.mem.indexOf(u8, file, "> help") != null);
    try std.testing.expect(std.mem.indexOf(u8, file, "exiting...") != null);
    try std.testing.expect(std.mem.indexOf(u8, file, stdout) != null);
}

test "harvested playthrough transcript is deterministic" {
    const allocator = std.testing.allocator;
    const path = "transcripts/session-1783208416-seed42.txt";

    const harvested = try transcript.harvestFile(allocator, path);
    defer transcript.freeCommands(allocator, harvested.commands);

    try std.testing.expectEqual(@as(?u64, 42), harvested.header.seed);
    try std.testing.expectEqual(@as(usize, 30), harvested.commands.len);
    try std.testing.expectEqualStrings("assign 5 1 6 2 3 4", harvested.commands[1]);

    var buf_a: [65536]u8 = undefined;
    var buf_b: [65536]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    const seed = harvested.header.seed orelse 42;
    try runReplScript(allocator, seed, harvested.commands, fbs_a.writer(), .{});
    try runReplScript(allocator, seed, harvested.commands, fbs_b.writer(), .{});

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "dragonborn") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "look floor=1") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

// Long-horizon regression from a 177-command ironman playtest (seed 7).
// Originally exposed monster mass-starvation and walking-dead permadeath; under
// v1.6 the same script starved on floor 4. v1.7 #40 survival retune re-blesses
// the outcome: a provisioned ironman reaches floor 4 and finishes the script
// *alive* (no clock death). Determinism is still the hard pin.
test "harvested george2 ironman transcript is deterministic and long-horizon" {
    const allocator = std.testing.allocator;
    const path = "transcripts/session-george2-ironman-seed7.txt";

    const harvested = try transcript.harvestFile(allocator, path);
    defer transcript.freeCommands(allocator, harvested.commands);

    try std.testing.expectEqual(@as(?u64, 7), harvested.header.seed);
    try std.testing.expectEqual(@as(usize, 177), harvested.commands.len);

    var buf_a: [65536]u8 = undefined;
    var buf_b: [65536]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    const seed = harvested.header.seed orelse 7;
    try runReplScript(allocator, seed, harvested.commands, fbs_a.writer(), .{});
    try runReplScript(allocator, seed, harvested.commands, fbs_b.writer(), .{});

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out_a, "descended to floor 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "equipped greatsword") != null);
    // #40 retune: this route no longer ends in clock death.
    try std.testing.expect(std.mem.indexOf(u8, out_a, "you are dead (permadeath)") == null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "exiting") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "repl crawl script is deterministic" {
    const allocator = std.testing.allocator;
    const script = [_][]const u8{
        "assign 6 5 4 3 2 1",
        "race 2",
        "class 1",
        "stats",
        "spawn",
        "look",
        "move north",
        "stats",
        "exit",
    };

    var buf_a: [16384]u8 = undefined;
    var buf_b: [16384]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runReplScript(allocator, 42, &script, fbs_a.writer(), .{});
    try runReplScript(allocator, 42, &script, fbs_b.writer(), .{});

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "character (draft)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "look floor=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "HP:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "You cannot move there") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);
}

test "repl live-ai script is deterministic and monsters act" {
    const allocator = std.testing.allocator;
    // Descend to floor 2 (floor 1 spawns no monsters) and burn a few explore
    // actions so live AI has turns to patrol/chase.
    const script = [_][]const u8{
        "assign 6 5 4 3 2 1",
        "race 2",
        "class 1",
        "spawn",
        "move east",
        "move south",
        "move east",
        "descend",
        "look",
        "wait",
        "wait",
        "wait",
        "wait",
        "exit",
    };

    var buf_a: [32768]u8 = undefined;
    var buf_b: [32768]u8 = undefined;
    var fbs_a = std.io.fixedBufferStream(&buf_a);
    var fbs_b = std.io.fixedBufferStream(&buf_b);

    try runReplScript(allocator, 42, &script, fbs_a.writer(), .{ .live_ai = true });
    try runReplScript(allocator, 42, &script, fbs_b.writer(), .{ .live_ai = true });

    const out_a = fbs_a.getWritten();
    const out_b = fbs_b.getWritten();
    try std.testing.expect(out_a.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, out_a, "look floor=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_a, " moved ") != null);
    try std.testing.expectEqualSlices(u8, out_a, out_b);

    // Default (piped) behavior stays AI-off: same script, no monster movement.
    var buf_off: [32768]u8 = undefined;
    var fbs_off = std.io.fixedBufferStream(&buf_off);
    try runReplScript(allocator, 42, &script, fbs_off.writer(), .{});
    try std.testing.expect(std.mem.indexOf(u8, fbs_off.getWritten(), " moved ") == null);
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