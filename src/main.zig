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
        var cli_override: ?[]const u8 = null;
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--semver")) {
                if (i + 1 >= args.len) {
                    try stdout.print("usage: --version [--semver <version>]\n", .{});
                    return;
                }
                cli_override = args[i + 1];
                i += 1;
            } else {
                try stdout.print("usage: --version [--semver <version>]\n", .{});
                return;
            }
        }
        try stdout.print("{s}\n", .{zig_q.version.cliVersion(cli_override)});
        return;
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--demo")) {
        const seed: u64 = if (args.len >= 3) try parseSeed(args[2]) else 42;
        _ = try zig_q.demo.runDemo(allocator, seed, stdout);
        return;
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--harvest")) {
        if (args.len < 3) {
            try stdout.print("usage: --harvest <transcript.txt>\n", .{});
            return;
        }
        const harvested = try zig_q.transcript.harvestFile(allocator, args[2]);
        defer zig_q.transcript.freeCommands(allocator, harvested.commands);
        if (harvested.header.seed) |seed| {
            try stdout.print("# seed={}\n", .{seed});
        }
        for (harvested.commands) |cmd| {
            try stdout.print("{s}\n", .{cmd});
        }
        return;
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--repl")) {
        const cli = try zig_q.repl.parseReplCli(args[2..]);
        const stdin = std.fs.File.stdin().deprecatedReader();
        try zig_q.repl.runRepl(allocator, cli.seed, stdin, stdout, .{
            .record = cli.record,
            .semver = cli.semver,
            .playtest = cli.playtest,
            .live_ai = cli.live_ai,
        });
        return;
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--help")) {
        try stdout.print(
            \\zig-q {s}
            \\Usage:
            \\  zig build run -- --version [--semver <version>]
            \\                                           Print semver and exit
            \\  zig build run -- --demo [seed]             Non-interactive demo (default seed 42)
            \\  zig build run -- --repl [seed] [--record [path]] [--semver <version>] [--playtest] [--live-ai]
            \\  zig build run -- --repl --record [seed]    Same; numeric after --record is seed
            \\                                           Interactive REPL (default seed 42)
            \\                                           --live-ai keeps explore AI on for piped
            \\                                           scripts (deterministic; off by default)
            \\  zig build dst -- <scenario> [seed]         DST harness (bootstrap, brawl, deadly_floor, …)
            \\  zig build dst -- @scenarios/<file> [seed]  Data-driven scenario file
            \\  zig build run -- --harvest <transcript>   Print harvested > command lines
            \\  zig build fuzz -- [iterations] [seed] [world_seed]
            \\                                           Deterministic REPL fuzz harness (required gate)
            \\  zig build gate-v16                        v1.6 release gate captures
            \\
            \\  --record writes a transcript under transcripts/ unless path is given.
            \\  Transcripts include # version=<semver>; --semver overrides for this run.
            \\  --playtest enables extra debug verbs (e.g. wound) for manual balance work.
            \\
            \\  See ROADMAP.md for the dungeon crawl plan (current: v1.6).
            \\
        , .{zig_q.version.semver});
        return;
    }

    try stdout.print("zig-q: pass --version, --demo, --repl, --harvest, or --help\n", .{});
}

fn parseSeed(text: []const u8) !u64 {
    return std.fmt.parseInt(u64, text, 10);
}
