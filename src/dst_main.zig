const std = @import("std");
const zig_q = @import("zig_q");
const io_out = @import("io_out.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cli = try zig_q.dst.parseDstCli(args[1..]);
    const stdout = io_out.stdoutWriter();
    if (std.mem.startsWith(u8, cli.scenarioOrDefault(), "@")) {
        try zig_q.dst.runScenarioFile(
            allocator,
            cli.scenarioOrDefault()[1..],
            cli.seedOrDefault(),
            stdout,
            cli.semver,
        );
    } else {
        try zig_q.dst.runNamedScenario(
            allocator,
            cli.scenarioOrDefault(),
            cli.seedOrDefault(),
            stdout,
            cli.semver,
        );
    }
}