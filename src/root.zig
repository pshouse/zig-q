//! Library root: re-exports modules and aggregates unit tests.

const std = @import("std");

pub const rng = @import("rng.zig");
pub const dice = @import("dice.zig");
pub const types = @import("types.zig");
pub const loc = @import("loc.zig");
pub const clock = @import("clock.zig");
pub const entity = @import("entity.zig");
pub const map = @import("map.zig");
pub const world = @import("world.zig");
pub const map_render = @import("map_render.zig");
pub const session = @import("session.zig");
pub const demo = @import("demo.zig");
pub const dst = @import("dst.zig");

test {
    std.testing.refAllDecls(@This());
    _ = @import("rng.zig");
    _ = @import("dice.zig");
    _ = @import("types.zig");
    _ = @import("loc.zig");
    _ = @import("clock.zig");
    _ = @import("entity.zig");
    _ = @import("map.zig");
    _ = @import("world.zig");
    _ = @import("map_render.zig");
    _ = @import("session.zig");
    _ = @import("demo.zig");
    _ = @import("dst.zig");
}