//! Single source of truth for release identity (semver).
const std = @import("std");

pub const semver: []const u8 = "1.5.2";

/// Wave gate versions recorded in DST/evidence transcripts per release plan.
pub const v11: []const u8 = "1.1.0";
pub const v12: []const u8 = "1.2.0";
pub const v13: []const u8 = "1.3.0";
pub const v14: []const u8 = "1.4.0";
pub const v15: []const u8 = "1.5.2";

pub const GateConfig = struct {
    wave: u8,
    emit: []const u8,
    reference_header: []const u8,

    pub fn semverForScenario(self: GateConfig, scenario_name: []const u8) []const u8 {
        if (isFrozenReference(scenario_name)) return self.reference_header;
        return self.emit;
    }
};

pub fn wave(w: u8) []const u8 {
    return switch (w) {
        11 => v11,
        12 => v12,
        13 => v13,
        14 => v14,
        15 => v15,
        else => semver,
    };
}

pub fn forGate(w: u8) GateConfig {
    return .{
        .wave = w,
        .emit = wave(w),
        .reference_header = v11,
    };
}

pub fn isFrozenReference(scenario_name: []const u8) bool {
    return std.mem.eql(u8, scenario_name, "reference_crawl");
}

pub fn resolve(override: ?[]const u8) []const u8 {
    return override orelse semver;
}

pub fn versionLine(buf: []u8, semver_text: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "# version={s}", .{semver_text});
}

/// Semver recorded in a DST/evidence transcript for `scenario_name`.
pub fn transcriptSemver(scenario_name: []const u8, cli_override: ?[]const u8) []const u8 {
    if (isFrozenReference(scenario_name)) return v11;
    return resolve(cli_override);
}

/// Semver printed by `zig build run -- --version`.
pub fn cliVersion(cli_override: ?[]const u8) []const u8 {
    return resolve(cli_override);
}

test "forGate maps wave to emit semver" {
    try std.testing.expectEqualStrings("1.2.0", forGate(12).emit);
    try std.testing.expectEqualStrings("1.1.0", forGate(14).reference_header);
}

test "resolve defaults to shipped semver" {
    try std.testing.expectEqualStrings("1.5.2", resolve(null));
    try std.testing.expectEqualStrings("0.6.0-dev", resolve("0.6.0-dev"));
}

test "transcriptSemver pins reference_crawl unconditionally" {
    try std.testing.expectEqualStrings("1.1.0", transcriptSemver("reference_crawl", null));
    try std.testing.expectEqualStrings("1.1.0", transcriptSemver("reference_crawl", "1.4.0"));
    try std.testing.expectEqualStrings("1.2.0", transcriptSemver("loot_roundtrip", "1.2.0"));
}

test "semverForScenario pins reference_crawl header under gate" {
    const gate = forGate(14);
    try std.testing.expectEqualStrings("1.4.0", gate.semverForScenario("survive"));
    try std.testing.expectEqualStrings("1.1.0", gate.semverForScenario("reference_crawl"));
}

test "isFrozenReference only matches reference_crawl" {
    try std.testing.expect(isFrozenReference("reference_crawl"));
    try std.testing.expect(!isFrozenReference("reference_survive"));
}