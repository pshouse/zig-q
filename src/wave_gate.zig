//! In-repo release gate runner for v1.1–v1.6 verification captures.
//! Invokes real `zig build` subcommands per plan verification steps.
const std = @import("std");
const version = @import("version.zig");

/// Repo-relative default; override with `ZIG_Q_SCRATCH` or CLI `--scratch`.
pub const default_scratch = ".gate-scratch";

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
            "bootstrap",     "explore",         "create",            "crawl_start",      "playthrough", "brawl",  "save_roundtrip",
            "descend_crawl", "reference_crawl", "save_v2_roundtrip", "conditions_brawl", "los_peek",    "ambush", "permadeath",
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
            "bootstrap",      "explore",         "create",            "crawl_start",      "playthrough", "brawl",  "save_roundtrip",
            "descend_crawl",  "reference_crawl", "save_v2_roundtrip", "conditions_brawl", "los_peek",    "ambush", "permadeath",
            "loot_roundtrip", "geared_brawl",    "corpse_loot",       "encumbered",
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
            "bootstrap",      "explore",         "create",            "crawl_start",      "playthrough", "brawl",  "save_roundtrip",
            "descend_crawl",  "reference_crawl", "save_v2_roundtrip", "conditions_brawl", "los_peek",    "ambush", "permadeath",
            "loot_roundtrip", "geared_brawl",    "corpse_loot",       "encumbered",       "hunt",        "flee",   "trap_trigger",
            "door_route",
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
            "bootstrap",      "explore",         "create",            "crawl_start",      "playthrough",       "brawl",  "save_roundtrip",
            "descend_crawl",  "reference_crawl", "save_v2_roundtrip", "conditions_brawl", "los_peek",          "ambush", "permadeath",
            "loot_roundtrip", "geared_brawl",    "corpse_loot",       "encumbered",       "hunt",              "flee",   "trap_trigger",
            "door_route",     "survive",         "starve",            "sleep_cycle",      "reference_survive",
        },
        .run_migration = false,
    },
    .{
        .wave = 15,
        .prefix = "v15",
        .evidence_step = "evidence-v15",
        .new_scenarios = &.{
            "heal_bandage", "trap_floor", "deep_floor", "reference_crawl",
        },
        .all_scenarios = &.{
            "bootstrap",      "explore",         "create",            "crawl_start",      "playthrough",       "brawl",        "save_roundtrip",
            "descend_crawl",  "reference_crawl", "save_v2_roundtrip", "conditions_brawl", "los_peek",          "ambush",       "permadeath",
            "loot_roundtrip", "geared_brawl",    "corpse_loot",       "encumbered",       "hunt",              "flee",         "trap_trigger",
            "door_route",     "survive",         "starve",            "sleep_cycle",      "reference_survive", "heal_bandage", "trap_floor",
            "deep_floor",
        },
        .run_migration = false,
    },
    .{
        .wave = 16,
        .prefix = "v16",
        .evidence_step = "evidence-v16",
        .new_scenarios = &.{
            "deadly_floor",     "elite_brawl",   "scarce_heals",    "save_v4_roundtrip", "sleep_interrupt",
            "rest_floor",       "combat_flee",   "catch_breath",    "unequip_cycle",     "drop_clears_slot",
            "bare_loot_corpse", "weaker_weapon", "reference_crawl",
        },
        .all_scenarios = &.{
            "bootstrap",         "explore",         "create",            "crawl_start",      "playthrough",       "brawl",         "save_roundtrip",
            "descend_crawl",     "reference_crawl", "save_v2_roundtrip", "conditions_brawl", "los_peek",          "ambush",        "permadeath",
            "loot_roundtrip",    "geared_brawl",    "corpse_loot",       "encumbered",       "hunt",              "flee",          "trap_trigger",
            "door_route",        "survive",         "starve",            "sleep_cycle",      "reference_survive", "heal_bandage",  "trap_floor",
            "deep_floor",        "rest_floor",      "combat_flee",       "catch_breath",     "deadly_floor",      "elite_brawl",   "scarce_heals",
            "save_v4_roundtrip", "sleep_interrupt", "unequip_cycle",     "drop_clears_slot", "bare_loot_corpse",  "weaker_weapon",
        },
        .run_migration = true,
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

const v15_feature_scenarios = [_][]const u8{ "heal_bandage", "trap_floor", "deep_floor" };

/// Builds completion prose from gate captures only (no hand-authored counts).
pub fn formatV15CompletionSummary(
    allocator: std.mem.Allocator,
    footer: []const u8,
    deep_floor_dst: []const u8,
    repl_bandage: []const u8,
) ![]const u8 {
    if (std.mem.indexOf(u8, repl_bandage, "used bandage; healed 5 hp") == null)
        return error.ReplMissingFlatHeal;

    var depth_lines = std.ArrayList(u8).empty;
    defer depth_lines.deinit(allocator);

    var pos: usize = 0;
    while (pos < deep_floor_dst.len) {
        const rel = std.mem.indexOf(u8, deep_floor_dst[pos..], "floor=") orelse break;
        const abs = pos + rel;
        const line_end = std.mem.indexOfScalarPos(u8, deep_floor_dst, abs, '\n') orelse deep_floor_dst.len;
        var row_buf: [128]u8 = undefined;
        const row = try std.fmt.bufPrint(&row_buf, "  {s}\n", .{deep_floor_dst[abs..line_end]});
        try depth_lines.appendSlice(allocator, row);
        pos = line_end + 1;
    }
    if (depth_lines.items.len == 0) return error.MissingDepthReport;

    var scenarios = std.ArrayList(u8).empty;
    defer scenarios.deinit(allocator);
    for (v15_feature_scenarios, 0..) |name, i| {
        if (i > 0) try scenarios.appendSlice(allocator, ", ");
        try scenarios.appendSlice(allocator, name);
    }

    return std.fmt.allocPrint(allocator,
        \\zig-q v{s} release complete
        \\
        \\{s}
        \\
        \\depth scaling (seed 42):
        \\{s}
        \\repl bandage capture: used bandage; healed 5 hp
        \\
        \\new dst scenarios: {s}
        \\
    , .{ version.semver, footer, depth_lines.items, scenarios.items });
}

pub fn writeV15CompletionSummary(
    allocator: std.mem.Allocator,
    scratch: []const u8,
    summary: WaveSummary,
) !void {
    var footer_buf: [256]u8 = undefined;
    const footer = try summary.formatFooter(&footer_buf);

    const deep_path = try joinPath(allocator, scratch, "v15_dst_deep_floor_a.txt");
    defer allocator.free(deep_path);
    const deep = try std.fs.cwd().readFileAlloc(allocator, deep_path, 16 * 1024 * 1024);
    defer allocator.free(deep);

    const repl_path = try joinPath(allocator, scratch, "repl-bandage.txt");
    defer allocator.free(repl_path);
    const repl = try std.fs.cwd().readFileAlloc(allocator, repl_path, 16 * 1024 * 1024);
    defer allocator.free(repl);

    const text = try formatV15CompletionSummary(allocator, footer, deep, repl);
    defer allocator.free(text);

    const out_path = try joinPath(allocator, scratch, "v15_completion.txt");
    defer allocator.free(out_path);
    try writeCapture(out_path, text);
}

/// reference_crawl is version-invariant (its transcript is pinned to `# version=1.1.0`),
/// so its canonical bytes are committed once as a golden. Regenerate with
/// `zig build update-reference-golden` whenever a change intentionally alters the crawl.
pub const reference_golden_path = "references/reference_crawl.txt";

/// Byte comparison that ignores carriage returns, so a golden checked out as CRLF
/// still matches the LF-only bytes captured from process stdout.
fn eqlIgnoringCr(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (true) {
        while (i < a.len and a[i] == '\r') i += 1;
        while (j < b.len and b[j] == '\r') j += 1;
        const a_done = i >= a.len;
        const b_done = j >= b.len;
        if (a_done or b_done) return a_done and b_done;
        if (a[i] != b[j]) return false;
        i += 1;
        j += 1;
    }
}

/// Compares this wave's freshly captured reference_crawl against the committed golden.
/// Returns a status line on match; a genuine difference is a regression and returns
/// `error.ReferenceCrawlRegression` so the gate fails. Unlike the old cross-wave check
/// this needs no prior-wave gate runs and can never report a fabricated pass.
fn verifyReferenceGolden(allocator: std.mem.Allocator, scratch: []const u8, prefix: []const u8) ![]const u8 {
    const leaf = try std.fmt.allocPrint(allocator, "{s}_dst_reference_crawl_a.txt", .{prefix});
    defer allocator.free(leaf);
    const fresh_path = try joinPath(allocator, scratch, leaf);
    defer allocator.free(fresh_path);
    const fresh = try std.fs.cwd().readFileAlloc(allocator, fresh_path, 16 * 1024 * 1024);
    defer allocator.free(fresh);

    const golden = std.fs.cwd().readFileAlloc(allocator, reference_golden_path, 16 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return error.ReferenceGoldenMissing,
        else => return err,
    };
    defer allocator.free(golden);

    if (!eqlIgnoringCr(fresh, golden)) return error.ReferenceCrawlRegression;

    var h: [64]u8 = undefined;
    sha256Hex(fresh, &h);
    return try std.fmt.allocPrint(allocator, "reference_crawl: matches committed golden ref_hash={s}\n", .{h[0..]});
}

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

    const verify_exists = blk: {
        std.fs.cwd().access(verify_path, .{}) catch break :blk false;
        break :blk true;
    };
    if (summary.wave == 11 or !verify_exists) {
        const header = if (summary.wave == 11)
            try std.fmt.allocPrint(allocator, "=== zig-q 1.x gate verification ===\n", .{})
        else
            try allocator.dupe(u8, "");
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

    {
        var prefix_buf: [8]u8 = undefined;
        const prefix = try std.fmt.bufPrint(&prefix_buf, "v{d}", .{summary.wave});
        const status = try verifyReferenceGolden(allocator, scratch, prefix);
        defer allocator.free(status);
        const file = try std.fs.cwd().openFile(verify_path, .{ .mode = .read_write });
        defer file.close();
        try file.seekFromEnd(0);
        try file.writeAll(status);
    }

    if (summary.wave == 15) {
        // Convenience artifact only: the verification file is already fully written,
        // so a missing/oversized capture here must not corrupt it or fail the gate
        // with a misattributed error.
        writeV15CompletionSummary(allocator, scratch, summary) catch |err| {
            std.log.warn("v15 completion summary skipped: {s}", .{@errorName(err)});
        };
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

const max_capture_bytes = 64 * 1024 * 1024;

fn runProcess(allocator: std.mem.Allocator, argv: []const []const u8) !RunResult {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    var stdout_list: std.ArrayList(u8) = .empty;
    defer stdout_list.deinit(allocator);
    var stderr_list: std.ArrayList(u8) = .empty;
    defer stderr_list.deinit(allocator);
    try child.collectOutput(allocator, &stdout_list, &stderr_list, max_capture_bytes);

    const term = try child.wait();
    const exit_code: u32 = switch (term) {
        .Exited => |code| code,
        else => 1,
    };

    const stdout = try stdout_list.toOwnedSlice(allocator);
    defer allocator.free(stdout);
    const stderr = try stderr_list.toOwnedSlice(allocator);
    defer allocator.free(stderr);
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

fn runZigReplScript(allocator: std.mem.Allocator, seed: u64, script: []const u8) !RunResult {
    const seed_str = try std.fmt.allocPrint(allocator, "{d}", .{seed});
    defer allocator.free(seed_str);
    const zig = try zigExe(allocator);
    defer allocator.free(zig);

    const argv = [_][]const u8{ zig, "build", "run", "--", "--repl", seed_str, "--playtest" };
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    // Feed stdin on a separate thread so the child's stdout is drained concurrently.
    // Writing the whole script before reading would deadlock once the child's echoed
    // output fills the OS pipe buffer while we're still blocked writing stdin.
    const stdin_pipe = child.stdin orelse return error.MissingStdin;
    child.stdin = null;
    const Feeder = struct {
        pipe: std.fs.File,
        data: []const u8,
        fn run(f: @This()) void {
            f.pipe.writeAll(f.data) catch {};
            f.pipe.close();
        }
    };
    const feeder = try std.Thread.spawn(.{}, Feeder.run, .{Feeder{ .pipe = stdin_pipe, .data = script }});

    var stdout_list: std.ArrayList(u8) = .empty;
    defer stdout_list.deinit(allocator);
    var stderr_list: std.ArrayList(u8) = .empty;
    defer stderr_list.deinit(allocator);
    try child.collectOutput(allocator, &stdout_list, &stderr_list, max_capture_bytes);
    feeder.join();

    const term = try child.wait();
    const exit_code: u32 = switch (term) {
        .Exited => |code| code,
        else => 1,
    };

    const stdout = try stdout_list.toOwnedSlice(allocator);
    defer allocator.free(stdout);
    const stderr = try stderr_list.toOwnedSlice(allocator);
    defer allocator.free(stderr);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ stdout, stderr });
    return .{ .exit_code = exit_code, .output = combined };
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

fn isV15PlanDstScenario(scenario: []const u8) bool {
    return std.mem.eql(u8, scenario, "heal_bandage") or
        std.mem.eql(u8, scenario, "trap_floor") or
        std.mem.eql(u8, scenario, "deep_floor");
}

fn copyScratchLeaf(allocator: std.mem.Allocator, scratch: []const u8, src_leaf: []const u8, dst_leaf: []const u8) !void {
    const src_path = try joinPath(allocator, scratch, src_leaf);
    defer allocator.free(src_path);
    const dst_path = try joinPath(allocator, scratch, dst_leaf);
    defer allocator.free(dst_path);
    const data = try std.fs.cwd().readFileAlloc(allocator, src_path, 64 * 1024 * 1024);
    defer allocator.free(data);
    try writeCapture(dst_path, data);
}

const repl_bandage_script =
    \\assign 6 5 4 3 2 1
    \\race 2
    \\class 1
    \\spawn
    \\wound
    \\wound
    \\use bandage
    \\stats
    \\exit
    \\
;

fn verifyReplBandage(output: []const u8) !void {
    if (std.mem.indexOf(u8, output, "used bandage; healed 5 hp") == null) return error.ReplMissingBandageHeal;
    if (std.mem.indexOf(u8, output, "HP:") == null) return error.ReplMissingHp;
}

fn captureReplBandage(allocator: std.mem.Allocator, scratch: []const u8, prefix: []const u8) !void {
    const script_path = try joinPath(allocator, scratch, "repl-bandage-script.txt");
    defer allocator.free(script_path);
    try writeCapture(script_path, repl_bandage_script);

    const result = try runZigReplScript(allocator, 42, repl_bandage_script);
    const output = try requireExit(result, allocator);
    defer allocator.free(output);
    try verifyReplBandage(output);

    const prefix_leaf = try std.fmt.allocPrint(allocator, "{s}_repl-bandage.txt", .{prefix});
    defer allocator.free(prefix_leaf);
    const prefix_path = try joinPath(allocator, scratch, prefix_leaf);
    defer allocator.free(prefix_path);
    try writeCapture(prefix_path, output);

    const plan_path = try joinPath(allocator, scratch, "repl-bandage.txt");
    defer allocator.free(plan_path);
    try writeCapture(plan_path, output);
}

fn mirrorV15PlanCaptures(allocator: std.mem.Allocator, scratch: []const u8, prefix: []const u8) !void {
    const test_leaf = try std.fmt.allocPrint(allocator, "{s}_test.log", .{prefix});
    defer allocator.free(test_leaf);
    const fuzz_leaf = try std.fmt.allocPrint(allocator, "{s}_fuzz.log", .{prefix});
    defer allocator.free(fuzz_leaf);
    const consumer_leaf = try std.fmt.allocPrint(allocator, "{s}_consumer.log", .{prefix});
    defer allocator.free(consumer_leaf);
    const evidence_leaf = try std.fmt.allocPrint(allocator, "{s}_evidence.log", .{prefix});
    defer allocator.free(evidence_leaf);
    const version_leaf = try std.fmt.allocPrint(allocator, "{s}_version1.log", .{prefix});
    defer allocator.free(version_leaf);

    try copyScratchLeaf(allocator, scratch, test_leaf, "test.log");
    try copyScratchLeaf(allocator, scratch, fuzz_leaf, "fuzz.log");
    try copyScratchLeaf(allocator, scratch, consumer_leaf, "consumer.log");
    try copyScratchLeaf(allocator, scratch, evidence_leaf, "evidence-v15.log");
    try copyScratchLeaf(allocator, scratch, version_leaf, "version.log");
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

    if (wave == 15 and isV15PlanDstScenario(scenario)) {
        const plan_a = try std.fmt.allocPrint(allocator, "dst-v15-{s}-a.log", .{scenario});
        defer allocator.free(plan_a);
        const plan_b = try std.fmt.allocPrint(allocator, "dst-v15-{s}-b.log", .{scenario});
        defer allocator.free(plan_b);
        const plan_path_a = try joinPath(allocator, scratch, plan_a);
        defer allocator.free(plan_path_a);
        const plan_path_b = try joinPath(allocator, scratch, plan_b);
        defer allocator.free(plan_path_b);
        try writeCapture(plan_path_a, out_a);
        try writeCapture(plan_path_b, out_b);
    }
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

    if (wave == 15) {
        try captureReplBandage(allocator, scratch, plan.prefix);
        try mirrorV15PlanCaptures(allocator, scratch, plan.prefix);
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

test "planForWave covers v11-v15" {
    try std.testing.expect(planForWave(11) != null);
    try std.testing.expect(planForWave(15) != null);
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

test "eqlIgnoringCr matches across CRLF/LF and rejects real differences" {
    try std.testing.expect(eqlIgnoringCr("a\nb\nc\n", "a\r\nb\r\nc\r\n"));
    try std.testing.expect(eqlIgnoringCr("abc", "abc"));
    try std.testing.expect(!eqlIgnoringCr("a\nb", "a\nc"));
    try std.testing.expect(!eqlIgnoringCr("abc", "abcd"));
}

test "verifyReferenceGolden matches the committed golden and flags a regression" {
    const allocator = std.testing.allocator;
    const scratch = "zig_q_refgold_test_scratch";
    std.fs.cwd().makePath(scratch) catch {};
    defer std.fs.cwd().deleteTree(scratch) catch {};

    const golden = try std.fs.cwd().readFileAlloc(allocator, reference_golden_path, 16 * 1024 * 1024);
    defer allocator.free(golden);

    const leaf_path = try joinPath(allocator, scratch, "v99_dst_reference_crawl_a.txt");
    defer allocator.free(leaf_path);

    // A fresh capture equal to the golden passes.
    try writeCapture(leaf_path, golden);
    const ok = try verifyReferenceGolden(allocator, scratch, "v99");
    defer allocator.free(ok);
    try std.testing.expect(std.mem.indexOf(u8, ok, "matches committed golden") != null);

    // A regressed capture must fail the gate.
    const bad = try std.fmt.allocPrint(allocator, "{s}\nREGRESSION\n", .{golden});
    defer allocator.free(bad);
    try writeCapture(leaf_path, bad);
    try std.testing.expectError(error.ReferenceCrawlRegression, verifyReferenceGolden(allocator, scratch, "v99"));
}

test "live reference_crawl output matches the committed golden" {
    // Runs the real scenario through the in-process DST harness (the same path the
    // zig-q-dst exe drives) and pins it to references/reference_crawl.txt. This is what
    // catches a silent drift of the frozen crawl during `zig build test`, instead of
    // only at gate-vNN time. The null semver override is equivalent to the exe's
    // `--semver 1.1.0`: version.transcriptSemver pins reference_crawl unconditionally.
    const dst = @import("dst.zig");
    const allocator = std.testing.allocator;

    var buf: [131072]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try dst.runNamedScenario(allocator, "reference_crawl", 42, fbs.writer(), null);
    const fresh = fbs.getWritten();
    try std.testing.expect(fresh.len > 0);

    const golden = std.fs.cwd().readFileAlloc(allocator, reference_golden_path, 16 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print(
                "missing {s}; regenerate it with `zig build update-reference-golden` and commit it\n",
                .{reference_golden_path},
            );
            return error.ReferenceGoldenMissing;
        },
        else => return err,
    };
    defer allocator.free(golden);

    if (!eqlIgnoringCr(fresh, golden)) {
        var fresh_lines = std.mem.splitScalar(u8, fresh, '\n');
        var golden_lines = std.mem.splitScalar(u8, golden, '\n');
        var line_no: usize = 1;
        while (true) : (line_no += 1) {
            const f_raw = fresh_lines.next();
            const g_raw = golden_lines.next();
            if (f_raw == null and g_raw == null) break;
            const f = std.mem.trimRight(u8, f_raw orelse "<end of output>", "\r");
            const g = std.mem.trimRight(u8, g_raw orelse "<end of golden>", "\r");
            if (!std.mem.eql(u8, f, g)) {
                std.debug.print("first difference at line {d}:\n  golden: {s}\n  fresh:  {s}\n", .{ line_no, g, f });
                break;
            }
        }
        std.debug.print(
            "reference_crawl (seed 42) no longer matches {s}.\n" ++
                "The frozen reference crawl is part of the determinism contract (see CLAUDE.md);\n" ++
                "changing it must be intentional and version-gated. If it is, regenerate the\n" ++
                "golden with `zig build update-reference-golden` and commit the result.\n",
            .{reference_golden_path},
        );
        return error.ReferenceCrawlRegression;
    }
}

test "formatV15CompletionSummary uses gate captures only" {
    const allocator = std.testing.allocator;
    const footer = "gate-v15: build_bytes=0 tests=192/192 version=1.5.3 ref_hash=abc fuzz=10000";
    const deep_floor = "step depth_report floor=2 plan_monsters=3 plan_loot=4\nstep depth_report floor=5 plan_monsters=5 plan_loot=8\n";
    const repl =
        \\> used bandage; healed 5 hp
        \\> HP: 12
    ;

    const out = try formatV15CompletionSummary(allocator, footer, deep_floor, repl);
    defer allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "192/192") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "plan_loot=4") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "plan_loot=8") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "healed 5 hp") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "heal_bandage") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "trap_floor") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "deep_floor") != null);

    try std.testing.expect(std.mem.indexOf(u8, out, "182") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "loot 4 vs 0") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "×2") == null);
}
