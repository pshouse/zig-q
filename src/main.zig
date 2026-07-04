const std = @import("std");
const zig_q = @import("zig_q");
const io_out = @import("io_out.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdout = io_out.stdoutWriter();

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--demo")) {
        const seed: u64 = if (args.len >= 3) try parseSeed(args[2]) else 42;
        _ = try zig_q.demo.runDemo(allocator, seed, stdout);
        return;
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--repl")) {
        const seed: u64 = if (args.len >= 3) try parseSeed(args[2]) else 42;
        const stdin = std.fs.File.stdin().deprecatedReader();
        try zig_q.repl.runRepl(allocator, seed, stdin, stdout);
        return;
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--help")) {
        try stdout.print(
            \\zig-q v0.3
            \\Usage:
            \\  zig build run -- --demo [seed]    Non-interactive demo (default seed 42)
            \\  zig build run -- --repl [seed]    Interactive REPL (default seed 42)
            \\  zig build dst -- bootstrap [seed]  DST harness: bootstrap scenario
            \\  zig build dst -- explore [seed]    DST harness: explore scenario
            \\
        , .{});
        return;
    }

    try stdout.print("zig-q: pass --demo, --repl, or --help\n", .{});
}

fn parseSeed(text: []const u8) !u64 {
    return std.fmt.parseInt(u64, text, 10);
}