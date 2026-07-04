const std = @import("std");
const zig_q = @import("zig_q");
const io_out = @import("io_out.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const scenario = if (args.len >= 2) args[1] else "bootstrap";
    const seed: u64 = if (args.len >= 3) try std.fmt.parseInt(u64, args[2], 10) else zig_q.dst.default_scenario.seed;

    const stdout = io_out.stdoutWriter();
    try zig_q.dst.runNamedScenario(allocator, scenario, seed, stdout);
}