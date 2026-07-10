//! Main help text with REPL vs DST v0.8 regression profiles.
const std = @import("std");

pub const Profile = enum {
    /// Legacy incomplete help (unused by REPL/DST — deleted from live paths).
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
    \\      inventory (inv), examine <item>, equip <item>, unequip <slot|item>, use <item>
    \\      look lists nearby items/corpses; stand adjacent to pick up
    \\ai:    monsters act after wait/move/get/drop/loot/use/open/close/wound when explore AI is on; ambush when they reach you
    \\
;

pub const repl_v11_golden =
    \\creation: roll, assign <6 picks>, race <1-3>, class <1-3>, spawn, stats
    \\explore:  look (l), time, move <n|s|e|w|nw|...>, m <dir>, wait, food, rest, sleep, conditions, descend, help, help gear, exit
    \\          chains: move w w   or   move w; move w
    \\gear:     get [item], get from corpse, loot (corpse first), drop <item>, inventory (inv), examine <item>, equip <item>, unequip <slot|item>, use <item>  (help gear)
    \\ai:      monsters act on wait/move/get/drop/loot/use/open/close/wound when explore AI is on; ambush seats the monster first
    \\combat:   attack [target], end turn, flee (disengage/retreat), catch breath
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
        // `.repl` is dead — redirect to the live `.repl_v11` surface so both paths match.
        .repl => try writer.writeAll(repl_v11_golden),
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

test "repl help redirects to live repl_v11 surface" {
    var buf: [768]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeMainHelp(fbs.writer(), .repl);
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "descend") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "flee") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "catch breath") != null);
    try std.testing.expectEqualStrings(repl_v11_golden, out);
}
