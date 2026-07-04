const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_q_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zig-q",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Run zig-q");
    run_step.dependOn(&run_exe.step);

    const test_exe = b.addTest(.{
        .root_module = zig_q_mod,
    });
    const test_run = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_run.step);

    const dst_exe = b.addExecutable(.{
        .name = "zig-q-dst",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/dst_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(dst_exe);

    const dst_run = b.addRunArtifact(dst_exe);
    if (b.args) |args| dst_run.addArgs(args);
    const dst_step = b.step("dst", "Run deterministic simulation harness");
    dst_step.dependOn(&dst_run.step);
}