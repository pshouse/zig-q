//! In-repo release gate runner for v1.1–v1.4 verification captures.
//! Invokes real `zig build` subcommands per plan verification steps.
const std = @import("std");
const version = @import("version.zig");

pub const default_scratch = "C:\\Users\\admin\\AppData\\Local\\Temp\\grok-goal-ed9bbd58ab86\\implementer";

pub const WavePlan = struct {
    wave: u8,
    prefix: []const u8,
    evidence_step: []const u8,
    new_scenarios: []const []const u8,
    all_scenarios: []const []const u8,
    run_migration: bool,
};

pub const plans = [_]WavePlan{
    .{
        .wave = 11,
        .prefix = "v11",
        .evidence_step = "evidence-v11",
        .new_scenarios = &.{
            "save_v2_roundtrip", "conditions_brawl", "los_peek", "ambush", "permadeath", "reference_crawl",
        },
        .all_scenarios = &.{
            "bootstrap", "explore", "create", "crawl_start", "playthrough", "brawl", "save_roundtrip",
            "descend_crawl", "reference_crawl", "save_v2_roundtrip", "conditions_brawl", "los_peek",
            "ambush", "permadeath",
        },
        .run_migration = true,
    },
    .{
        .wave = 12,
        .prefix = "v12",
        .evidence_step = "evidence-v12",
        .new_scenarios = &.{
            "loot_roundtrip", "geared_brawl", "corpse_loot", "encumbered", "reference_crawl",
        },
        .all_scenarios = &.{
            "bootstrap", "explore", "create", "crawl_start", "playthrough", "brawl", "save_roundtrip",
            "descend_crawl", "reference_crawl", "save_v2_roundtrip", "conditions_brawl", "los_peek",
            "ambush", "permadeath", "loot_roundtrip", "geared_brawl", "corpse_loot", "encumbered",
        },
        .run_migration = false,
    },
    .{
        .wave = 13,
        .prefix = "v13",
        .evidence_step = "evidence-v13",
        .new_scenarios = &.{
            "hunt", "flee", "trap_trigger", "door_route", "ambush", "reference_crawl",
        },
        .all_scenarios = &.{
            "bootstrap", "explore", "create", "crawl_start", "playthrough", "brawl", "save_roundtrip",
            "descend_crawl", "reference_crawl", "save_v2_roundtrip", "conditions_brawl", "los_peek",
            "ambush", "permadeath", "loot_roundtrip", "geared_brawl", "corpse_loot", "encumbered",
            "hunt", "flee", "trap_trigger", "door_route",
        },
        .run_migration = false,
    },
    .{
        .wave = 14,
        .prefix = "v14",
        .evidence_step = "evidence-v14",
        .new_scenarios = &.{
            "survive", "starve", "sleep_cycle", "reference_survive", "reference_crawl",
        },
        .all_scenarios = &.{
            "bootstrap", "explore", "create", "crawl_start", "playthrough", "brawl", "save_roundtrip",
            "descend_crawl", "reference_crawl", "save_v2_roundtrip", "conditions_brawl", "los_peek",
            "ambush", "permadeath", "loot_roundtrip", "geared_brawl", "corpse_loot", "encumbered",
            "hunt", "flee", "trap_trigger", "door_route", "survive", "starve", "sleep_cycle",
            "reference_survive",
        },
        .run_migration = false,
    },
};

pub const Options = struct {
    skip_build: bool = false,
};

pub const WaveSummary = struct {
    wave: u8,
    build_bytes: u64,
    tests_passed: u32,
    tests_total: u32,
    version: []const u8,
    ref_hash: [64]u8,
    fuzz_iters: u32,

    pub fn formatFooter(self: WaveSummary, buf: []u8) ![]const u8 {
        return std.fmt.bufPrint(buf, "gate-v{d}: build_bytes={d} tests={d}/{d} version={s} ref_hash={s} fuzz={d}", .{
            self.wave,
            self.build_bytes,
            self.tests_passed,
            self.tests_total,
            self.version,
            self.ref_hash[0..],
            self.fuzz_iters,
        });
    }
};

pub fn appendVerificationFooter(
    allocator: std.mem.Allocator,
    scratch: []const u8,
    summary: WaveSummary,
) !void {
    const verify_path = try joinPath(allocator, scratch, "gate_verification.txt");
    defer allocator.free(verify_path);

    var footer_buf: [256]u8 = undefined;
    const footer = try summary.formatFooter(&footer_buf);

    const wave_footer_leaf = try std.fmt.allocPrint(allocator, "v{d}_gate_footer.txt", .{summary.wave});
    defer allocator.free(wave_footer_leaf);
    const wave_footer_path = try joinPath(allocator, scratch, wave_footer_leaf);
    defer allocator.free(wave_footer_path);
    try writeCapture(wave_footer_path, footer);

    if (summary.wave == 11) {
        const header = try std.fmt.allocPrint(allocator, "=== zig-q 1.x gate verification ===\n", .{});
        defer allocator.free(header);
        const file = try std.fs.cwd().createFile(verify_path, .{});
        defer file.close();
        try file.writeAll(header);
        try file.writeAll(footer);
        try file.writeAll("\n");
    } else {
        const file = try std.fs.cwd().openFile(verify_path, .{ .mode = .read_write });
        defer file.close();
        try file.seekFromEnd(0);
        try file.writeAll(footer);
        try file.writeAll("\n");
    }

    if (summary.wave == 14) {
        var hash_match = true;
        var first_hash: ?[64]u8 = null;
        const prefixes = [_][]const u8{ "v11", "v12", "v13", "v14" };
        for (prefixes) |prefix| {
            const leaf = try std.fmt.allocPrint(allocator, "{s}_dst_reference_crawl_a.txt", .{prefix});
            defer allocator.free(leaf);
            const ref_path = try joinPath(allocator, scratch, leaf);
            defer allocator.free(ref_path);
            const data = std.fs.cwd().readFileAlloc(allocator, ref_path, 16 * 1024 * 1024) catch {
                hash_match = false;
                continue;
            };
            defer allocator.free(data);
            var h: [64]u8 = undefined;
            sha256Hex(data, &h);
            if (first_hash) |fh| {
                if (!std.mem.eql(u8, &fh, &h)) hash_match = false;
            } else {
                first_hash = h;
            }
        }
        const cross = if (hash_match and first_hash != null)
            try std.fmt.allocPrint(allocator, "cross_wave_reference: v11==v12==v13==v14 ref_hash={s}\n", .{first_hash.?[0..]})
        else
            try std.fmt.allocPrint(allocator, "cross_wave_reference: MISMATCH\n", .{});
        defer allocator.free(cross);
        const file = try std.fs.cwd().openFile(verify_path, .{ .mode = .read_write });
        defer file.close();
        try file.seekFromEnd(0);
        try file.writeAll(cross);
    }
}

pub fn planForWave(wave: u8) ?WavePlan {
    for (plans) |p| {
        if (p.wave == wave) return p;
    }
    return null;
}

pub fn scratchDir(allocator: std.mem.Allocator, override: ?[]const u8) ![]const u8 {
    if (override) |path| return try allocator.dupe(u8, path);
    const env_path = std.process.getEnvVarOwned(allocator, "ZIG_Q_SCRATCH") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return try allocator.dupe(u8, default_scratch),
        else => |e| return e,
    };
    return env_path;
}

const RunResult = struct {
    exit_code: u32,
    output: []const u8,
};

fn zigExe(allocator: std.mem.Allocator) ![]const u8 {
    return try allocator.dupe(u8, "zig");
}

fn runProcess(allocator: std.mem.Allocator, argv: []const []const u8) !RunResult {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    const stdout_pipe = child.stdout orelse return error.MissingStdout;
    const stderr_pipe = child.stderr orelse return error.MissingStderr;

    const ReadCtx = struct {
        pipe: std.fs.File,
        output: ?[]u8 = null,
        allocator: std.mem.Allocator,
        fn run(ctx: *@This()) void {
            ctx.output = ctx.pipe.readToEndAlloc(ctx.allocator, 64 * 1024 * 1024) catch null;
        }
    };

    var stdout_ctx: ReadCtx = .{ .pipe = stdout_pipe, .allocator = allocator };
    var stderr_ctx: ReadCtx = .{ .pipe = stderr_pipe, .allocator = allocator };
    defer if (stdout_ctx.output) |out| allocator.free(out);
    defer if (stderr_ctx.output) |out| allocator.free(out);

    const stdout_thread = try std.Thread.spawn(.{}, ReadCtx.run, .{&stdout_ctx});
    const stderr_thread = try std.Thread.spawn(.{}, ReadCtx.run, .{&stderr_ctx});

    const term = try child.wait();
    stdout_thread.join();
    stderr_thread.join();

    const exit_code: u32 = switch (term) {
        .Exited => |code| code,
        else => 1,
    };

    const stdout = stdout_ctx.output orelse "";
    const stderr = stderr_ctx.output orelse "";
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ stdout, stderr });
    return .{ .exit_code = exit_code, .output = combined };
}

fn runZigBuild(allocator: std.mem.Allocator, build_args: []const []const u8) !RunResult {
    const zig = try zigExe(allocator);
    defer allocator.free(zig);

    var argv = try allocator.alloc([]const u8, build_args.len + 2);
    defer allocator.free(argv);
    argv[0] = zig;
    argv[1] = "build";
    @memcpy(argv[2..], build_args);
    return runProcess(allocator, argv);
}

fn writeCapture(path: []const u8, output: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(output);
}

fn joinPath(allocator: std.mem.Allocator, scratch: []const u8, leaf: []const u8) ![]const u8 {
    return std.fs.path.join(allocator, &.{ scratch, leaf });
}

fn requireExit(result: RunResult, allocator: std.mem.Allocator) ![]const u8 {
    if (result.exit_code != 0) {
        allocator.free(result.output);
        return error.GateCommandFailed;
    }
    return result.output;
}

fn verifyBuildLog(allocator: std.mem.Allocator, scratch: []const u8, prefix: []const u8) !u64 {
    const leaf = try std.fmt.allocPrint(allocator, "{s}_build.log", .{prefix});
    defer allocator.free(leaf);
    const full_path = try joinPath(allocator, scratch, leaf);
    defer allocator.free(full_path);

    const file = std.fs.cwd().openFile(full_path, .{}) catch return error.MissingBuildLog;
    defer file.close();
    return file.getEndPos();
}

fn sha256Hex(data: []const u8, out: *[64]u8) void {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &hash, .{});
    const hex = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        out[i * 2] = hex[byte >> 4];
        out[i * 2 + 1] = hex[byte & 0xf];
    }
}

fn parseTestCounts(output: []const u8) !struct { passed: u32, total: u32 } {
    const marker = " tests passed";
    var iter = std.mem.splitScalar(u8, output, '\n');
    while (iter.next()) |line| {
        const end = std.mem.indexOf(u8, line, marker) orelse continue;
        const head = std.mem.trim(u8, line[0..end], " \t");
        const slash = std.mem.lastIndexOf(u8, head, "/") orelse continue;
        const passed_start = std.mem.lastIndexOfScalar(u8, head[0..slash], ' ');
        const passed_str = if (passed_start) |ps| head[ps + 1 .. slash] else head[0..slash];
        const total_str = head[slash + 1 ..];
        const passed = try std.fmt.parseInt(u32, passed_str, 10);
        const total = try std.fmt.parseInt(u32, total_str, 10);
        return .{ .passed = passed, .total = total };
    }
    return error.TestMissingPassLine;
}

fn parseFuzzIters(output: []const u8) !u32 {
    if (std.mem.indexOf(u8, output, "fuzz ok:") == null) return error.FuzzMissingSuccess;
    const marker = "fuzz ok: ";
    const pos = std.mem.indexOf(u8, output, marker) orelse return error.FuzzMissingSuccess;
    const tail = output[pos + marker.len ..];
    var iter = std.mem.tokenizeAny(u8, tail, " \t\r\n");
    const n_str = iter.next() orelse return error.FuzzMissingSuccess;
    return try std.fmt.parseInt(u32, n_str, 10);
}

fn dstSemverForScenario(wave: u8, scenario: []const u8) []const u8 {
    if (version.isFrozenReference(scenario)) return version.v11;
    return version.wave(wave);
}

fn captureDstPair(
    allocator: std.mem.Allocator,
    wave: u8,
    scratch: []const u8,
    prefix: []const u8,
    scenario: []const u8,
) !void {
    const semver = dstSemverForScenario(wave, scenario);
    var header_buf: [64]u8 = undefined;
    const header = try version.versionLine(&header_buf, semver);

    const leaf_a = try std.fmt.allocPrint(allocator, "{s}_dst_{s}_a.txt", .{ prefix, scenario });
    defer allocator.free(leaf_a);
    const leaf_b = try std.fmt.allocPrint(allocator, "{s}_dst_{s}_b.txt", .{ prefix, scenario });
    defer allocator.free(leaf_b);

    const dst_args = [_][]const u8{ "dst", "--", scenario, "42", "--semver", semver };
    const result_a = try runZigBuild(allocator, &dst_args);
    const out_a = try requireExit(result_a, allocator);
    defer allocator.free(out_a);
    const result_b = try runZigBuild(allocator, &dst_args);
    const out_b = try requireExit(result_b, allocator);
    defer allocator.free(out_b);

    if (!std.mem.eql(u8, out_a, out_b)) return error.DstNotIdentical;
    if (std.mem.indexOf(u8, out_a, header) == null) return error.DstMissingVersionHeader;

    const path_a = try joinPath(allocator, scratch, leaf_a);
    defer allocator.free(path_a);
    const path_b = try joinPath(allocator, scratch, leaf_b);
    defer allocator.free(path_b);
    try writeCapture(path_a, out_a);
    try writeCapture(path_b, out_b);
}

fn captureDstAll(
    allocator: std.mem.Allocator,
    wave: u8,
    scratch: []const u8,
    prefix: []const u8,
    scenarios: []const []const u8,
) !void {
    const leaf = try std.fmt.allocPrint(allocator, "{s}_dst_all.log", .{prefix});
    defer allocator.free(leaf);
    const path = try joinPath(allocator, scratch, leaf);
    defer allocator.free(path);

    var list = std.ArrayListUnmanaged(u8){};
    defer list.deinit(allocator);

    for (scenarios) |scenario| {
        try list.writer(allocator).print("=== {s} ===\n", .{scenario});
        const semver = dstSemverForScenario(wave, scenario);
        const dst_args = [_][]const u8{ "dst", "--", scenario, "42", "--semver", semver };
        const result = try runZigBuild(allocator, &dst_args);
        const output = try requireExit(result, allocator);
        defer allocator.free(output);
        try list.writer(allocator).writeAll(output);
    }

    try writeCapture(path, list.items);
}

fn captureVersionTwice(
    allocator: std.mem.Allocator,
    wave: u8,
    scratch: []const u8,
    prefix: []const u8,
) !void {
    const gate = version.forGate(wave);
    const args = [_][]const u8{ "run", "--", "--version", "--semver", gate.emit };

    const leaf1 = try std.fmt.allocPrint(allocator, "{s}_version1.log", .{prefix});
    defer allocator.free(leaf1);
    const leaf2 = try std.fmt.allocPrint(allocator, "{s}_version2.log", .{prefix});
    defer allocator.free(leaf2);

    const result1 = try runZigBuild(allocator, &args);
    const out1 = try requireExit(result1, allocator);
    defer allocator.free(out1);
    const result2 = try runZigBuild(allocator, &args);
    const out2 = try requireExit(result2, allocator);
    defer allocator.free(out2);

    const trimmed1 = std.mem.trim(u8, out1, " \t\r\n");
    const trimmed2 = std.mem.trim(u8, out2, " \t\r\n");
    if (!std.mem.eql(u8, trimmed1, gate.emit) or !std.mem.eql(u8, trimmed2, gate.emit)) {
        return error.VersionMismatch;
    }

    const path1 = try joinPath(allocator, scratch, leaf1);
    defer allocator.free(path1);
    const path2 = try joinPath(allocator, scratch, leaf2);
    defer allocator.free(path2);
    try writeCapture(path1, out1);
    try writeCapture(path2, out2);
}

fn verifyEvidence(output: []const u8, wave: u8) !void {
    const gate = version.forGate(wave);
    if (std.mem.indexOf(u8, output, ": true") == null) return error.EvidenceMissingTrue;
    if (std.mem.indexOf(u8, output, gate.emit) == null) return error.EvidenceMissingWaveVersion;
}

fn verifyMigration(output: []const u8) !void {
    if (std.mem.indexOf(u8, output, "evidence:") != null) return error.MigrationContainsEvidence;
    if (std.mem.indexOf(u8, output, "migration schema=2") == null) return error.MigrationMissingSchema;
}

fn verifyFuzz(output: []const u8) !void {
    if (std.mem.indexOf(u8, output, "fuzz ok:") == null) return error.FuzzMissingSuccess;
}

fn verifyTest(output: []const u8) !void {
    _ = try parseTestCounts(output);
}

fn verifyConsumer(output: []const u8) !void {
    if (std.mem.indexOf(u8, output, "tests passed") == null and
        std.mem.indexOf(u8, output, "All ") == null)
    {
        return error.ConsumerMissingPassLine;
    }
}

pub fn runWave(
    allocator: std.mem.Allocator,
    wave: u8,
    scratch_override: ?[]const u8,
    opts: Options,
) !WaveSummary {
    const plan = planForWave(wave) orelse return error.UnknownWave;
    const scratch = try scratchDir(allocator, scratch_override);
    defer allocator.free(scratch);

    std.fs.cwd().makePath(scratch) catch {};

    if (!opts.skip_build) return error.SkipBuildRequired;
    const build_bytes = try verifyBuildLog(allocator, scratch, plan.prefix);

    const test_leaf = try std.fmt.allocPrint(allocator, "{s}_test.log", .{plan.prefix});
    defer allocator.free(test_leaf);
    const test_result = try runZigBuild(allocator, &.{ "test", "--summary", "all" });
    const test_out = try requireExit(test_result, allocator);
    defer allocator.free(test_out);
    try verifyTest(test_out);
    const test_counts = try parseTestCounts(test_out);
    const test_path = try joinPath(allocator, scratch, test_leaf);
    defer allocator.free(test_path);
    try writeCapture(test_path, test_out);

    const consumer_leaf = try std.fmt.allocPrint(allocator, "{s}_consumer.log", .{plan.prefix});
    defer allocator.free(consumer_leaf);
    const consumer_result = try runZigBuild(allocator, &.{ "consumer-test", "--summary", "all" });
    const consumer_out = try requireExit(consumer_result, allocator);
    defer allocator.free(consumer_out);
    try verifyConsumer(consumer_out);
    const consumer_path = try joinPath(allocator, scratch, consumer_leaf);
    defer allocator.free(consumer_path);
    try writeCapture(consumer_path, consumer_out);

    try captureVersionTwice(allocator, wave, scratch, plan.prefix);

    for (plan.new_scenarios) |scenario| {
        try captureDstPair(allocator, wave, scratch, plan.prefix, scenario);
    }

    try captureDstAll(allocator, wave, scratch, plan.prefix, plan.all_scenarios);

    const fuzz_leaf = try std.fmt.allocPrint(allocator, "{s}_fuzz.log", .{plan.prefix});
    defer allocator.free(fuzz_leaf);
    const fuzz_result = try runZigBuild(allocator, &.{"fuzz"});
    const fuzz_out = try requireExit(fuzz_result, allocator);
    defer allocator.free(fuzz_out);
    try verifyFuzz(fuzz_out);
    const fuzz_path = try joinPath(allocator, scratch, fuzz_leaf);
    defer allocator.free(fuzz_path);
    try writeCapture(fuzz_path, fuzz_out);

    const evidence_leaf = try std.fmt.allocPrint(allocator, "{s}_evidence.log", .{plan.prefix});
    defer allocator.free(evidence_leaf);
    const evidence_args = [_][]const u8{plan.evidence_step};
    const evidence_result = try runZigBuild(allocator, &evidence_args);
    const evidence_out = try requireExit(evidence_result, allocator);
    defer allocator.free(evidence_out);
    try verifyEvidence(evidence_out, wave);
    const evidence_path = try joinPath(allocator, scratch, evidence_leaf);
    defer allocator.free(evidence_path);
    try writeCapture(evidence_path, evidence_out);

    if (plan.run_migration) {
        const migration_result = try runZigBuild(allocator, &.{"migration-v11"});
        const migration_out = try requireExit(migration_result, allocator);
        defer allocator.free(migration_out);
        try verifyMigration(migration_out);
        const migration_path = try joinPath(allocator, scratch, "v11_migration.log");
        defer allocator.free(migration_path);
        try writeCapture(migration_path, migration_out);
    }

    const ref_leaf = try std.fmt.allocPrint(allocator, "{s}_dst_reference_crawl_a.txt", .{plan.prefix});
    defer allocator.free(ref_leaf);
    const ref_path = try joinPath(allocator, scratch, ref_leaf);
    defer allocator.free(ref_path);
    const ref_data = try std.fs.cwd().readFileAlloc(allocator, ref_path, 16 * 1024 * 1024);
    defer allocator.free(ref_data);

    var ref_hash: [64]u8 = undefined;
    sha256Hex(ref_data, &ref_hash);

    const fuzz_iters = try parseFuzzIters(fuzz_out);

    return .{
        .wave = wave,
        .build_bytes = build_bytes,
        .tests_passed = test_counts.passed,
        .tests_total = test_counts.total,
        .version = version.forGate(wave).emit,
        .ref_hash = ref_hash,
        .fuzz_iters = fuzz_iters,
    };
}

test "planForWave covers v11-v14" {
    try std.testing.expect(planForWave(11) != null);
    try std.testing.expect(planForWave(14) != null);
    try std.testing.expect(planForWave(9) == null);
}

test "dstSemverForScenario pins reference_crawl" {
    try std.testing.expectEqualStrings("1.1.0", dstSemverForScenario(14, "reference_crawl"));
    try std.testing.expectEqualStrings("1.4.0", dstSemverForScenario(14, "survive"));
}

test "parseTestCounts reads 144/144 from build summary" {
    const sample =
        \\Build Summary: 3/3 steps succeeded; 144/144 tests passed
        \\test success
    ;
    const counts = try parseTestCounts(sample);
    try std.testing.expectEqual(@as(u32, 144), counts.passed);
    try std.testing.expectEqual(@as(u32, 144), counts.total);
}