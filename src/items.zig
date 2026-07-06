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
            .proficient_classes = &.{"fighter"},
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

pub fn idTag(id: Id) []const u8 {
    return @tagName(id);
}

test "parse short sword aliases" {
    try std.testing.expectEqual(Id.short_sword, parseId("short_sword").?);
    try std.testing.expectEqual(Id.short_sword, parseId("short sword").?);
}