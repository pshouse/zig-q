//! Library root: re-exports modules and aggregates unit tests.

const std = @import("std");

pub const rng = @import("rng.zig");
pub const dice = @import("dice.zig");
pub const types = @import("types.zig");
pub const loc = @import("loc.zig");
pub const clock = @import("clock.zig");
pub const entity = @import("entity.zig");
pub const map = @import("map.zig");
pub const terrain = @import("terrain.zig");
pub const dungeon = @import("dungeon.zig");
pub const world = @import("world.zig");
pub const movement = @import("movement.zig");
pub const commands = @import("commands.zig");
pub const map_render = @import("map_render.zig");
pub const session = @import("session.zig");
pub const character = @import("character.zig");
pub const monsters = @import("monsters.zig");
pub const combat = @import("combat.zig");
pub const choose = @import("choose.zig");
pub const demo = @import("demo.zig");
pub const repl = @import("repl.zig");
pub const transcript = @import("transcript.zig");
pub const fuzz = @import("fuzz.zig");
pub const version = @import("version.zig");
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
    _ = @import("terrain.zig");
    _ = @import("dungeon.zig");
    _ = @import("world.zig");
    _ = @import("movement.zig");
    _ = @import("commands.zig");
    _ = @import("map_render.zig");
    _ = @import("session.zig");
    _ = @import("character.zig");
    _ = @import("monsters.zig");
    _ = @import("combat.zig");
    _ = @import("choose.zig");
    _ = @import("demo.zig");
    _ = @import("repl.zig");
    _ = @import("transcript.zig");
    _ = @import("fuzz.zig");
    _ = @import("version.zig");
    _ = @import("dst.zig");
}