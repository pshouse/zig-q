//! Single source of truth for release identity (semver).
const std = @import("std");

pub const semver: []const u8 = "1.7.0";

/// Wave gate versions recorded in DST/evidence transcripts per release plan.
pub const v11: []const u8 = "1.1.0";
pub const v12: []const u8 = "1.2.0";
pub const v13: []const u8 = "1.3.0";
pub const v14: []const u8 = "1.4.0";
pub const v15: []const u8 = "1.5.3";
pub const v16: []const u8 = "1.6.0";
pub const v17: []const u8 = "1.7.0";

pub const GateConfig = struct {
    wave: u8,
    emit: []const u8,
    reference_header: []const u8,

    pub fn semverForScenario(self: GateConfig, scenario_name: []const u8) []const u8 {
        if (isFrozenReference(scenario_name)) return self.reference_header;
        return self.emit;
    }
};

/// Known shipped waves only. Unknown N returns null so callers fail loudly
/// instead of silently yielding the live semver (#37).
pub fn wave(w: u8) ?[]const u8 {
    return switch (w) {
        11 => v11,
        12 => v12,
        13 => v13,
        14 => v14,
        15 => v15,
        16 => v16,
        17 => v17,
        else => null,
    };
}

pub fn forGate(w: u8) ?GateConfig {
    const emit = wave(w) orelse return null;
    return .{
        .wave = w,
        .emit = emit,
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
    try std.testing.expectEqualStrings("1.2.0", forGate(12).?.emit);
    try std.testing.expectEqualStrings("1.1.0", forGate(14).?.reference_header);
    try std.testing.expectEqualStrings("1.6.0", forGate(16).?.emit);
    try std.testing.expectEqualStrings("1.7.0", forGate(17).?.emit);
}

test "wave and forGate reject unknown waves" {
    // #37: no silent else-fallthrough to live semver.
    try std.testing.expect(wave(99) == null);
    try std.testing.expect(forGate(99) == null);
    try std.testing.expect(wave(10) == null);
}

test "resolve defaults to shipped semver" {
    try std.testing.expectEqualStrings("1.7.0", resolve(null));
    try std.testing.expectEqualStrings("0.6.0-dev", resolve("0.6.0-dev"));
}

test "transcriptSemver pins reference_crawl unconditionally" {
    try std.testing.expectEqualStrings("1.1.0", transcriptSemver("reference_crawl", null));
    try std.testing.expectEqualStrings("1.1.0", transcriptSemver("reference_crawl", "1.4.0"));
    try std.testing.expectEqualStrings("1.2.0", transcriptSemver("loot_roundtrip", "1.2.0"));
}

test "semverForScenario pins reference_crawl header under gate" {
    const gate = forGate(14).?;
    try std.testing.expectEqualStrings("1.4.0", gate.semverForScenario("survive"));
    try std.testing.expectEqualStrings("1.1.0", gate.semverForScenario("reference_crawl"));
}

test "isFrozenReference only matches reference_crawl" {
    try std.testing.expect(isFrozenReference("reference_crawl"));
    try std.testing.expect(!isFrozenReference("reference_survive"));
}
