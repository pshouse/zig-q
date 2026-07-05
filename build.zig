const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_q_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    zig_q_mod.addIncludePath(b.path("deps/sqlite3"));
    zig_q_mod.addCSourceFiles(.{
        .files = &.{"deps/sqlite3/sqlite3.c"},
        .flags = &.{
            "-DSQLITE_THREADSAFE=0",
            "-DSQLITE_OMIT_LOAD_EXTENSION",
        },
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

    const fuzz_exe = b.addExecutable(.{
        .name = "zig-q-fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/fuzz_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(fuzz_exe);

    const fuzz_run = b.addRunArtifact(fuzz_exe);
    if (b.args) |args| fuzz_run.addArgs(args);
    const fuzz_step = b.step("fuzz", "Run deterministic REPL fuzz harness");
    fuzz_step.dependOn(&fuzz_run.step);

    const evidence_exe = b.addExecutable(.{
        .name = "zig-q-evidence",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/evidence_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(evidence_exe);

    const evidence_run = b.addRunArtifact(evidence_exe);
    const evidence_step = b.step("evidence", "Emit v0.7 combat verification transcript");
    evidence_step.dependOn(&evidence_run.step);

    const evidence_v08_exe = b.addExecutable(.{
        .name = "zig-q-evidence-v08",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/evidence_v08_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(evidence_v08_exe);

    const evidence_v08_run = b.addRunArtifact(evidence_v08_exe);
    const evidence_v08_step = b.step("evidence-v08", "Emit v0.8 save/load verification transcript");
    evidence_v08_step.dependOn(&evidence_v08_run.step);
}