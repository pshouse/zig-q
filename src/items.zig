//! Mundane item catalog (no magic).
const std = @import("std");

pub const Id = enum {
    short_sword,
    leather_armour,
    wooden_shield,
    antidote,
    bandage,
    rations,
    iron_key,
};

pub const Category = enum {
    weapon,
    armour,
    shield,
    consumable,
};

/// Flat HP restored by `use bandage` when wounded (explore only).
pub const bandage_heal: u16 = 5;

pub const Trait = enum {
    none,
    trip,
};

pub const Def = struct {
    id: Id,
    name: []const u8,
    weight: u8,
    category: Category,
    damage_die: u8 = 0,
    ac_bonus: u8 = 0,
    trait: Trait = .none,
    is_food: bool = false,
    food_restore: u16 = 0,
    /// Empty means all classes proficient.
    proficient_classes: []const []const u8 = &.{},
};

pub fn def(id: Id) Def {
    return switch (id) {
        .short_sword => .{
            .id = id,
            .name = "short sword",
            .weight = 2,
            .category = .weapon,
            .damage_die = 6,
            .trait = .trip,
        },
        .leather_armour => .{
            .id = id,
            .name = "leather armour",
            .weight = 10,
            .category = .armour,
            .ac_bonus = 11,
            .proficient_classes = &.{"fighter", "barbarian"},
        },
        .wooden_shield => .{
            .id = id,
            .name = "wooden shield",
            .weight = 6,
            .category = .shield,
            .ac_bonus = 2,
        },
        .antidote => .{
            .id = id,
            .name = "antidote",
            .weight = 1,
            .category = .consumable,
        },
        .bandage => .{
            .id = id,
            .name = "bandage",
            .weight = 1,
            .category = .consumable,
        },
        .rations => .{
            .id = id,
            .name = "rations",
            .weight = 1,
            .category = .consumable,
            .is_food = true,
            .food_restore = 50,
        },
        .iron_key => .{
            .id = id,
            .name = "iron key",
            .weight = 1,
            .category = .consumable,
        },
    };
}

pub fn parseId(name: []const u8) ?Id {
    inline for (std.meta.fields(Id)) |field| {
        const id = @field(Id, field.name);
        const d = def(id);
        if (std.mem.eql(u8, name, field.name)) return id;
        if (std.mem.eql(u8, name, d.name)) return id;
    }
    return null;
}

pub fn parseCategory(name: []const u8) ?Category {
    if (std.mem.eql(u8, name, "weapon")) return .weapon;
    if (std.mem.eql(u8, name, "armour") or std.mem.eql(u8, name, "armor")) return .armour;
    if (std.mem.eql(u8, name, "shield")) return .shield;
    if (std.mem.eql(u8, name, "consumable")) return .consumable;
    return null;
}

pub fn categoryLabel(cat: Category) []const u8 {
    return switch (cat) {
        .weapon => "weapon",
        .armour => "armour",
        .shield => "shield",
        .consumable => "consumable",
    };
}

pub fn printProficiencyHint(d: Def, player_class: []const u8, writer: anytype) !void {
    if (d.proficient_classes.len == 0) return;
    try writer.print(" (", .{});
    for (d.proficient_classes, 0..) |class_name, i| {
        if (i > 0) {
            if (i == d.proficient_classes.len - 1) {
                try writer.print(" or ", .{});
            } else {
                try writer.print(", ", .{});
            }
        }
        try writer.print("{s}", .{class_name});
    }
    try writer.print(" only; you are {s})", .{player_class});
}

pub fn idTag(id: Id) []const u8 {
    return @tagName(id);
}

test "parse short sword aliases" {
    try std.testing.expectEqual(Id.short_sword, parseId("short_sword").?);
    try std.testing.expectEqual(Id.short_sword, parseId("short sword").?);
}

test "parse category aliases" {
    try std.testing.expectEqual(Category.armour, parseCategory("armour").?);
    try std.testing.expectEqual(Category.armour, parseCategory("armor").?);
    try std.testing.expectEqual(Category.weapon, parseCategory("weapon").?);
    try std.testing.expectEqual(Category.shield, parseCategory("shield").?);
}