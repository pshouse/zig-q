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
        .name = "test",
        .root_module = zig_q_mod,
    });
    b.installArtifact(test_exe);
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

    const evidence_v09_exe = b.addExecutable(.{
        .name = "zig-q-evidence-v09",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/evidence_v09_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(evidence_v09_exe);

    const evidence_v09_run = b.addRunArtifact(evidence_v09_exe);
    const evidence_v09_step = b.step("evidence-v09", "Emit v0.9 generator/descend verification transcript");
    evidence_v09_step.dependOn(&evidence_v09_run.step);

    const evidence_v10_exe = b.addExecutable(.{
        .name = "zig-q-evidence-v10",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/evidence_v10_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(evidence_v10_exe);

    const evidence_v10_run = b.addRunArtifact(evidence_v10_exe);
    const evidence_v10_step = b.step("evidence-v10", "Emit v1.0 reference-crawl verification transcript");
    evidence_v10_step.dependOn(&evidence_v10_run.step);

    const evidence_v11_exe = b.addExecutable(.{
        .name = "zig-q-evidence-v11",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/evidence_v11_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(evidence_v11_exe);

    const evidence_v11_run = b.addRunArtifact(evidence_v11_exe);
    const evidence_v11_step = b.step("evidence-v11", "Emit v1.1 foundation verification transcript");
    evidence_v11_step.dependOn(&evidence_v11_run.step);

    const migration_v11_exe = b.addExecutable(.{
        .name = "zig-q-migration-v11",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/migration_v11_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(migration_v11_exe);

    const migration_v11_run = b.addRunArtifact(migration_v11_exe);
    const migration_v11_step = b.step("migration-v11", "Emit v1.0→v1.1 save migration transcript");
    migration_v11_step.dependOn(&migration_v11_run.step);

    const evidence_v12_exe = b.addExecutable(.{
        .name = "zig-q-evidence-v12",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/evidence_v12_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(evidence_v12_exe);

    const evidence_v12_run = b.addRunArtifact(evidence_v12_exe);
    const evidence_v12_step = b.step("evidence-v12", "Emit v1.2 mundane-gear verification transcript");
    evidence_v12_step.dependOn(&evidence_v12_run.step);

    const evidence_v13_exe = b.addExecutable(.{
        .name = "zig-q-evidence-v13",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/evidence_v13_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(evidence_v13_exe);

    const evidence_v13_run = b.addRunArtifact(evidence_v13_exe);
    const evidence_v13_step = b.step("evidence-v13", "Emit v1.3 living-dungeon verification transcript");
    evidence_v13_step.dependOn(&evidence_v13_run.step);

    const evidence_v14_exe = b.addExecutable(.{
        .name = "zig-q-evidence-v14",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/evidence_v14_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(evidence_v14_exe);

    const evidence_v14_run = b.addRunArtifact(evidence_v14_exe);
    const evidence_v14_step = b.step("evidence-v14", "Emit v1.4 survival-clock verification transcript");
    evidence_v14_step.dependOn(&evidence_v14_run.step);

    const evidence_v15_exe = b.addExecutable(.{
        .name = "zig-q-evidence-v15",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/evidence_v15_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(evidence_v15_exe);

    const evidence_v15_run = b.addRunArtifact(evidence_v15_exe);
    const evidence_v15_step = b.step("evidence-v15", "Emit v1.5 crawl-completeness verification transcript");
    evidence_v15_step.dependOn(&evidence_v15_run.step);

    const evidence_v16_exe = b.addExecutable(.{
        .name = "zig-q-evidence-v16",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/evidence_v16_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(evidence_v16_exe);

    const evidence_v16_run = b.addRunArtifact(evidence_v16_exe);
    const evidence_v16_step = b.step("evidence-v16", "Emit v1.6 depth-danger verification transcript");
    evidence_v16_step.dependOn(&evidence_v16_run.step);

    const evidence_v17_exe = b.addExecutable(.{
        .name = "zig-q-evidence-v17",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/evidence_v17_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(evidence_v17_exe);

    const evidence_v17_run = b.addRunArtifact(evidence_v17_exe);
    const evidence_v17_step = b.step("evidence-v17", "Emit v1.7 fair-danger verification transcript");
    evidence_v17_step.dependOn(&evidence_v17_run.step);

    const wave_gate_exe = b.addExecutable(.{
        .name = "zig-q-wave-gate",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wave_gate_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(wave_gate_exe);

    // Portable gate scratch: repo-relative `.gate-scratch/` (override via ZIG_Q_SCRATCH).
    // Same env var wave_gate.zig honors so build-log paths and gate captures share a root.
    const gate_scratch = b.graph.env_map.get("ZIG_Q_SCRATCH") orelse ".gate-scratch";

    inline for (.{ 11, 12, 13, 14, 15, 16, 17 }) |wave| {
        const prefix = b.fmt("v{d}", .{wave});
        const build_log = b.fmt("{s}\\{s}_build.log", .{ gate_scratch, prefix });

        // Plan step 1: top-level `zig build` shell redirect (raw, no post-processing).
        const build_capture = b.addSystemCommand(&.{
            "cmd", "/c",
            b.fmt(
                "if not exist {s} mkdir {s} && zig build 1>{s} 2>&1",
                .{ gate_scratch, gate_scratch, build_log },
            ),
        });
        build_capture.setCwd(b.path("."));
        build_capture.step.name = b.fmt("gate-v{d}-build", .{wave});

        const build_step = b.step(
            b.fmt("gate-v{d}-build", .{wave}),
            b.fmt("Per-wave zig build capture to {s}_build.log", .{prefix}),
        );
        build_step.dependOn(&build_capture.step);

        // Plan steps 2–8: wave-gate verifies build log then runs real zig build subcommands.
        const gate_run = b.addRunArtifact(wave_gate_exe);
        gate_run.addArg(b.fmt("{d}", .{wave}));
        gate_run.addArg("--skip-build");
        gate_run.step.dependOn(build_step);
        gate_run.step.dependOn(b.getInstallStep());

        const gate_step = b.step(
            b.fmt("gate-v{d}", .{wave}),
            b.fmt("Run v1.{d} release gate captures (steps 2–8)", .{wave - 10}),
        );
        gate_step.dependOn(&gate_run.step);
    }

    const consumer_test_exe = b.addTest(.{
        .name = "zig-q-consumer-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/consumer_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_q", .module = zig_q_mod },
            },
        }),
    });
    b.installArtifact(consumer_test_exe);
    const consumer_test_run = b.addRunArtifact(consumer_test_exe);
    const consumer_test_step = b.step("consumer-test", "Run public zig_q API integration tests");
    consumer_test_step.dependOn(&consumer_test_run.step);

    // Regenerate the committed reference_crawl golden that the release gate checks against.
    // Run this only when a change intentionally alters the reference crawl, then commit
    // references/reference_crawl.txt. The transcript is version-pinned to 1.1.0.
    const update_golden = b.addSystemCommand(&.{
        "cmd", "/c",
        "if not exist references mkdir references && " ++
            "zig-out\\bin\\zig-q-dst.exe reference_crawl 42 --semver 1.1.0 > references\\reference_crawl.txt",
    });
    update_golden.step.dependOn(b.getInstallStep());
    const update_golden_step = b.step(
        "update-reference-golden",
        "Regenerate references/reference_crawl.txt from the current build",
    );
    update_golden_step.dependOn(&update_golden.step);
}
