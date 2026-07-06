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

pub const repl_v11_golden =
    \\creation: roll, assign <6 picks>, race <1-3>, class <1-3>, spawn, stats
    \\explore:  look (l), time, move <n|s|e|w|nw|...>, m <dir>, wait, food, rest, sleep, conditions, descend, help, exit
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

pub fn writeMainHelp(writer: anytype, profile: Profile) !void {
    switch (profile) {
        .dst_v08 => try writer.writeAll(dst_v08_golden),
        .repl_v11 => try writer.writeAll(repl_v11_golden),
        .repl => try writer.print(
            \\creation: roll, assign <6 picks>, race <1-3>, class <1-3>, spawn, stats
            \\explore:  look (l), time, move <n|s|e|w|nw|...>, m <dir>, descend, help, exit
            \\          chains: move w w   or   move w; move w
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
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeMainHelp(fbs.writer(), .repl_v11);
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "wait") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "conditions") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "descend") != null);
}

test "repl help lists descend on explore line" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeMainHelp(fbs.writer(), .repl);
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "descend") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "explore:") != null);
}