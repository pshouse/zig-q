const std = @import("std");

pub const RecordOpts = struct {
    /// `null` selects `transcripts/session-<unix_ts>-seed<N>.txt` under cwd.
    path: ?[]const u8 = null,
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

    pub fn writeHeader(self: *Session, seed: u64) !void {
        const w = self.file.deprecatedWriter();
        try w.print("# zig-q repl transcript\n", .{});
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

test "session mirrors output and input" {
    const allocator = std.testing.allocator;

    const dest_path = "zig-q-transcript-test.txt";
    defer std.fs.cwd().deleteFile(dest_path) catch {};

    var session = try Session.open(allocator, 42, .{ .path = dest_path });
    defer session.deinit();

    try session.writeHeader(42);

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

    try std.testing.expect(std.mem.indexOf(u8, file, "# seed=42") != null);
    try std.testing.expect(std.mem.indexOf(u8, file, "zig-q repl seed=42") != null);
    try std.testing.expect(std.mem.indexOf(u8, file, "> help") != null);
}