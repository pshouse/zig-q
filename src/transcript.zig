const std = @import("std");
const version = @import("version.zig");

pub const RecordOpts = struct {
    /// `null` selects `transcripts/session-<unix_ts>-seed<N>.txt` under cwd.
    path: ?[]const u8 = null,
    /// Override semver written to transcript header (default: compile-time `version.semver`).
    semver: ?[]const u8 = null,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    owned_path: []u8,

    pub fn open(allocator: std.mem.Allocator, seed: u64, opts: RecordOpts) !Session {
        const dest_path = if (opts.path) |custom|
            try allocator.dupe(u8, custom)
        else
            try defaultPath(allocator, seed);

        if (opts.path == null) {
            const dir = std.fs.path.dirname(dest_path) orelse "transcripts";
            try std.fs.cwd().makePath(dir);
        } else if (std.fs.path.dirname(dest_path)) |dir| {
            try std.fs.cwd().makePath(dir);
        }

        const file = try std.fs.cwd().createFile(dest_path, .{});
        errdefer file.close();

        return .{
            .allocator = allocator,
            .file = file,
            .owned_path = dest_path,
        };
    }

    pub fn deinit(self: *Session) void {
        self.file.close();
        self.allocator.free(self.owned_path);
        self.* = undefined;
    }

    pub fn path(self: *const Session) []const u8 {
        return self.owned_path;
    }

    pub fn writeHeader(self: *Session, seed: u64, semver_override: ?[]const u8) !void {
        const w = self.file.deprecatedWriter();
        try w.print("# zig-q repl transcript\n", .{});
        try w.print("# version={s}\n", .{version.resolve(semver_override)});
        try w.print("# seed={}\n", .{seed});
        try w.print("# started={d}\n", .{std.time.timestamp()});
        try w.print("# ---\n", .{});
    }

    pub fn logInput(self: *Session, line: []const u8) !void {
        try self.file.deprecatedWriter().print("> {s}\n", .{line});
    }
};

pub fn Output(comptime StdoutWriter: type) type {
    return struct {
        stdout: StdoutWriter,
        session: ?*Session = null,

        pub fn print(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
            try self.stdout.print(fmt, args);
            if (self.session) |session| {
                try session.file.deprecatedWriter().print(fmt, args);
            }
        }

        pub fn write(self: *@This(), bytes: []const u8) !usize {
            const n = try self.stdout.write(bytes);
            if (self.session) |session| {
                try session.file.deprecatedWriter().writeAll(bytes[0..n]);
            }
            return n;
        }

        pub fn writeAll(self: *@This(), bytes: []const u8) !void {
            try self.stdout.writeAll(bytes);
            if (self.session) |session| {
                try session.file.deprecatedWriter().writeAll(bytes);
            }
        }
    };
}

fn defaultPath(allocator: std.mem.Allocator, seed: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "transcripts/session-{d}-seed{}.txt", .{
        std.time.timestamp(),
        seed,
    });
}

pub const Header = struct {
    seed: ?u64 = null,
    version: ?[]const u8 = null,
};

/// Parse `# seed=` and `# version=` lines from a recorded transcript header.
pub fn parseHeader(text: []const u8) Header {
    var result: Header = .{};
    var iter = std.mem.splitScalar(u8, text, '\n');
    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.eql(u8, trimmed, "# ---")) break;
        if (std.mem.startsWith(u8, trimmed, "# seed=")) {
            const raw = trimmed["# seed=".len..];
            result.seed = std.fmt.parseInt(u64, raw, 10) catch null;
        }
        if (std.mem.startsWith(u8, trimmed, "# version=")) {
            result.version = trimmed["# version=".len..];
        }
    }
    return result;
}

/// Extract every `> command` input line from a transcript (playthrough harvest).
pub fn harvestCommands(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit(allocator);
    }

    var iter = std.mem.splitScalar(u8, text, '\n');
    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "> ")) continue;
        const cmd = std.mem.trim(u8, trimmed[2..], " \t\r");
        if (cmd.len == 0) continue;
        try lines.append(allocator, try allocator.dupe(u8, cmd));
    }

    return try lines.toOwnedSlice(allocator);
}

pub fn freeCommands(allocator: std.mem.Allocator, commands: []const []const u8) void {
    for (commands) |cmd| allocator.free(cmd);
    allocator.free(commands);
}

pub fn harvestFile(allocator: std.mem.Allocator, path: []const u8) !struct {
    header: Header,
    commands: []const []const u8,
} {
    const text = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    errdefer allocator.free(text);
    const header = parseHeader(text);
    const commands = try harvestCommands(allocator, text);
    allocator.free(text);
    return .{ .header = header, .commands = commands };
}

test "harvestCommands extracts playthrough inputs" {
    const allocator = std.testing.allocator;
    const sample =
        \\# zig-q repl transcript
        \\# version=0.6.0
        \\# seed=42
        \\# ---
        \\> assign 5 1 6 2 3 4
        \\> race 1
        \\> spawn
        \\> look
        \\> exit
        \\
    ;

    const cmds = try harvestCommands(allocator, sample);
    defer freeCommands(allocator, cmds);

    try std.testing.expectEqual(@as(usize, 5), cmds.len);
    try std.testing.expectEqualStrings("assign 5 1 6 2 3 4", cmds[0]);
    try std.testing.expectEqualStrings("race 1", cmds[1]);
    try std.testing.expectEqualStrings("spawn", cmds[2]);
    try std.testing.expectEqualStrings("look", cmds[3]);
    try std.testing.expectEqualStrings("exit", cmds[4]);
}

test "parseHeader reads seed and version" {
    const sample =
        \\# zig-q repl transcript
        \\# version=0.6.0
        \\# seed=42
        \\# started=1
        \\# ---
        \\
    ;
    const header = parseHeader(sample);
    try std.testing.expectEqual(@as(?u64, 42), header.seed);
    try std.testing.expectEqualStrings("0.6.0", header.version.?);
}

test "session mirrors output and input" {
    const allocator = std.testing.allocator;

    const dest_path = "zig-q-transcript-test.txt";
    defer std.fs.cwd().deleteFile(dest_path) catch {};

    var session = try Session.open(allocator, 42, .{ .path = dest_path });
    defer session.deinit();

    try session.writeHeader(42, null);

    var buf: [256]u8 = undefined;
    var capture = std.io.fixedBufferStream(&buf);
    var out = Output(@TypeOf(capture.writer())){
        .stdout = capture.writer(),
        .session = &session,
    };

    try out.print("zig-q repl seed={}\n", .{42});
    try session.logInput("help");

    const file = try std.fs.cwd().readFileAlloc(allocator, dest_path, 1024);
    defer allocator.free(file);

    try std.testing.expect(std.mem.indexOf(u8, file, "# version=0.6.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, file, "# seed=42") != null);
    try std.testing.expect(std.mem.indexOf(u8, file, "zig-q repl seed=42") != null);
    try std.testing.expect(std.mem.indexOf(u8, file, "> help") != null);
}