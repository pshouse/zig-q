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
    if (args.len < 2) {
        try stdout.print("usage: wave-gate <11|12|13|14|15> [--skip-build] [scratch_dir]\n", .{});
        return error.InvalidArguments;
    }

    const wave = try std.fmt.parseInt(u8, args[1], 10);

    var skip_build = false;
    var scratch_override: ?[]const u8 = null;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--skip-build")) {
            skip_build = true;
        } else if (scratch_override == null) {
            scratch_override = args[i];
        }
    }

    if (!skip_build) {
        try stdout.print("error: use zig build gate-v{d} (build log must come from gate step redirect)\n", .{wave});
        return error.SkipBuildRequired;
    }

    const scratch = try zig_q.wave_gate.scratchDir(allocator, scratch_override);
    defer allocator.free(scratch);

    const summary = try zig_q.wave_gate.runWave(allocator, wave, scratch_override, .{
        .skip_build = true,
    });

    try zig_q.wave_gate.appendVerificationFooter(allocator, scratch, summary);

    var footer_buf: [256]u8 = undefined;
    const footer = try summary.formatFooter(&footer_buf);
    try stdout.print("{s}\n", .{footer});
}