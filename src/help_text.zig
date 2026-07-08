//! Main help text with REPL vs DST v0.8 regression profiles.
const std = @import("std");

pub const Profile = enum {
    repl,
    repl_v11,
    dst_v08,
};

/// Byte-identical to v0.8 playthrough golden `help` output (no trailing newline).
pub const dst_v08_golden =
    \\creation: roll, assign <6 picks>, race <1-3>, class <1-3>, spawn, stats
    \\explore:  look (l), time, move <n|s|e|w|nw|...>, m <dir>, help, exit
    \\          chains: move w w   or   move w; move w
    \\combat:   attack [target], end turn
    \\persist:  save [slot], load <slot>
    \\
    \\example: assign 6 5 4 3 2 1
    \\         race 2
    \\         class 1
    \\         spawn
    \\
;

pub const gear_golden =
    \\gear: get [item], get from corpse, loot (corpse first), drop <item>
    \\      inventory (inv), examine <item>, equip <item>, use <item>
    \\      look lists nearby items/corpses; stand adjacent to pick up
    \\ai:    monsters act after wait/move on floor 2+; ambush when they reach you
    \\
;

pub const repl_v11_golden =
    \\creation: roll, assign <6 picks>, race <1-3>, class <1-3>, spawn, stats
    \\explore:  look (l), time, move <n|s|e|w|nw|...>, m <dir>, wait, food, rest, sleep, conditions, descend, help, help gear, exit
    \\          chains: move w w   or   move w; move w
    \\gear:     get [item], get from corpse, loot (corpse first), drop <item>, inventory (inv), examine <item>, equip <item>, use <item>  (help gear)
    \\ai:      monsters act on wait/move (floor 2+); ambush when they step adjacent
    \\combat:   attack [target], end turn
    \\persist:  save [slot], load <slot>
    \\
    \\example: assign 6 5 4 3 2 1
    \\         race 2
    \\         class 1
    \\         spawn
    \\
;

pub fn writeGearHelp(writer: anytype) !void {
    try writer.writeAll(gear_golden);
}

pub fn writeMainHelp(writer: anytype, profile: Profile) !void {
    switch (profile) {
        .dst_v08 => try writer.writeAll(dst_v08_golden),
        .repl_v11 => try writer.writeAll(repl_v11_golden),
        .repl => try writer.print(
            \\creation: roll, assign <6 picks>, race <1-3>, class <1-3>, spawn, stats
            \\explore:  look (l), time, move <n|s|e|w|nw|...>, m <dir>, descend, help, help gear, exit
            \\          chains: move w w   or   move w; move w
            \\gear:     get [item], get from corpse, loot (corpse first), drop <item>, inventory (inv), examine <item>, equip <item>, use <item>  (help gear)
            \\ai:      monsters act on wait/move (floor 2+); ambush when they step adjacent
            \\combat:   attack [target], end turn
            \\persist:  save [slot], load <slot>
            \\
            \\example: assign 6 5 4 3 2 1
            \\         race 2
            \\         class 1
            \\         spawn
            \\
        , .{}),
    }
}

test "dst_v08 help matches v0.8 golden substring" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeMainHelp(fbs.writer(), .dst_v08);
    try std.testing.expectEqualStrings(dst_v08_golden, fbs.getWritten());
}

test "repl_v11 help lists wait and conditions" {
    var buf: [768]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeMainHelp(fbs.writer(), .repl_v11);
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "wait") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "conditions") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "descend") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "get from corpse") != null);
}

test "repl help lists descend on explore line" {
    var buf: [768]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeMainHelp(fbs.writer(), .repl);
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "descend") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "explore:") != null);
}