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

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--version")) {
        try stdout.print("{s}\n", .{zig_q.version.semver});
        return;
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--demo")) {
        const seed: u64 = if (args.len >= 3) try parseSeed(args[2]) else 42;
        _ = try zig_q.demo.runDemo(allocator, seed, stdout);
        return;
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--repl")) {
        const cli = try zig_q.repl.parseReplCli(args[2..]);
        const stdin = std.fs.File.stdin().deprecatedReader();
        try zig_q.repl.runRepl(allocator, cli.seed, stdin, stdout, .{
            .record = cli.record,
            .semver = cli.semver,
        });
        return;
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--help")) {
        try stdout.print(
            \\zig-q {s}
            \\Usage:
            \\  zig build run -- --version                 Print semver and exit
            \\  zig build run -- --demo [seed]             Non-interactive demo (default seed 42)
            \\  zig build run -- --repl [seed] [--record [path]] [--semver <version>]
            \\  zig build run -- --repl --record [seed]    Same; numeric after --record is seed
            \\                                           Interactive REPL (default seed 42)
            \\  zig build dst -- bootstrap [seed]          DST harness: bootstrap scenario
            \\  zig build dst -- explore [seed]            DST harness: explore scenario
            \\  zig build dst -- create [seed]             DST harness: character creation scenario
            \\  zig build fuzz -- [iterations] [seed] [world_seed]
            \\                                           Deterministic REPL fuzz harness (required gate)
            \\
            \\  --record writes a transcript under transcripts/ unless path is given.
            \\  Transcripts include # version=<semver>; --semver overrides for this run.
            \\
            \\  See ROADMAP.md for v0.6-v1.0 dungeon crawl plan.
            \\
        , .{zig_q.version.semver});
        return;
    }

    try stdout.print("zig-q: pass --version, --demo, --repl, or --help\n", .{});
}

fn parseSeed(text: []const u8) !u64 {
    return std.fmt.parseInt(u64, text, 10);
}