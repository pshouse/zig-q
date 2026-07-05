const std = @import("std");
const dst = @import("dst.zig");

pub fn freeScenario(allocator: std.mem.Allocator, scenario: dst.Scenario) void {
    allocator.free(scenario.name);
    for (scenario.steps) |step| {
        switch (step) {
            .creation_finish => |name| allocator.free(name),
            .command => |cmd| allocator.free(cmd),
            .spawn => |s| allocator.free(s.name),
            else => {},
        }
    }
    allocator.free(scenario.steps);
}

fn stripBom(text: []const u8) []const u8 {
    if (text.len >= 3 and text[0] == 0xEF and text[1] == 0xBB and text[2] == 0xBF) {
        return text[3..];
    }
    return text;
}

pub fn loadScenario(allocator: std.mem.Allocator, path: []const u8, seed: u64) !dst.Scenario {
    const raw_text = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    errdefer allocator.free(raw_text);
    const text = stripBom(raw_text);

    var owned_name: ?[]u8 = null;
    var file_seed: u64 = seed;
    var steps: std.ArrayList(dst.Step) = .empty;
    errdefer {
        for (steps.items) |step| {
            switch (step) {
                .creation_finish => |n| allocator.free(n),
                .command => |cmd| allocator.free(cmd),
                .spawn => |s| allocator.free(s.name),
                else => {},
            }
        }
        steps.deinit(allocator);
    }

    var lines = std.mem.splitAny(u8, text, "\r\n");
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "#")) {
            if (std.mem.startsWith(u8, line, "# name=")) {
                if (owned_name) |old| allocator.free(old);
                owned_name = try allocator.dupe(u8, line["# name=".len..]);
            }
            if (std.mem.startsWith(u8, line, "# seed=")) {
                file_seed = try std.fmt.parseInt(u64, line["# seed=".len..], 10);
            }
            continue;
        }
        try steps.append(allocator, try parseStep(allocator, line));
    }

    const final_name = owned_name orelse try allocator.dupe(u8, "file");
    const owned_steps = try steps.toOwnedSlice(allocator);
    allocator.free(raw_text);

    return .{
        .name = final_name,
        .seed = file_seed,
        .steps = owned_steps,
    };
}

fn parseStep(allocator: std.mem.Allocator, line: []const u8) !dst.Step {
    if (std.mem.eql(u8, line, "roll_stats")) return .roll_stats;
    if (std.mem.eql(u8, line, "creation_roll")) return .creation_roll;
    if (std.mem.eql(u8, line, "time")) return .time;
    if (std.mem.eql(u8, line, "look")) return .look;

    if (std.mem.startsWith(u8, line, "load_floor ")) {
        const arg = std.mem.trim(u8, line["load_floor ".len..], " \t");
        return .{ .load_floor = try std.fmt.parseInt(u32, arg, 10) };
    }
    if (std.mem.startsWith(u8, line, "assign_stats ")) {
        return .{ .assign_stats = try parseSixPicks(line["assign_stats ".len..]) };
    }
    if (std.mem.startsWith(u8, line, "choose_race ")) {
        const arg = std.mem.trim(u8, line["choose_race ".len..], " \t");
        return .{ .choose_race = try std.fmt.parseInt(usize, arg, 10) };
    }
    if (std.mem.startsWith(u8, line, "choose_class ")) {
        const arg = std.mem.trim(u8, line["choose_class ".len..], " \t");
        return .{ .choose_class = try std.fmt.parseInt(usize, arg, 10) };
    }
    if (std.mem.startsWith(u8, line, "creation_finish ")) {
        const arg = std.mem.trim(u8, line["creation_finish ".len..], " \t");
        return .{ .creation_finish = try allocator.dupe(u8, arg) };
    }
    if (std.mem.startsWith(u8, line, "command ")) {
        const arg = std.mem.trim(u8, line["command ".len..], " \t");
        return .{ .command = try allocator.dupe(u8, arg) };
    }
    if (std.mem.startsWith(u8, line, "spawn ")) {
        var iter = std.mem.splitScalar(u8, line["spawn ".len..], ' ');
        const name = iter.next() orelse return error.InvalidScenarioLine;
        const x = try std.fmt.parseInt(u64, iter.next() orelse return error.InvalidScenarioLine, 10);
        const y = try std.fmt.parseInt(u64, iter.next() orelse return error.InvalidScenarioLine, 10);
        return .{ .spawn = .{
            .name = try allocator.dupe(u8, name),
            .x = x,
            .y = y,
        } };
    }
    return error.InvalidScenarioLine;
}

fn parseSixPicks(tail: []const u8) ![6]usize {
    var iter = std.mem.splitScalar(u8, tail, ' ');
    var picks: [6]usize = undefined;
    for (&picks) |*pick| {
        const tok = iter.next() orelse return error.InvalidScenarioLine;
        pick.* = try std.fmt.parseInt(usize, tok, 10);
    }
    return picks;
}

test "runScenarioFile executes descend_crawl steps" {
    const allocator = std.testing.allocator;
    var buf: [65536]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try dst.runScenarioFile(allocator, "scenarios/descend_crawl.txt", 42, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "descended to floor 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "look floor=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "creation_finish name=George") != null);
}