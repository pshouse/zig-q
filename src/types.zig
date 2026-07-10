const std = @import("std");

pub const Condition = enum {
    blinded,
    charmed,
    deafened,
    exhaustion,
    frightened,
    grappled,
    incapacitated,
    invisible,
    paralyzed,
    petrified,
    poisoned,
    prone,
    restrained,
    stunned,
    unconscious,
    dead,
    starving,
};

pub const ConditionSet = struct {
    flags: std.EnumSet(Condition),

    pub fn initEmpty() ConditionSet {
        return .{ .flags = .initEmpty() };
    }

    pub fn has(self: ConditionSet, c: Condition) bool {
        return self.flags.contains(c);
    }

    pub fn add(self: *ConditionSet, c: Condition) void {
        self.flags.insert(c);
    }
};

pub const Status = enum {
    exploring,
    fighting,
};

pub const Attribute = struct {
    name: []const u8,
    abbr: []const u8,
    stat: u64,
};

pub const Race = struct {
    name: []const u8,
    speed: u8,
    attr_bonuses: std.ArrayList(Attribute),
};

pub const Class = struct {
    name: []const u8,
    hit_die: u8,
};

pub const Character = struct {
    name: []const u8,
    attributes: std.ArrayList(Attribute),
    race: Race,
    class: Class,
    status: Status = .exploring,
};

pub fn defaultAttributes(allocator: std.mem.Allocator) !std.ArrayList(Attribute) {
    var list: std.ArrayList(Attribute) = .empty;
    try list.append(allocator, .{ .name = "strength", .abbr = "STR", .stat = 0 });
    try list.append(allocator, .{ .name = "dexterity", .abbr = "DEX", .stat = 0 });
    try list.append(allocator, .{ .name = "constitution", .abbr = "CON", .stat = 0 });
    try list.append(allocator, .{ .name = "intelligence", .abbr = "INT", .stat = 0 });
    try list.append(allocator, .{ .name = "wisdom", .abbr = "WIS", .stat = 0 });
    try list.append(allocator, .{ .name = "charisma", .abbr = "CHA", .stat = 0 });
    return list;
}

pub fn defaultRaces(allocator: std.mem.Allocator) !std.ArrayList(Race) {
    var list: std.ArrayList(Race) = .empty;

    // #32 option C: INT/CHA are cosmetic; move dragonborn's +2 onto a live stat
    // (STR — attack/damage/carry) instead of dead CHA. See docs/INT_CHA_DECISION.md.
    var drb_bonuses: std.ArrayList(Attribute) = .empty;
    try drb_bonuses.append(allocator, .{ .name = "strength_bonus", .abbr = "STR", .stat = 2 });
    try list.append(allocator, .{ .name = "dragonborn", .speed = 30, .attr_bonuses = drb_bonuses });

    var dwf_bonuses: std.ArrayList(Attribute) = .empty;
    try dwf_bonuses.append(allocator, .{ .name = "constitution_bonus", .abbr = "CON", .stat = 2 });
    try list.append(allocator, .{ .name = "dwarf", .speed = 25, .attr_bonuses = dwf_bonuses });

    var elf_bonuses: std.ArrayList(Attribute) = .empty;
    try elf_bonuses.append(allocator, .{ .name = "dexterity_bonus", .abbr = "DEX", .stat = 2 });
    try list.append(allocator, .{ .name = "elf", .speed = 30, .attr_bonuses = elf_bonuses });

    return list;
}

pub fn defaultClasses() [3]Class {
    return .{
        .{ .name = "barbarian", .hit_die = 12 },
        .{ .name = "fighter", .hit_die = 10 },
        .{ .name = "bard", .hit_die = 8 },
    };
}

pub fn deinitRaceList(allocator: std.mem.Allocator, races: *std.ArrayList(Race)) void {
    for (races.items) |*race| race.attr_bonuses.deinit(allocator);
    races.deinit(allocator);
}