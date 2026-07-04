const std = @import("std");
const dice = @import("dice.zig");
const types = @import("types.zig");
const world = @import("world.zig");
const character = @import("character.zig");
const choose = @import("choose.zig");

pub const StatPool = struct {
    rolls: [6]i32,
};

pub const CreationDraft = struct {
    pool: StatPool = undefined,
    has_pool: bool = false,
    picks: [6]usize = undefined,
    has_assign: bool = false,
    race_pick: usize = 0,
    class_pick: usize = 0,
    has_race: bool = false,
    has_class: bool = false,
};

pub fn rollStatPool(w: *world.World) StatPool {
    var pool: StatPool = undefined;
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        var buf: [4]u8 = undefined;
        const result = dice.roll(&w.rng, .{ .n = 4, .sides = 6, .drop = .low }, &buf);
        pool.rolls[i] = result.sum;
    }
    return pool;
}

/// v0.2/v0.3 compatibility path: sequential assign, first race/class, no bonuses.
pub fn bootstrapCharacter(
    allocator: std.mem.Allocator,
    w: *world.World,
    name: []const u8,
) !struct { character: *types.Character, pool: StatPool } {
    const pool = rollStatPool(w);

    var attrs = try types.defaultAttributes(allocator);
    var i: usize = 0;
    while (i < attrs.items.len) : (i += 1) {
        attrs.items[i].stat = @intCast(pool.rolls[i]);
    }

    const char = try allocator.create(types.Character);
    char.* = .{
        .name = name,
        .attributes = attrs,
        .race = w.races.items[0],
        .class = types.defaultClasses()[0],
    };

    return .{ .character = char, .pool = pool };
}

pub fn draftRoll(w: *world.World, draft: *CreationDraft) StatPool {
    const pool = rollStatPool(w);
    draft.pool = pool;
    draft.has_pool = true;
    return pool;
}

pub fn draftAssign(draft: *CreationDraft, picks: [6]usize) !void {
    if (!draft.has_pool) return error.NoStatPool;
    draft.picks = picks;
    draft.has_assign = true;
}

pub fn draftChooseRace(draft: *CreationDraft, pick: usize) !void {
    if (pick < 1 or pick > 3) return error.InvalidPick;
    draft.race_pick = pick;
    draft.has_race = true;
}

pub fn draftChooseClass(draft: *CreationDraft, pick: usize) !void {
    if (pick < 1 or pick > 3) return error.InvalidPick;
    draft.class_pick = pick;
    draft.has_class = true;
}

pub fn draftBuildCharacter(
    allocator: std.mem.Allocator,
    w: *world.World,
    draft: *const CreationDraft,
    name: []const u8,
) !*types.Character {
    if (!draft.has_pool or !draft.has_assign or !draft.has_race or !draft.has_class)
        return error.IncompleteDraft;

    var attrs = try types.defaultAttributes(allocator);
    try character.assignStatPool(&attrs, draft.pool, draft.picks);

    const race_idx = try choose.pickIndex(w.races.items.len, draft.race_pick);
    const class_idx = try choose.pickIndex(types.defaultClasses().len, draft.class_pick);

    const char = try allocator.create(types.Character);
    char.* = .{
        .name = name,
        .attributes = attrs,
        .race = w.races.items[race_idx],
        .class = types.defaultClasses()[class_idx],
    };
    character.applyRaceBonuses(char);
    return char;
}

pub fn formatStatPool(pool: StatPool, writer: anytype) !void {
    try writer.print("stat_rolls:", .{});
    for (pool.rolls, 0..) |roll, idx| {
        try writer.print(" {d}={}", .{ idx + 1, roll });
    }
    try writer.print("\n", .{});
}