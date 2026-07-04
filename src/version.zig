//! Single source of truth for release identity (semver).

pub const semver: []const u8 = "0.5.0";

pub fn resolve(override: ?[]const u8) []const u8 {
    return override orelse semver;
}