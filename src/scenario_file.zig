const std = @import("std");
const dst = @import("dst.zig");

pub fn loadScenario(allocator: std.mem.Allocator, path: []const u8, seed: u64) !dst.Scenario {
    const text = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    errdefer allocator.free(text);

    var name: []const u8 = "file";
    var file_seed: u64 = seed;
    var steps: std.ArrayList(dst.Step) = .empty;
    errdefer steps.deinit(allocator);

    var lines = std.mem.splitAny(u8, text, "\r\n");
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "#")) {
            if (std.mem.startsWith(u8, line, "# name=")) name = line["# name=".len..];
            if (std.mem.startsWith(u8, line, "# seed=")) file_seed = try std.fmt.parseInt(u64, line["# seed=".len..], 10);
            continue;
        }
        try steps.append(allocator, try parseStep(line));
    }

    const owned_name = try allocator.dupe(u8, name);
    const owned_steps = try steps.toOwnedSlice(allocator);
    allocator.free(text);

    return .{
        .name = owned_name,
        .seed = file_seed,
        .steps = owned_steps,
    };
}

fn parseStep(line: []const u8) !dst.Step {
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
        return .{ .creation_finish = arg };
    }
    if (std.mem.startsWith(u8, line, "command ")) {
        return .{ .command = std.mem.trim(u8, line["command ".len..], " \t") };
    }
    if (std.mem.startsWith(u8, line, "spawn ")) {
        var iter = std.mem.splitScalar(u8, line["spawn ".len..], ' ');
        const name = iter.next() orelse return error.InvalidScenarioLine;
        const x = try std.fmt.parseInt(u64, iter.next() orelse return error.InvalidScenarioLine, 10);
        const y = try std.fmt.parseInt(u64, iter.next() orelse return error.InvalidScenarioLine, 10);
        return .{ .spawn = .{ .name = name, .x = x, .y = y } };
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

test "loadScenario parses command steps" {
    const allocator = std.testing.allocator;
    const path = "scenarios/descend_crawl.txt";
    const scenario = try loadScenario(allocator, path, 42);
    defer allocator.free(@constCast(scenario.name));
    defer allocator.free(@constCast(scenario.steps));
    try std.testing.expectEqual(@as(u64, 42), scenario.seed);
    try std.testing.expect(scenario.steps.len > 0);
}