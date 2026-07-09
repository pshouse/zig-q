const std = @import("std");
const zig_q = @import("zig_q");
const io_out = @import("io_out.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var cfg = zig_q.fuzz.Config{};
    if (args.len >= 2) cfg.iterations = try std.fmt.parseInt(u32, args[1], 10);
    if (args.len >= 3) cfg.seed = try std.fmt.parseInt(u64, args[2], 10);
    if (args.len >= 4) cfg.world_seed = try std.fmt.parseInt(u64, args[3], 10);

    const stdout = io_out.stdoutWriter();
    try stdout.print("zig-q fuzz version={s} iterations={} seed={} world_seed={}\n", .{
        zig_q.version.semver,
        cfg.iterations,
        cfg.seed,
        cfg.world_seed,
    });

    var report = try zig_q.fuzz.run(allocator, cfg);
    defer report.deinit(allocator);
    if (!report.passed()) {
        const failure = report.failure.?;
        try stdout.print("fuzz failure at iteration={} step={}: {s}\n", .{
            failure.iteration,
            failure.step,
            failure.message,
        });
        for (failure.script) |line| {
            try stdout.print("> {s}\n", .{line});
        }
        return error.FuzzFailure;
    }

    try stdout.print("fuzz ok: {} iterations\n", .{report.iterations});
}