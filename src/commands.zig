const std = @import("std");
const world = @import("world.zig");
const entity = @import("entity.zig");
const loc = @import("loc.zig");
const movement = @import("movement.zig");
const map_render = @import("map_render.zig");
const session = @import("session.zig");
const character = @import("character.zig");
const combat = @import("combat.zig");
const save_state = @import("save_state.zig");
const sqlite_store = @import("sqlite_store.zig");
const help_text = @import("help_text.zig");
const dungeon = @import("dungeon.zig");
const evidence_format = @import("evidence_format.zig");
const conditions = @import("conditions.zig");
const explore = @import("explore.zig");
const items = @import("items.zig");
const inventory = @import("inventory.zig");
const world_objects = @import("world_objects.zig");
const survival = @import("survival.zig");

/// Target for the `get`/`loot` command family. All of `get`, `loot`,
/// `get from corpse`, and `loot X` funnel through one command with this payload.
pub const GetTarget = struct {
    /// Named target: an item id/category token, or the literal `"corpse"` for
    /// the adjacent corpse's loot. `null` means "nearest nearby object".
    name: ?[]const u8 = null,
    /// When picking the nearest object (`name == null`), prefer an adjacent
    /// corpse's loot before a floor item. Set by the bare `loot` verb; bare
    /// `get` leaves it false and takes whichever object is nearest in order.
    prefer_corpse: bool = false,
};

pub const Command = union(enum) {
    look,
    time,
    move: movement.Direction,
    help,
    exit,
    roll,
    assign: [6]usize,
    assign_usage,
    race: usize,
    race_usage,
    class: usize,
    class_usage,
    spawn,
    stats,
    attack,
    attack_target: []const u8,
    end_turn,
    flee,
    catch_breath,
    descend,
    save,
    save_slot: u32,
    save_usage,
    load_slot: u32,
    load_usage,
    help_descend,
    help_gear,
    wait,
    conditions_cmd,
    inventory_cmd,
    get_item: GetTarget,
    drop_item: []const u8,
    examine_item: []const u8,
    equip_item: []const u8,
    equip_usage,
    food,
    food_item: []const u8,
    rest,
    sleep,
    open_dir: movement.Direction,
    close_dir: movement.Direction,
    use_item: []const u8,
    wound,
    unknown: []const u8,
};

pub const Result = union(enum) {
    continue_repl,
    exit_repl,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    w: *world.World,
    draft: *session.CreationDraft,
    player_id: entity.EntityId = entity.invalid_id,
    save_path: []const u8 = sqlite_store.default_path,
    help_profile: help_text.Profile = .repl_v11,
    look_list_nearby: bool = true,
    /// Enables debug/playtest-only commands (e.g. `wound`). Off in the shipped REPL;
    /// the release gate turns it on via `--repl --playtest` for bandage-heal capture.
    playtest: bool = false,
};

pub fn parseLine(line: []const u8) Command {
    var trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return .help;

    if (std.mem.eql(u8, trimmed, "look")) return .look;
    if (std.mem.eql(u8, trimmed, "time")) return .time;
    if (std.mem.eql(u8, trimmed, "help")) return .help;
    if (std.mem.eql(u8, trimmed, "help descend")) return .help_descend;
    if (std.mem.eql(u8, trimmed, "help gear")) return .help_gear;
    if (std.mem.eql(u8, trimmed, "exit")) return .exit;
    if (std.mem.eql(u8, trimmed, "roll")) return .roll;
    if (std.mem.eql(u8, trimmed, "spawn")) return .spawn;
    if (std.mem.eql(u8, trimmed, "stats")) return .stats;
    if (std.mem.eql(u8, trimmed, "attack")) return .attack;
    if (std.mem.eql(u8, trimmed, "end turn")) return .end_turn;
    if (std.mem.eql(u8, trimmed, "flee")) return .flee;
    if (std.mem.eql(u8, trimmed, "disengage")) return .flee;
    if (std.mem.eql(u8, trimmed, "retreat")) return .flee;
    if (std.mem.eql(u8, trimmed, "catch breath")) return .catch_breath;
    if (std.mem.eql(u8, trimmed, "recover")) return .catch_breath;
    if (std.mem.eql(u8, trimmed, "descend")) return .descend;
    if (std.mem.eql(u8, trimmed, "wait")) return .wait;
    if (std.mem.eql(u8, trimmed, "food")) return .food;
    if (std.mem.eql(u8, trimmed, "rest")) return .rest;
    if (std.mem.eql(u8, trimmed, "sleep")) return .sleep;
    if (std.mem.eql(u8, trimmed, "conditions")) return .conditions_cmd;
    if (std.mem.eql(u8, trimmed, "inventory")) return .inventory_cmd;
    if (std.mem.eql(u8, trimmed, "inv")) return .inventory_cmd;
    if (std.mem.eql(u8, trimmed, "get")) return .{ .get_item = .{} };
    if (std.mem.eql(u8, trimmed, "get from corpse")) return .{ .get_item = .{ .name = "corpse" } };
    if (std.mem.eql(u8, trimmed, "loot")) return .{ .get_item = .{ .prefer_corpse = true } };
    if (std.mem.eql(u8, trimmed, "loot from corpse")) return .{ .get_item = .{ .name = "corpse" } };
    if (std.mem.startsWith(u8, trimmed, "loot ")) {
        const arg = std.mem.trim(u8, trimmed[5..], " \t");
        if (arg.len > 0) return .{ .get_item = .{ .name = arg } };
    }
    if (std.mem.startsWith(u8, trimmed, "get ")) {
        const arg = std.mem.trim(u8, trimmed[4..], " \t");
        if (arg.len > 0) return .{ .get_item = .{ .name = arg } };
    }
    if (std.mem.startsWith(u8, trimmed, "drop ")) {
        const arg = std.mem.trim(u8, trimmed[5..], " \t");
        if (arg.len > 0) return .{ .drop_item = arg };
    }
    if (std.mem.startsWith(u8, trimmed, "examine ")) {
        const arg = std.mem.trim(u8, trimmed[8..], " \t");
        if (arg.len > 0) return .{ .examine_item = arg };
    }
    if (std.mem.eql(u8, trimmed, "equip")) return .equip_usage;
    if (std.mem.startsWith(u8, trimmed, "equip ")) {
        const arg = std.mem.trim(u8, trimmed[6..], " \t");
        if (arg.len > 0) return .{ .equip_item = arg };
    }
    if (std.mem.startsWith(u8, trimmed, "eat ")) {
        const arg = std.mem.trim(u8, trimmed[4..], " \t");
        if (arg.len > 0) return .{ .food_item = arg };
    }
    if (std.mem.startsWith(u8, trimmed, "food ")) {
        const arg = std.mem.trim(u8, trimmed[5..], " \t");
        if (arg.len > 0) return .{ .food_item = arg };
    }
    if (std.mem.eql(u8, trimmed, "save")) return .save;

    if (std.mem.startsWith(u8, trimmed, "save ")) {
        const arg = std.mem.trim(u8, trimmed[5..], " \t");
        if (arg.len == 0) return .save;
        if (std.fmt.parseInt(u32, arg, 10) catch null) |slot| return .{ .save_slot = slot };
        return .save_usage;
    }

    if (std.mem.eql(u8, trimmed, "load")) return .load_usage;

    if (std.mem.startsWith(u8, trimmed, "load ")) {
        const arg = std.mem.trim(u8, trimmed[5..], " \t");
        if (arg.len == 0) return .load_usage;
        if (std.fmt.parseInt(u32, arg, 10) catch null) |slot| return .{ .load_slot = slot };
        return .load_usage;
    }

    if (std.mem.startsWith(u8, trimmed, "attack ")) {
        const arg = std.mem.trim(u8, trimmed[7..], " \t");
        if (arg.len > 0) return .{ .attack_target = arg };
    }

    if (std.mem.startsWith(u8, trimmed, "move ")) {
        const arg = std.mem.trim(u8, trimmed[5..], " \t");
        if (movement.Direction.parse(arg)) |dir| return .{ .move = dir };
    }

    if (std.mem.startsWith(u8, trimmed, "open ")) {
        const arg = std.mem.trim(u8, trimmed[5..], " \t");
        if (movement.Direction.parse(arg)) |dir| return .{ .open_dir = dir };
    }
    if (std.mem.startsWith(u8, trimmed, "close ")) {
        const arg = std.mem.trim(u8, trimmed[6..], " \t");
        if (movement.Direction.parse(arg)) |dir| return .{ .close_dir = dir };
    }
    if (std.mem.startsWith(u8, trimmed, "use ")) {
        const arg = std.mem.trim(u8, trimmed[4..], " \t");
        if (arg.len > 0) return .{ .use_item = arg };
    }
    if (std.mem.eql(u8, trimmed, "wound")) return .wound;

    if (std.mem.eql(u8, trimmed, "assign")) return .assign_usage;
    if (std.mem.startsWith(u8, trimmed, "assign ")) {
        if (parseSixPicks("assign ", trimmed)) |picks| return .{ .assign = picks };
        return .assign_usage;
    }

    if (std.mem.eql(u8, trimmed, "race")) return .race_usage;
    if (std.mem.startsWith(u8, trimmed, "race ")) {
        if (parseOnePick("race ", trimmed)) |pick| return .{ .race = pick };
        return .race_usage;
    }

    if (std.mem.eql(u8, trimmed, "class")) return .class_usage;
    if (std.mem.startsWith(u8, trimmed, "class ")) {
        if (parseOnePick("class ", trimmed)) |pick| return .{ .class = pick };
        return .class_usage;
    }

    return .{ .unknown = trimmed };
}

fn parseSixPicks(prefix: []const u8, trimmed: []const u8) ?[6]usize {
    if (!std.mem.startsWith(u8, trimmed, prefix)) return null;
    var iter = std.mem.splitScalar(u8, trimmed[prefix.len..], ' ');
    var picks: [6]usize = undefined;
    for (&picks) |*pick| {
        const tok = iter.next() orelse return null;
        const t = std.mem.trim(u8, tok, " \t");
        if (t.len == 0) return null;
        pick.* = std.fmt.parseInt(usize, t, 10) catch return null;
    }
    return picks;
}

fn parseOnePick(prefix: []const u8, trimmed: []const u8) ?usize {
    if (!std.mem.startsWith(u8, trimmed, prefix)) return null;
    const arg = std.mem.trim(u8, trimmed[prefix.len..], " \t");
    if (arg.len == 0) return null;
    return std.fmt.parseInt(usize, arg, 10) catch null;
}

fn tileNearPlayer(w: *world.World, player_id: entity.EntityId, x: u64, y: u64) bool {
    const player = w.store.get(player_id) orelse return false;
    const dx = @as(i64, @intCast(player.loc.x)) - @as(i64, @intCast(x));
    const dy = @as(i64, @intCast(player.loc.y)) - @as(i64, @intCast(y));
    const adx: u64 = @intCast(if (dx < 0) -dx else dx);
    const ady: u64 = @intCast(if (dy < 0) -dy else dy);
    return adx + ady <= 1;
}

fn cmdInventory(ctx: *Context, writer: anytype) !Result {
    const ent = ctx.w.store.get(ctx.player_id) orelse {
        try writer.print("no player spawned\n", .{});
        return .continue_repl;
    };
    try ent.inventory.format(writer);
    return .continue_repl;
}

fn cmdGet(ctx: *Context, target: GetTarget, writer: anytype) !Result {
    if (combat.isInCombat(ctx.w)) {
        try writer.print("cannot loot during combat\n", .{});
        return .continue_repl;
    }
    const ent = ctx.w.store.get(ctx.player_id) orelse {
        try writer.print("no player spawned\n", .{});
        return .continue_repl;
    };
    var picked: ?items.Id = null;
    var remove_pos: ?loc.Loc = null;
    var picked_from_corpse = false;
    var corpse_label: ?[]const u8 = null;
    var empty_corpse_near = false;

    if (target.name) |n| {
        if (std.mem.eql(u8, n, "corpse")) {
            for (ctx.w.floor_objects.objects.items) |*obj| {
                if (obj.kind != .corpse) continue;
                if (!tileNearPlayer(ctx.w, ctx.player_id, obj.x, obj.y)) continue;
                if (obj.item) |loot| {
                    picked = loot;
                    remove_pos = loc.Loc.init(obj.x, obj.y);
                    picked_from_corpse = true;
                    corpse_label = obj.label;
                    break;
                }
                empty_corpse_near = true;
            }
        } else if (items.parseId(n)) |id| {
            for (ctx.w.floor_objects.objects.items) |*obj| {
                if (obj.kind != .item and obj.kind != .corpse) continue;
                if (obj.item != id) continue;
                if (!tileNearPlayer(ctx.w, ctx.player_id, obj.x, obj.y)) continue;
                picked = id;
                remove_pos = loc.Loc.init(obj.x, obj.y);
                if (obj.kind == .corpse) {
                    picked_from_corpse = true;
                    corpse_label = obj.label;
                }
                break;
            }
        }
    } else {
        // Bare `loot` prefers an adjacent corpse's gear (the interesting loot)
        // before falling back to a floor item; bare `get` skips this pass and
        // takes whichever nearby object comes first in object order.
        if (target.prefer_corpse) {
            for (ctx.w.floor_objects.objects.items) |*obj| {
                if (obj.kind != .corpse) continue;
                if (!tileNearPlayer(ctx.w, ctx.player_id, obj.x, obj.y)) continue;
                if (obj.item) |loot| {
                    picked = loot;
                    remove_pos = loc.Loc.init(obj.x, obj.y);
                    picked_from_corpse = true;
                    corpse_label = obj.label;
                    break;
                }
                empty_corpse_near = true;
            }
        }
        if (picked == null) {
            for (ctx.w.floor_objects.objects.items) |*obj| {
                if (obj.kind != .item and obj.kind != .corpse) continue;
                if (!tileNearPlayer(ctx.w, ctx.player_id, obj.x, obj.y)) continue;
                if (obj.item) |loot| {
                    picked = loot;
                    remove_pos = loc.Loc.init(obj.x, obj.y);
                    if (obj.kind == .corpse) {
                        picked_from_corpse = true;
                        corpse_label = obj.label;
                    }
                    break;
                }
                if (obj.kind == .corpse) empty_corpse_near = true;
            }
        }
    }

    if (picked == null) {
        if (empty_corpse_near) {
            try writer.print("corpse is empty\n", .{});
        } else {
            try writer.print("nothing to pick up here\n", .{});
        }
        return .continue_repl;
    }
    try ent.inventory.add(ctx.allocator, picked.?, 1);
    if (remove_pos) |pos| {
        if (ctx.w.floor_objects.at(pos)) |obj| {
            if (obj.kind == .corpse) {
                obj.item = null;
            } else {
                ctx.w.floor_objects.removeAt(ctx.allocator, pos);
            }
        }
    }
    const d = items.def(picked.?);
    if (picked_from_corpse and corpse_label != null) {
        try writer.print("picked up {s} from {s}\n", .{ d.name, corpse_label.? });
    } else {
        try writer.print("picked up {s}\n", .{d.name});
    }
    try tickPlayerAction(ctx, 1, writer);
    try finishExploreAction(ctx, writer);
    return .continue_repl;
}

fn printItemExamine(id: items.Id, writer: anytype) !void {
    const d = items.def(id);
    try writer.print("{s}: weight={} category={s}", .{ d.name, d.weight, @tagName(d.category) });
    if (d.damage_die > 0) try writer.print(" damage=d{}", .{d.damage_die});
    if (d.ac_bonus > 0) try writer.print(" ac_bonus={}", .{d.ac_bonus});
    if (d.trait != .none) try writer.print(" trait={s}", .{@tagName(d.trait)});
    try writer.print("\n", .{});
}

fn countNearbyFloorCategory(ctx: *Context, cat: items.Category) usize {
    var count: usize = 0;
    for (ctx.w.floor_objects.objects.items) |obj| {
        if (!tileNearPlayer(ctx.w, ctx.player_id, obj.x, obj.y)) continue;
        const id = obj.item orelse continue;
        if (items.def(id).category == cat) count += 1;
    }
    return count;
}

fn findNearbyFloorCategory(ctx: *Context, cat: items.Category) ?items.Id {
    if (countNearbyFloorCategory(ctx, cat) != 1) return null;
    for (ctx.w.floor_objects.objects.items) |obj| {
        if (!tileNearPlayer(ctx.w, ctx.player_id, obj.x, obj.y)) continue;
        const id = obj.item orelse continue;
        if (items.def(id).category == cat) return id;
    }
    return null;
}

fn printBagCategoryOptions(ent: *entity.Entity, cat: items.Category, writer: anytype) !void {
    var first = true;
    for (ent.inventory.bag.items) |stack| {
        if (stack.count == 0) continue;
        if (items.def(stack.id).category != cat) continue;
        if (!first) try writer.print(", ", .{});
        try writer.print("{s}", .{items.def(stack.id).name});
        first = false;
    }
    try writer.print("\n", .{});
}

fn resolveBagItemOrPrint(ent: *entity.Entity, name: []const u8, writer: anytype) !?items.Id {
    switch (ent.inventory.resolveBagItem(name)) {
        .found => |id| return id,
        .unknown => {
            try writer.print("unknown item\n", .{});
            return null;
        },
        .none_in_category => |cat| {
            try writer.print("no {s} in inventory\n", .{items.categoryLabel(cat)});
            return null;
        },
        .ambiguous => |cat| {
            try writer.print("ambiguous {s}; specify: ", .{items.categoryLabel(cat)});
            try printBagCategoryOptions(ent, cat, writer);
            return null;
        },
    }
}

fn cmdDrop(ctx: *Context, name: []const u8, writer: anytype) !Result {
    if (combat.isInCombat(ctx.w)) {
        try writer.print("cannot drop during combat\n", .{});
        return .continue_repl;
    }
    const ent = ctx.w.store.get(ctx.player_id) orelse {
        try writer.print("no player spawned\n", .{});
        return .continue_repl;
    };
    const id = try resolveBagItemOrPrint(ent, name, writer) orelse return .continue_repl;
    if (!ent.inventory.remove(id, 1)) {
        try writer.print("you do not have that item\n", .{});
        return .continue_repl;
    }
    try ctx.w.floor_objects.addItem(ctx.allocator, .item, ent.loc, items.idTag(id), id);
    try writer.print("dropped {s}\n", .{items.def(id).name});
    // Dropping the last copy of equipped gear must release its slot; otherwise the
    // weapon/armour reference dangles and combat keeps using the departed item.
    if (!ent.inventory.has(id) and ent.inventory.unequip(id)) {
        try writer.print("unequipped {s}\n", .{items.def(id).name});
    }
    try tickPlayerAction(ctx, 1, writer);
    try finishExploreAction(ctx, writer);
    return .continue_repl;
}

fn cmdExamine(ctx: *Context, name: []const u8, writer: anytype) !Result {
    if (items.parseId(name)) |id| {
        try printItemExamine(id, writer);
        return .continue_repl;
    }
    if (items.parseCategory(name)) |cat| {
        if (findNearbyFloorCategory(ctx, cat)) |id| {
            try printItemExamine(id, writer);
            return .continue_repl;
        }
        if (countNearbyFloorCategory(ctx, cat) > 1) {
            try writer.print("ambiguous {s} nearby; specify item name\n", .{items.categoryLabel(cat)});
            return .continue_repl;
        }
        const ent = ctx.w.store.get(ctx.player_id) orelse {
            try writer.print("no player spawned\n", .{});
            return .continue_repl;
        };
        switch (ent.inventory.resolveBagItem(name)) {
            .found => |id| {
                try printItemExamine(id, writer);
            },
            .unknown => try writer.print("unknown item\n", .{}),
            .none_in_category => {
                try writer.print("no {s} here or in inventory\n", .{items.categoryLabel(cat)});
            },
            .ambiguous => {
                try writer.print("ambiguous {s}; specify: ", .{items.categoryLabel(cat)});
                try printBagCategoryOptions(ent, cat, writer);
            },
        }
        return .continue_repl;
    }
    for (ctx.w.floor_objects.objects.items) |obj| {
        if (!tileNearPlayer(ctx.w, ctx.player_id, obj.x, obj.y)) continue;
        const matches_label = std.mem.eql(u8, name, obj.label) or
            (std.mem.eql(u8, name, "corpse") and obj.kind == .corpse);
        if (!matches_label) continue;
        switch (obj.kind) {
            .corpse => {
                if (obj.item) |loot| {
                    try writer.print("corpse {s} holds {s}\n", .{ obj.label, items.def(loot).name });
                } else {
                    try writer.print("corpse {s} is empty\n", .{obj.label});
                }
                return .continue_repl;
            },
            .item => {
                if (obj.item) |loot| {
                    const d = items.def(loot);
                    try writer.print("{s} on floor: weight={} category={s}\n", .{
                        d.name, d.weight, @tagName(d.category),
                    });
                    return .continue_repl;
                }
            },
            .trap => {},
        }
    }
    try writer.print("unknown item\n", .{});
    return .continue_repl;
}

fn cmdEquip(ctx: *Context, name: []const u8, writer: anytype) !Result {
    const ent = ctx.w.store.get(ctx.player_id) orelse {
        try writer.print("no player spawned\n", .{});
        return .continue_repl;
    };
    const id = try resolveBagItemOrPrint(ent, name, writer) orelse return .continue_repl;
    if (!ent.inventory.has(id)) {
        try writer.print("you do not have that item\n", .{});
        return .continue_repl;
    }
    const d = items.def(id);
    switch (d.category) {
        .weapon => ent.inventory.weapon = id,
        .armour => {
            if (!inventory.State.classProficient(ent, id)) {
                try writer.print("not proficient with {s}", .{d.name});
                try items.printProficiencyHint(d, ent.char.class.name, writer);
                try writer.print("\n", .{});
                return .continue_repl;
            }
            ent.inventory.armour = id;
        },
        .shield => ent.inventory.shield = id,
        .consumable => {
            try writer.print("cannot equip consumable\n", .{});
            return .continue_repl;
        },
    }
    try writer.print("equipped {s}\n", .{d.name});
    return .continue_repl;
}

fn cmdFood(ctx: *Context, name: ?[]const u8, writer: anytype) !Result {
    const ent = ctx.w.store.get(ctx.player_id) orelse {
        try writer.print("no player spawned\n", .{});
        return .continue_repl;
    };
    var food_id: ?items.Id = null;
    if (name) |n| {
        food_id = items.parseId(n);
    } else {
        for (ent.inventory.bag.items) |stack| {
            const d = items.def(stack.id);
            if (d.category == .consumable and d.is_food) {
                food_id = stack.id;
                break;
            }
        }
    }
    const id = food_id orelse {
        try writer.print("no food available\n", .{});
        return .continue_repl;
    };
    const d = items.def(id);
    if (!d.is_food) {
        try writer.print("{s} is not food\n", .{d.name});
        return .continue_repl;
    }
    if (!ent.inventory.has(id)) {
        try writer.print("you do not have {s}\n", .{d.name});
        return .continue_repl;
    }
    const notice = SurvivalNoticeState.capture(ent);
    _ = ent.inventory.remove(id, 1);
    _ = survival.eatFood(ent, id);
    ctx.w.tickAction(1);
    try notice.printChanges(ent, writer);
    try writer.print("ate {s} hunger={}\n", .{ d.name, ent.hunger });
    return .continue_repl;
}

fn cmdRest(ctx: *Context, writer: anytype) !Result {
    const ent = ctx.w.store.get(ctx.player_id) orelse {
        try writer.print("no player spawned\n", .{});
        return .continue_repl;
    };
    if (combat.isInCombat(ctx.w)) {
        try writer.print("cannot rest during combat\n", .{});
        return .continue_repl;
    }
    if (conditions.blocksMove(ent)) {
        try writer.print("cannot rest while incapacitated\n", .{});
        return .continue_repl;
    }
    const notice = SurvivalNoticeState.capture(ent);
    var i: u32 = 0;
    while (i < survival.rest_ticks) : (i += 1) {
        ctx.w.tickAction(1);
        if (combat.isInCombat(ctx.w)) {
            try writer.print("rest interrupted by combat\n", .{});
            try notice.printChanges(ent, writer);
            return .continue_repl;
        }
    }
    _ = survival.applyRest(ent);
    try notice.printChanges(ent, writer);
    try writer.print("rested (ticks={} fatigue={})\n", .{ ctx.w.game_clock.ticks, ent.fatigue });
    return .continue_repl;
}

fn cmdSleep(ctx: *Context, writer: anytype) !Result {
    const ent = ctx.w.store.get(ctx.player_id) orelse {
        try writer.print("no player spawned\n", .{});
        return .continue_repl;
    };
    if (combat.isInCombat(ctx.w)) {
        try writer.print("cannot sleep during combat\n", .{});
        return .continue_repl;
    }
    if (conditions.blocksMove(ent) and !ent.sleeping) {
        try writer.print("cannot sleep while incapacitated\n", .{});
        return .continue_repl;
    }
    ent.sleeping = true;
    conditions.apply(ent, .unconscious);
    try writer.print("sleeping (unconscious)\n", .{});
    const notice = SurvivalNoticeState.capture(ent);
    var i: u32 = 0;
    while (i < survival.sleep_ticks) : (i += 1) {
        ctx.w.tickAction(1);
        if (combat.isInCombat(ctx.w)) {
            ent.sleeping = false;
            conditions.remove(ent, .unconscious);
            _ = survival.syncExhaustion(ent);
            try writer.print("sleep interrupted by combat (interrupt rule: ambush ends sleep)\n", .{});
            try notice.printChanges(ent, writer);
            return .continue_repl;
        }
    }
    ent.sleeping = false;
    conditions.remove(ent, .unconscious);
    _ = survival.applySleep(ent);
    try notice.printChanges(ent, writer);
    try writer.print("slept (ticks={} fatigue=0)\n", .{ ctx.w.game_clock.ticks });
    return .continue_repl;
}

fn isSpawned(ctx: *const Context) bool {
    return ctx.player_id != entity.invalid_id;
}

const SurvivalNoticeState = struct {
    exhaustion: u3,
    starving: bool,
    current_hp: u32,

    fn capture(ent: *const entity.Entity) SurvivalNoticeState {
        return .{
            .exhaustion = conditions.exhaustionLevel(ent),
            .starving = conditions.has(ent, .starving),
            .current_hp = ent.current_hp,
        };
    }

    fn printChanges(self: SurvivalNoticeState, ent: *const entity.Entity, writer: anytype) !void {
        try survival.printHpDotNotice(self.current_hp, ent, writer);
        try survival.printExhaustionNotice(self.exhaustion, conditions.exhaustionLevel(ent), writer);
        try survival.printStarvingNotice(self.starving, conditions.has(ent, .starving), writer);
    }
};

fn tickPlayerAction(ctx: *Context, count: u32, writer: anytype) !void {
    const ent = ctx.w.store.get(ctx.player_id) orelse {
        ctx.w.tickAction(count);
        return;
    };
    const notice = SurvivalNoticeState.capture(ent);
    ctx.w.tickAction(count);
    try notice.printChanges(ent, writer);
}

fn finishExploreAction(ctx: *Context, writer: anytype) !void {
    if (combat.isInCombat(ctx.w)) return;
    // When explore AI is disabled (piped REPL, reference/trap scenarios), no player
    // action advances monsters or triggers ambushes. This must gate every finish path
    // — moves and non-move actions (get/loot/use/wait/open/close/wound) alike — so a
    // scripted run behaves the same regardless of which command the player issues.
    if (!ctx.w.explore_ai_on_move) return;
    const notice_before: ?SurvivalNoticeState = if (ctx.w.store.get(ctx.player_id)) |ent|
        SurvivalNoticeState.capture(ent)
    else
        null;
    const ambush = try explore.afterPlayerExploreAction(ctx.w, ctx.player_id, writer);
    if (notice_before) |before| {
        if (ctx.w.store.get(ctx.player_id)) |ent| {
            try before.printChanges(ent, writer);
        }
    }
    if (ambush) try writer.print("ambush combat started\n", .{});
}

fn finishExploreMove(ctx: *Context, writer: anytype) !void {
    // The explore_ai_on_move / combat gates live in finishExploreAction; moves add the
    // floor-1 exemption (no wandering monsters on the handcrafted starting floor).
    if (ctx.w.floor_index < 2) return;
    try finishExploreAction(ctx, writer);
}

fn cmdWound(ctx: *Context, writer: anytype) !Result {
    if (!ctx.playtest) {
        try writer.print("unknown command: wound\n", .{});
        return .continue_repl;
    }
    if (combat.isInCombat(ctx.w)) {
        try writer.print("cannot wound during combat\n", .{});
        return .continue_repl;
    }
    const ent = ctx.w.store.get(ctx.player_id) orelse {
        try writer.print("no player spawned\n", .{});
        return .continue_repl;
    };
    if (ent.current_hp <= 1) {
        try writer.print("already at minimum hp\n", .{});
        return .continue_repl;
    }
    const loss: u32 = @min(3, ent.current_hp - 1);
    ent.current_hp -= loss;
    try writer.print("wounded for playtest; hp={}/{}\n", .{ ent.current_hp, ent.max_hp });
    try tickPlayerAction(ctx, 1, writer);
    try finishExploreAction(ctx, writer);
    return .continue_repl;
}

fn cmdUse(ctx: *Context, name: []const u8, writer: anytype) !Result {
    const ent = ctx.w.store.get(ctx.player_id) orelse {
        try writer.print("no player spawned\n", .{});
        return .continue_repl;
    };
    const id = try resolveBagItemOrPrint(ent, name, writer) orelse return .continue_repl;
    if (!ent.inventory.has(id)) {
        try writer.print("you do not have that item\n", .{});
        return .continue_repl;
    }
    if (id == .antidote) {
        if (!conditions.has(ent, .poisoned)) {
            try writer.print("you are not poisoned\n", .{});
            return .continue_repl;
        }
        _ = ent.inventory.remove(id, 1);
        conditions.remove(ent, .poisoned);
        try writer.print("used antidote; poison cleared\n", .{});
        try tickPlayerAction(ctx, 1, writer);
        try finishExploreAction(ctx, writer);
        return .continue_repl;
    }
    if (id == .bandage) {
        if (combat.isInCombat(ctx.w)) {
            try writer.print("cannot use bandage during combat\n", .{});
            return .continue_repl;
        }
        if (ent.current_hp >= ent.max_hp) {
            try writer.print("you are not wounded\n", .{});
            return .continue_repl;
        }
        _ = ent.inventory.remove(id, 1);
        const applied = items.applyBandageHeal(ent);
        try writer.print("used bandage; healed {} hp\n", .{applied});
        try tickPlayerAction(ctx, 1, writer);
        try finishExploreAction(ctx, writer);
        return .continue_repl;
    }
    try writer.print("cannot use {s} here\n", .{items.def(id).name});
    return .continue_repl;
}

fn rejectCreationAfterSpawn(ctx: *const Context, writer: anytype, verb: []const u8) !bool {
    if (!isSpawned(ctx)) return false;
    try writer.print("character already spawned ({s} disabled in crawl phase)\n", .{verb});
    return true;
}

pub fn freeExpanded(allocator: std.mem.Allocator, parts: []const []const u8) void {
    for (parts) |part| allocator.free(part);
    allocator.free(parts);
}

fn appendMove(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), dir: movement.Direction) !void {
    const cmd = try std.fmt.allocPrint(allocator, "move {s}", .{movement.Direction.token(dir)});
    try list.append(allocator, cmd);
}

fn expandMoveTail(allocator: std.mem.Allocator, tail: []const u8, list: *std.ArrayList([]const u8)) !void {
    var tokens: [8][]const u8 = undefined;
    var count: usize = 0;

    var iter = std.mem.splitScalar(u8, tail, ' ');
    while (iter.next()) |raw| {
        const tok = std.mem.trim(u8, raw, " \t");
        if (tok.len == 0) continue;
        if (count >= tokens.len) return error.TooManyMoveSteps;
        tokens[count] = tok;
        count += 1;
    }
    if (count == 0) return error.InvalidMoveShorthand;

    if (count == 1) {
        const tok = tokens[0];
        if (movement.parseCompound(tok)) |pair| {
            try appendMove(allocator, list, pair[0]);
            try appendMove(allocator, list, pair[1]);
            return;
        }
        if (movement.Direction.parse(tok)) |dir| {
            try appendMove(allocator, list, dir);
            return;
        }
        return error.InvalidMoveShorthand;
    }

    for (tokens[0..count]) |tok| {
        if (movement.parseCompound(tok)) |pair| {
            try appendMove(allocator, list, pair[0]);
            try appendMove(allocator, list, pair[1]);
        } else if (movement.Direction.parse(tok)) |dir| {
            try appendMove(allocator, list, dir);
        } else {
            return error.InvalidMoveShorthand;
        }
    }
}

fn expandSegment(allocator: std.mem.Allocator, segment: []const u8, list: *std.ArrayList([]const u8)) !void {
    const trimmed = std.mem.trim(u8, segment, " \t\r\n");
    if (trimmed.len == 0) return;

    if (std.mem.eql(u8, trimmed, "l")) {
        try list.append(allocator, try allocator.dupe(u8, "look"));
        return;
    }

    if (std.mem.startsWith(u8, trimmed, "m ")) {
        const tail = std.mem.trim(u8, trimmed[2..], " \t");
        expandMoveTail(allocator, tail, list) catch |err| switch (err) {
            error.InvalidMoveShorthand, error.TooManyMoveSteps => {
                try list.append(allocator, try std.fmt.allocPrint(allocator, "move {s}", .{tail}));
            },
            else => return err,
        };
        return;
    }

    if (std.mem.startsWith(u8, trimmed, "move ")) {
        const tail = std.mem.trim(u8, trimmed[5..], " \t");
        expandMoveTail(allocator, tail, list) catch |err| switch (err) {
            error.InvalidMoveShorthand, error.TooManyMoveSteps => {
                try list.append(allocator, try allocator.dupe(u8, trimmed));
            },
            else => return err,
        };
        return;
    }

    try list.append(allocator, try allocator.dupe(u8, trimmed));
}

/// Split on `;` and expand roguelike shorthands to canonical command lines.
pub fn expandInput(allocator: std.mem.Allocator, line: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer freeExpanded(allocator, list.items);

    var segments = std.mem.splitScalar(u8, line, ';');
    while (segments.next()) |segment| {
        try expandSegment(allocator, segment, &list);
    }

    if (list.items.len == 0) {
        try list.append(allocator, try allocator.dupe(u8, "help"));
    }

    return try list.toOwnedSlice(allocator);
}

/// Parse and execute one input line, expanding shorthands and `;` chains.
pub fn executeLine(ctx: *Context, line: []const u8, writer: anytype) !Result {
    const parts = try expandInput(ctx.allocator, line);
    defer freeExpanded(ctx.allocator, parts);

    var result: Result = .continue_repl;
    for (parts) |part| {
        const cmd = parseLine(part);
        result = try execute(ctx, cmd, writer);
        if (result == .exit_repl) return result;
    }
    return result;
}

pub fn execute(ctx: *Context, cmd: Command, writer: anytype) !Result {
    if (ctx.w.isPlayerDead()) {
        switch (cmd) {
            .exit, .stats, .conditions_cmd, .inventory_cmd, .examine_item => {},
            else => {
                try writer.print("you are dead (permadeath)\n", .{});
                return .continue_repl;
            },
        }
    }
    switch (cmd) {
        .look => {
            const ent = ctx.w.store.get(ctx.player_id) orelse {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            };
            _ = ent;
            try map_render.renderLook(ctx.w, ctx.player_id, ctx.look_list_nearby, writer);
        },
        .time => {
            try writer.print("time ticks={} time_of_day={d:.4} ", .{
                ctx.w.game_clock.ticks,
                ctx.w.game_clock.time_of_day,
            });
            if (ctx.w.store.get(ctx.player_id)) |ent| {
                try survival.formatMeters(ent, writer);
            }
            try writer.writeAll("\n");
        },
        .move => |dir| {
            if (ctx.w.store.get(ctx.player_id) == null) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            if (combat.isInCombat(ctx.w) and combat.isFighting(ctx.w, ctx.player_id)) {
                const active = combat.activeTurn(ctx.w) orelse {
                    try writer.print("cannot move during combat\n", .{});
                    return .continue_repl;
                };
                if (active != ctx.player_id) {
                    try writer.print("cannot move during combat\n", .{});
                    return .continue_repl;
                }
            }
            if (ctx.w.store.get(ctx.player_id)) |ent| {
                if (ent.inventory.blocksMove(ent)) {
                    try writer.print("You are too encumbered to move.\n", .{});
                    return .continue_repl;
                }
            }
            const move_ent = ctx.w.store.get(ctx.player_id).?;
            if (movement.step(move_ent.loc, dir)) |target| {
                if (ctx.w.tileBlockReason(target, ctx.player_id)) |reason| {
                    try writer.print("{s}.\n", .{reason});
                    return .continue_repl;
                }
            }
            const notice = SurvivalNoticeState.capture(move_ent);
            const new_loc = movement.moveEntity(ctx.w, ctx.player_id, dir) catch |err| switch (err) {
                error.Blocked => {
                    try writer.print("You cannot move there.\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
            try writer.print("moved to ({},{})\n", .{ new_loc.x, new_loc.y });
            try notice.printChanges(move_ent, writer);
            if (explore.checkStepTraps(ctx.w, ctx.player_id)) {
                try writer.print("trap triggered: poisoned\n", .{});
            }
            try finishExploreMove(ctx, writer);
        },
        .wait => {
            if (ctx.w.store.get(ctx.player_id) == null) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            try tickPlayerAction(ctx, 1, writer);
            try writer.print("waited (ticks={})\n", .{ctx.w.game_clock.ticks});
            try finishExploreAction(ctx, writer);
        },
        .open_dir => |dir| {
            if (ctx.w.store.get(ctx.player_id) == null) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            if (explore.tryOpenDoor(ctx.w, ctx.player_id, dir)) {
                try writer.print("opened door to the {s}\n", .{movement.Direction.token(dir)});
            } else |err| switch (err) {
                error.NotADoor => try writer.print("no door there\n", .{}),
                error.AlreadyOpen => try writer.print("door already open\n", .{}),
                error.DoorLocked => try writer.print("door is locked\n", .{}),
                else => |e| return e,
            }
            try tickPlayerAction(ctx, 1, writer);
            try finishExploreAction(ctx, writer);
        },
        .close_dir => |dir| {
            if (ctx.w.store.get(ctx.player_id) == null) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            if (explore.tryCloseDoor(ctx.w, ctx.player_id, dir)) {
                try writer.print("closed door to the {s}\n", .{movement.Direction.token(dir)});
            } else |err| switch (err) {
                error.NotADoor => try writer.print("no door there\n", .{}),
                error.AlreadyClosed => try writer.print("door already closed\n", .{}),
                else => |e| return e,
            }
            try tickPlayerAction(ctx, 1, writer);
            try finishExploreAction(ctx, writer);
        },
        .use_item => |name| return cmdUse(ctx, name, writer),
        .wound => return cmdWound(ctx, writer),
        .conditions_cmd => {
            const ent = ctx.w.store.get(ctx.player_id) orelse {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            };
            try writer.writeAll("conditions: ");
            try conditions.formatList(ent, writer);
            try writer.writeAll("\n");
        },
        .inventory_cmd => return cmdInventory(ctx, writer),
        .get_item => |target| return cmdGet(ctx, target, writer),
        .drop_item => |name| return cmdDrop(ctx, name, writer),
        .examine_item => |name| return cmdExamine(ctx, name, writer),
        .equip_usage => {
            try writer.print("equip what? (e.g. equip short sword, equip armour)\n", .{});
        },
        .equip_item => |name| return cmdEquip(ctx, name, writer),
        .food => return cmdFood(ctx, null, writer),
        .food_item => |name| return cmdFood(ctx, name, writer),
        .rest => return cmdRest(ctx, writer),
        .sleep => return cmdSleep(ctx, writer),
        .roll => {
            if (try rejectCreationAfterSpawn(ctx, writer, "roll")) return .continue_repl;
            const pool = session.draftRoll(ctx.w, ctx.draft);
            try session.formatStatPool(pool, writer);
        },
        .assign => |picks| {
            if (try rejectCreationAfterSpawn(ctx, writer, "assign")) return .continue_repl;
            session.draftAssign(ctx.draft, picks) catch |err| switch (err) {
                error.NoStatPool => {
                    try writer.print("roll stats first\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
            try writer.print("stats assigned\n", .{});
        },
        .assign_usage => {
            if (try rejectCreationAfterSpawn(ctx, writer, "assign")) return .continue_repl;
            try writer.print(
                \\usage: assign <p1> <p2> <p3> <p4> <p5> <p6>
                \\       map rolled stats (1-6) to STR DEX CON INT WIS CHA
                \\       example: assign 6 5 4 3 2 1
                \\
            , .{});
            if (ctx.draft.has_pool) try session.formatStatPool(ctx.draft.pool, writer);
        },
        .race => |pick| {
            if (try rejectCreationAfterSpawn(ctx, writer, "race")) return .continue_repl;
            session.draftChooseRace(ctx.draft, pick) catch {
                try writer.print("invalid race pick (1-3)\n", .{});
                return .continue_repl;
            };
            try writer.print("race chosen\n", .{});
        },
        .race_usage => {
            if (try rejectCreationAfterSpawn(ctx, writer, "race")) return .continue_repl;
            try writer.print(
                \\usage: race <1-3>
                \\       1=dragonborn (+2 CHA)  2=dwarf (+2 CON)  3=elf (+2 DEX)
                \\
            , .{});
        },
        .class => |pick| {
            if (try rejectCreationAfterSpawn(ctx, writer, "class")) return .continue_repl;
            session.draftChooseClass(ctx.draft, pick) catch {
                try writer.print("invalid class pick (1-3)\n", .{});
                return .continue_repl;
            };
            try writer.print("class chosen\n", .{});
        },
        .class_usage => {
            if (try rejectCreationAfterSpawn(ctx, writer, "class")) return .continue_repl;
            try writer.print(
                \\usage: class <1-3>
                \\       1=barbarian  2=fighter  3=bard
                \\
            , .{});
        },
        .spawn => {
            if (isSpawned(ctx)) {
                try writer.print("character already spawned\n", .{});
                return .continue_repl;
            }
            const char = session.draftBuildCharacter(ctx.allocator, ctx.w, ctx.draft, "George") catch |err| switch (err) {
                error.IncompleteDraft => {
                    try writer.print("complete creation first (roll, assign, race, class)\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
            ctx.w.stageCharacter(char);
            ctx.player_id = try ctx.w.spawnStagedPlayer(loc.Loc.init(49, 49), "entity_0");
            try writer.print("spawned id={} at (49,49) (rations x{} bandage x{})\n", .{
                ctx.player_id,
                survival.starter_rations,
                survival.starter_bandage,
            });
        },
        .stats => {
            if (ctx.w.store.get(ctx.player_id)) |ent| {
                if (!ent.is_monster) {
                    try writer.print("character {s} race={s} class={s}\n", .{
                        ent.char.name,
                        ent.char.race.name,
                        ent.char.class.name,
                    });
                    for (ent.char.attributes.items) |attr| {
                        try writer.print("{s}: {}\n", .{ attr.abbr, attr.stat });
                    }
                    try writer.print("HP: {}\n", .{ ent.current_hp });
                    try writer.print("AC: {}\n", .{inventory.State.playerAc(&ent.inventory, ent)});
                    try writer.print("movement: {}\n", .{inventory.State.effectiveMovement(&ent.inventory, ent)});
                    const cap = inventory.State.carryCapacity(character.statByAbbr(ent.char, "STR"));
                    try writer.print("encumbrance: {} of {}\n", .{ ent.inventory.totalWeight(), cap });
                    try survival.formatMeters(ent, writer);
                    try writer.writeAll("\n");
                } else {
                    try character.formatStats(ent.char, writer);
                }
                if (conditions.hasActive(ent)) {
                    try writer.writeAll("conditions: ");
                    try conditions.formatList(ent, writer);
                    try writer.writeAll("\n");
                }
                if (ctx.w.isPlayerDead()) try writer.writeAll("status: dead (permadeath)\n");
            } else {
                character.formatDraftStats(ctx.allocator, ctx.w, ctx.draft, writer) catch |err| switch (err) {
                    error.IncompleteDraft => {
                        try writer.print("complete assign, race, and class for draft stats\n", .{});
                        return .continue_repl;
                    },
                    else => |e| return e,
                };
            }
        },
        .attack => {
            if (!isSpawned(ctx)) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            combat.attack(ctx.w, ctx.player_id, null, writer) catch |err| switch (err) {
                error.NoTarget => {
                    try writer.print("no valid attack target", .{});
                    try combat.formatTargetHints(ctx.w, ctx.player_id, writer);
                    if (combat.isInCombat(ctx.w)) try writer.writeAll("; move closer on your turn");
                    try writer.writeAll("\n");
                    return .continue_repl;
                },
                error.NotYourTurn => {
                    try writer.print("not your turn\n", .{});
                    return .continue_repl;
                },
                error.NotAdjacent => {
                    try writer.print("target not adjacent; move next to it first", .{});
                    try combat.formatTargetHints(ctx.w, ctx.player_id, writer);
                    try writer.writeAll("\n");
                    return .continue_repl;
                },
                else => |e| return e,
            };
        },
        .attack_target => |target| {
            if (!isSpawned(ctx)) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            combat.attack(ctx.w, ctx.player_id, target, writer) catch |err| switch (err) {
                error.NoTarget => {
                    try writer.print("no valid attack target: {s}", .{target});
                    try combat.formatTargetHints(ctx.w, ctx.player_id, writer);
                    try writer.writeAll("\n");
                    return .continue_repl;
                },
                error.NotYourTurn => {
                    try writer.print("not your turn\n", .{});
                    return .continue_repl;
                },
                error.NotAdjacent => {
                    try writer.print("target not adjacent; move next to it first", .{});
                    try combat.formatTargetHints(ctx.w, ctx.player_id, writer);
                    try writer.writeAll("\n");
                    return .continue_repl;
                },
                else => |e| return e,
            };
        },
        .descend => {
            if (!isSpawned(ctx)) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            ctx.w.descend(ctx.player_id) catch |err| switch (err) {
                error.NotOnStairs => {
                    try writer.print("not on stairs\n", .{});
                    return .continue_repl;
                },
                error.InCombat => {
                    try writer.print("cannot descend during combat\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
            try writer.print("descended to floor {}\n", .{ctx.w.floor_index});
        },
        .end_turn => {
            if (!isSpawned(ctx)) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            combat.endTurn(ctx.w, ctx.player_id, writer) catch |err| switch (err) {
                error.NotInCombat => {
                    try writer.print("not in combat\n", .{});
                    return .continue_repl;
                },
                error.NotYourTurn => {
                    try writer.print("not your turn\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
        },
        .flee => {
            if (!isSpawned(ctx)) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            combat.flee(ctx.w, ctx.player_id, writer) catch |err| switch (err) {
                error.NotInCombat => {
                    try writer.print("not in combat\n", .{});
                    return .continue_repl;
                },
                error.NotYourTurn => {
                    try writer.print("not your turn\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
        },
        .catch_breath => {
            if (!isSpawned(ctx)) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            combat.catchBreath(ctx.w, ctx.player_id, writer) catch |err| switch (err) {
                error.NotInCombat => {
                    try writer.print("not in combat\n", .{});
                    return .continue_repl;
                },
                error.NotYourTurn => {
                    try writer.print("not your turn\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
        },
        .save => {
            if (!isSpawned(ctx)) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            sqlite_store.saveSlot(ctx.allocator, ctx.save_path, 1, ctx.w, ctx.player_id, writer) catch |err| switch (err) {
                error.SqliteError => {
                    try writer.print("save failed\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
        },
        .save_slot => |save_slot| {
            if (!isSpawned(ctx)) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            if (save_slot < 1 or save_slot > 9) {
                try writer.print("invalid save slot (1-9)\n", .{});
                return .continue_repl;
            }
            sqlite_store.saveSlot(ctx.allocator, ctx.save_path, save_slot, ctx.w, ctx.player_id, writer) catch |err| switch (err) {
                error.SqliteError => {
                    try writer.print("save failed\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
        },
        .load_slot => |load_slot| {
            if (load_slot < 1 or load_slot > 9) {
                try writer.print("invalid load slot (1-9)\n", .{});
                return .continue_repl;
            }
            const loaded = sqlite_store.loadSlot(ctx.allocator, ctx.save_path, load_slot, writer) catch |err| switch (err) {
                error.SaveSlotEmpty => {
                    try writer.print("no save in slot {}\n", .{load_slot});
                    return .continue_repl;
                },
                error.SqliteError, error.UnsupportedSchema => {
                    try writer.print("load failed\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
            save_state.replaceWorld(ctx.w, loaded.world);
            ctx.player_id = loaded.player_id;
            ctx.draft.* = .{};
        },
        .save_usage => {
            try writer.print(
                \\usage: save [1-9]
                \\       example: save 1
                \\
            , .{});
        },
        .load_usage => {
            try writer.print(
                \\usage: load <1-9>
                \\       example: load 1
                \\
            , .{});
        },
        .help => {
            try help_text.writeMainHelp(writer, ctx.help_profile);
        },
        .help_descend => {
            try writer.print("descend: use on stairs (>) or floor-1 door (+); explore until you see > in look\n", .{});
        },
        .help_gear => {
            try help_text.writeGearHelp(writer);
        },
        .exit => return .exit_repl,
        .unknown => |text| {
            try writer.print("unknown command: {s}\n", .{text});
        },
    }
    return .continue_repl;
}

test "expandInput infers look shorthand" {
    const allocator = std.testing.allocator;
    const parts = try expandInput(allocator, "l");
    defer freeExpanded(allocator, parts);
    try std.testing.expectEqual(@as(usize, 1), parts.len);
    try std.testing.expectEqualStrings("look", parts[0]);
}

test "parseLine maps get and loot verbs" {
    // Bare `loot` prefers a corpse; bare `get` does not.
    const loot_cmd = parseLine("loot");
    try std.testing.expect(loot_cmd == .get_item);
    try std.testing.expect(loot_cmd.get_item.name == null);
    try std.testing.expect(loot_cmd.get_item.prefer_corpse);

    const get_cmd = parseLine("get");
    try std.testing.expect(get_cmd == .get_item);
    try std.testing.expect(get_cmd.get_item.name == null);
    try std.testing.expect(!get_cmd.get_item.prefer_corpse);

    const corpse_cmd = parseLine("loot from corpse");
    try std.testing.expect(corpse_cmd == .get_item);
    try std.testing.expectEqualStrings("corpse", corpse_cmd.get_item.name.?);

    const bandage_cmd = parseLine("loot bandage");
    try std.testing.expect(bandage_cmd == .get_item);
    try std.testing.expectEqualStrings("bandage", bandage_cmd.get_item.name.?);
}

test "expandInput infers move shorthand" {
    const allocator = std.testing.allocator;
    const parts = try expandInput(allocator, "m n");
    defer freeExpanded(allocator, parts);
    try std.testing.expectEqual(@as(usize, 1), parts.len);
    try std.testing.expectEqualStrings("move n", parts[0]);
}

test "expandInput expands compound and repeated moves" {
    const allocator = std.testing.allocator;
    const nw = try expandInput(allocator, "move nw");
    defer freeExpanded(allocator, nw);
    try std.testing.expectEqual(@as(usize, 2), nw.len);
    try std.testing.expectEqualStrings("move n", nw[0]);
    try std.testing.expectEqualStrings("move w", nw[1]);

    const ww = try expandInput(allocator, "move w w");
    defer freeExpanded(allocator, ww);
    try std.testing.expectEqual(@as(usize, 2), ww.len);
    try std.testing.expectEqualStrings("move w", ww[0]);
    try std.testing.expectEqualStrings("move w", ww[1]);

    const chain = try expandInput(allocator, "move w; move w");
    defer freeExpanded(allocator, chain);
    try std.testing.expectEqual(@as(usize, 2), chain.len);
    try std.testing.expectEqualStrings("move w", chain[0]);
    try std.testing.expectEqualStrings("move w", chain[1]);

    const se_e = try expandInput(allocator, "move se e");
    defer freeExpanded(allocator, se_e);
    try std.testing.expectEqual(@as(usize, 3), se_e.len);
    try std.testing.expectEqualStrings("move s", se_e[0]);
    try std.testing.expectEqualStrings("move e", se_e[1]);
    try std.testing.expectEqualStrings("move e", se_e[2]);

    const m_se_e = try expandInput(allocator, "m se e");
    defer freeExpanded(allocator, m_se_e);
    try std.testing.expectEqual(@as(usize, 3), m_se_e.len);
    try std.testing.expectEqualStrings("move s", m_se_e[0]);
    try std.testing.expectEqualStrings("move e", m_se_e[1]);
    try std.testing.expectEqualStrings("move e", m_se_e[2]);
}

test "parse and execute move changes position" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 7);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    var ctx = Context{
        .allocator = allocator,
        .w = &w,
        .draft = &draft,
        .player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49)),
    };

    const cmd = parseLine("move east");
    switch (cmd) {
        .move => |_| {},
        else => return error.TestExpectedEqual,
    }

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, cmd, fbs.writer());

    try std.testing.expectEqual(@as(u64, 50), w.store.get(ctx.player_id).?.loc.y);
}

test "bare assign shows usage not unknown" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft };

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const cmd = parseLine("assign");
    switch (cmd) {
        .assign_usage => {},
        else => return error.TestExpectedEqual,
    }
    _ = try execute(&ctx, cmd, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "usage: assign") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "stat_rolls:") != null);
}

test "stats before spawn exact low-con draft via execute" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 2, 4, 3, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);

    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft };
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, .stats, fbs.writer());
    try std.testing.expectEqualStrings(character.low_con_draft_sheet, fbs.getWritten());
}

test "assign rejected after spawn" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);

    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft };
    _ = try execute(&ctx, .spawn, std.io.null_writer);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, .{ .assign = .{ 1, 2, 3, 4, 5, 6 } }, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "already spawned") != null);
}

test "stats after spawn uses v0.6 hp line format" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);

    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft };
    _ = try execute(&ctx, .spawn, std.io.null_writer);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, .stats, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "HP: ") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "/") == null);
}

test "spawn after creation shows dwarf con bonus in stats" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);

    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft };
    _ = try execute(&ctx, .spawn, std.io.null_writer);
    _ = try execute(&ctx, .stats, std.io.null_writer);

    const ent = w.store.get(ctx.player_id).?;
    for (ent.char.attributes.items) |attr| {
        if (std.mem.eql(u8, attr.abbr, "CON")) {
            try std.testing.expect(attr.stat >= 12);
            return;
        }
    }
    return error.TestExpectedEqual;
}

fn combatTestCtx(allocator: std.mem.Allocator, w: *world.World) !Context {
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    _ = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");
    return .{
        .allocator = allocator,
        .w = w,
        .draft = &draft,
        .player_id = player_id,
    };
}

test "attack via execute sets fighting status" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var ctx = try combatTestCtx(allocator, &w);
    _ = try execute(&ctx, parseLine("attack goblin_0"), std.io.null_writer);
    try std.testing.expect(combat.isFighting(&w, ctx.player_id));
    try std.testing.expect(w.combat != null);
}

test "end turn via execute advances initiative" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var ctx = try combatTestCtx(allocator, &w);
    _ = try execute(&ctx, parseLine("attack goblin_0"), std.io.null_writer);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("end turn"), fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "turn:") != null or std.mem.indexOf(u8, out, "attack ") != null);
}

test "flee via execute ends combat" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var ctx = try combatTestCtx(allocator, &w);
    w.store.get(ctx.player_id).?.max_hp = 30;
    w.store.get(ctx.player_id).?.current_hp = 30;
    _ = try execute(&ctx, parseLine("attack goblin_0"), std.io.null_writer);
    try std.testing.expect(combat.isInCombat(&w));

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("flee"), fbs.writer());
    try std.testing.expect(!combat.isInCombat(&w));
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "flees from combat") != null);
}

test "flee aliases disengage and retreat parse to flee" {
    try std.testing.expect(parseLine("flee") == .flee);
    try std.testing.expect(parseLine("disengage") == .flee);
    try std.testing.expect(parseLine("retreat") == .flee);
    try std.testing.expect(parseLine("catch breath") == .catch_breath);
    try std.testing.expect(parseLine("recover") == .catch_breath);
}

test "flee out of combat via execute reports not in combat" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var ctx = try combatTestCtx(allocator, &w);
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("flee"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "not in combat") != null);
}

test "catch breath via execute recovers fatigue and keeps fighting" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var ctx = try combatTestCtx(allocator, &w);
    const player = w.store.get(ctx.player_id).?;
    player.max_hp = 40;
    player.current_hp = 40;
    player.fatigue = 42;
    _ = survival.syncExhaustion(player);
    _ = try execute(&ctx, parseLine("attack goblin_0"), std.io.null_writer);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("catch breath"), fbs.writer());
    try std.testing.expect(w.store.get(ctx.player_id).?.fatigue < 42);
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "catches their breath") != null);
}

test "move allowed on player turn during combat via execute" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var ctx = try combatTestCtx(allocator, &w);
    _ = try execute(&ctx, parseLine("attack goblin_0"), std.io.null_writer);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("move west"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "moved to") != null);
}

test "prone target via execute shows +2 mod in output" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var ctx = try combatTestCtx(allocator, &w);
    for (w.store.get(ctx.player_id).?.char.attributes.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "STR")) attr.stat = 14;
    }
    const goblin_id = blk: {
        for (w.store.entities.items) |*ent| {
            if (ent.is_monster) break :blk ent.id;
        }
        return error.TestExpectedEqual;
    };
    w.store.get(goblin_id).?.conditions.add(.prone);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("attack goblin_0"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "mod=4") != null);
}

test "blinded attacker via execute uses two rng rolls" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var ctx = try combatTestCtx(allocator, &w);
    w.store.get(ctx.player_id).?.conditions.add(.blinded);
    const offset_before = w.rng.offset;

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("attack goblin_0"), fbs.writer());
    try std.testing.expect(w.rng.offset >= offset_before + 2);
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "attack ") != null);
}

test "help descend via execute documents descend" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    var draft: session.CreationDraft = .{};
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft };
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, .help_descend, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "descend:") != null);
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "stairs") != null);
}

test "repl help via execute lists descend and gear" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    var draft: session.CreationDraft = .{};
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft };
    var buf: [768]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, .help, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "descend") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "get from corpse") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "help gear") != null);
}

fn descendTestCtx(allocator: std.mem.Allocator, w: *world.World) !Context {
    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);
    var ctx = Context{ .allocator = allocator, .w = w, .draft = &draft };
    _ = try execute(&ctx, .spawn, std.io.null_writer);
    return ctx;
}

test "descend via execute from normal spawn reaches floor 2" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    var ctx = try descendTestCtx(allocator, &w);
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("move east"), fbs.writer());
    _ = try execute(&ctx, parseLine("move south"), fbs.writer());
    _ = try execute(&ctx, parseLine("move east"), fbs.writer());
    _ = try execute(&ctx, .descend, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "descended to floor 2") != null);
    try std.testing.expectEqual(@as(u32, 2), w.floor_index);

    var layout_map = @import("terrain.zig").TerrainMap.init(allocator);
    defer layout_map.deinit();
    const gen = try dungeon.generateFloor(&layout_map, 42, w.floor_index);
    var monster_count: usize = 0;
    for (w.store.entities.items) |ent| {
        if (ent.is_monster) monster_count += 1;
    }
    evidence_format.printDescendEvidence(w.floor_index, gen.layout_hash, gen.walkable_count, monster_count);
}

test "applyBandageHeal restores flat bandage_heal on wounded player" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    const ctx = try descendTestCtx(allocator, &w);
    const ent = w.store.get(ctx.player_id).?;
    const max_hp = ent.max_hp;
    ent.current_hp = max_hp - items.bandage_heal;

    const applied = items.applyBandageHeal(ent);
    try std.testing.expectEqual(items.bandage_heal, applied);
    try std.testing.expectEqual(max_hp, ent.current_hp);
}

test "wound and bandage via execute on minimal repl path" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    var ctx = try descendTestCtx(allocator, &w);
    ctx.playtest = true;
    const ent = w.store.get(ctx.player_id).?;
    try std.testing.expect(ent.inventory.findStack(.bandage).?.count == 1);
    const max_hp = ent.max_hp;

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, .wound, fbs.writer());
    _ = try execute(&ctx, .wound, fbs.writer());
    const after_wound_hp = w.store.get(ctx.player_id).?.current_hp;
    try std.testing.expect(max_hp - after_wound_hp >= items.bandage_heal);

    _ = try execute(&ctx, parseLine("use bandage"), fbs.writer());
    _ = try execute(&ctx, .stats, fbs.writer());

    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "wounded for playtest") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "used bandage; healed 5 hp") != null);
    try std.testing.expectEqual(after_wound_hp + items.bandage_heal, w.store.get(ctx.player_id).?.current_hp);
    try std.testing.expect(!ent.inventory.has(.bandage));
}

test "use bandage via execute heals flat bandage_heal and consumes item" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    var ctx = try descendTestCtx(allocator, &w);
    const ent = w.store.get(ctx.player_id).?;
    try std.testing.expect(ent.inventory.findStack(.bandage).?.count == 1);
    const max_hp = ent.max_hp;
    const before_hp = max_hp - items.bandage_heal;
    ent.current_hp = before_hp;

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("use bandage"), fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "used bandage; healed 5 hp") != null);
    try std.testing.expectEqual(before_hp + items.bandage_heal, ent.current_hp);
    try std.testing.expectEqual(max_hp, ent.current_hp);
    try std.testing.expect(!ent.inventory.has(.bandage));
}

test "descend blocked during combat via execute" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    var ctx = try descendTestCtx(allocator, &w);
    try dungeon.walkSpawnToFloor1Stairs(&w, ctx.player_id);
    _ = try w.spawnMonster(.goblin, loc.Loc.init(51, 51), "goblin_0");
    _ = try execute(&ctx, parseLine("attack goblin_0"), std.io.null_writer);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, .descend, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "cannot descend during combat") != null);
    try std.testing.expectEqual(@as(u32, 1), w.floor_index);
}

test "dst_v08 help via execute matches golden" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    var draft: session.CreationDraft = .{};
    var ctx = Context{
        .allocator = allocator,
        .w = &w,
        .draft = &draft,
        .help_profile = .dst_v08,
    };
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, .help, fbs.writer());
    try std.testing.expectEqualStrings(help_text.dst_v08_golden, fbs.getWritten());
}

test "bare load shows usage via execute" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    var draft: session.CreationDraft = .{};
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft };
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("load"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "usage: load") != null);
}

test "save load via execute preserves crawl snapshot" {
    const allocator = std.testing.allocator;
    const path = "zig-q-cmd-test.sqlite";
    defer sqlite_store.deleteDb(path);

    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    var draft: session.CreationDraft = .{};
    _ = session.draftRoll(&w, &draft);
    try session.draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try session.draftChooseRace(&draft, 2);
    try session.draftChooseClass(&draft, 1);

    var ctx = Context{
        .allocator = allocator,
        .w = &w,
        .draft = &draft,
        .save_path = path,
    };
    _ = try execute(&ctx, .spawn, std.io.null_writer);
    _ = try execute(&ctx, parseLine("move east"), std.io.null_writer);

    var before = try save_state.capture(allocator, &w, ctx.player_id);
    defer before.deinit(allocator);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, .save, fbs.writer());
    _ = try execute(&ctx, parseLine("load 1"), fbs.writer());

    var after = try save_state.capture(allocator, &w, ctx.player_id);
    defer after.deinit(allocator);
    try save_state.expectEqual(&before, &after);
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "saved slot") != null);
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "loaded slot") != null);
}

test "get requires adjacent floor item" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    try w.floor_objects.addItem(allocator, .item, loc.Loc.init(52, 49), "leather_armour", .leather_armour);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("get leather armour"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "nothing to pick up") != null);
    try std.testing.expect(w.floor_objects.at(loc.Loc.init(52, 49)) != null);
}

test "wait prints poison hp dot after tick" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    const player = w.store.get(player_id).?;
    player.max_hp = 13;
    player.current_hp = 10;
    conditions.apply(player, .poisoned);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, .wait, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "poison deals 1 hp; hp=9/13") != null);
}

test "finish explore action prints exhaustion after monster tick" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(2);
    w.explore_ai_on_move = true;
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    const player = w.store.get(player_id).?;
    player.fatigue = 19;
    _ = survival.syncExhaustion(player);
    _ = try w.spawnMonster(.goblin, loc.Loc.init(52, 49), "goblin_0");

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try finishExploreAction(&ctx, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "exhaustion level 1") != null);
}

test "non-move action does not advance monster AI when explore_ai_on_move is off" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(2);
    w.explore_ai_on_move = false;
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    const monster_id = try w.spawnMonster(.goblin, loc.Loc.init(51, 49), "goblin_0");
    const goblin_start = w.store.get(monster_id).?.loc;
    // A pickable item on the player's tile so `get` reaches finishExploreAction.
    try w.floor_objects.addItem(allocator, .item, loc.Loc.init(49, 49), "bandage", .bandage);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("get"), fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "picked up bandage") != null);
    // Flag off: the goblin must hold still and no ambush may start, exactly like a move.
    const after_off = w.store.get(monster_id).?.loc;
    try std.testing.expectEqual(goblin_start.x, after_off.x);
    try std.testing.expectEqual(goblin_start.y, after_off.y);
    try std.testing.expect(!combat.isInCombat(&w));
    try std.testing.expect(std.mem.indexOf(u8, out, "moved") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ambush") == null);

    // Control: with the flag on, the same setup advances the goblin, proving the guard
    // above is real and not passing only because the monster could never move here.
    w.explore_ai_on_move = true;
    try w.floor_objects.addItem(allocator, .item, loc.Loc.init(49, 49), "bandage", .bandage);
    fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("get"), fbs.writer());
    const after_on = w.store.get(monster_id).?.loc;
    try std.testing.expect(after_on.x != goblin_start.x or after_on.y != goblin_start.y);
}

test "bare equip prints usage" {
    const cmd = parseLine("equip");
    try std.testing.expect(cmd == .equip_usage);
}

test "examine armour resolves nearby floor item" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    try w.floor_objects.addItem(allocator, .item, loc.Loc.init(50, 49), "leather_armour", .leather_armour);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("examine armour"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "leather armour") != null);
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "ac_bonus=11") != null);
}

test "equip armour resolves category shorthand" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    const ent = w.store.get(player_id).?;
    try ent.inventory.add(allocator, .leather_armour, 1);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("equip armour"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "equipped leather armour") != null);
    try std.testing.expectEqual(.leather_armour, ent.inventory.armour);
}

test "drop while wielded clears weapon slot and restores innate die" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    const ent = w.store.get(player_id).?;
    try ent.inventory.add(allocator, .short_sword, 1);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("equip short sword"), fbs.writer());
    try std.testing.expectEqual(.short_sword, ent.inventory.weapon.?);
    // Under the upgrade-only rule the barbarian's innate d12 outclasses the
    // short sword's d6, so wielding it leaves the effective die at d12.
    try std.testing.expectEqual(@as(u8, 12), ent.inventory.weaponDamageDie(ent));

    fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("drop short sword"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "dropped short sword") != null);
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "unequipped short sword") != null);
    // Slot released, bag empty of it, damage die stays the barbarian's d12.
    try std.testing.expect(ent.inventory.weapon == null);
    try std.testing.expect(!ent.inventory.has(.short_sword));
    try std.testing.expectEqual(@as(u8, 12), ent.inventory.weaponDamageDie(ent));
}

test "drop while worn clears armour slot and restores base ac" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    const ent = w.store.get(player_id).?;
    try ent.inventory.add(allocator, .leather_armour, 1);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("equip leather armour"), fbs.writer());
    try std.testing.expectEqual(.leather_armour, ent.inventory.armour.?);
    const worn_ac = ent.inventory.playerAc(ent);

    fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("drop leather armour"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "unequipped leather armour") != null);
    try std.testing.expect(ent.inventory.armour == null);
    // Base AC (10 + dex) differs from the leather-clad AC, confirming the fallback.
    try std.testing.expect(ent.inventory.playerAc(ent) != worn_ac);
}

test "drop one of two wielded copies keeps weapon slot" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    const ent = w.store.get(player_id).?;
    try ent.inventory.add(allocator, .short_sword, 2);
    ent.inventory.weapon = .short_sword;

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("drop short sword"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "unequipped short sword") == null);
    // A copy remains, so the wield stays consistent and the die is unchanged
    // (the barbarian's innate d12 still outclasses the short sword's d6).
    try std.testing.expectEqual(.short_sword, ent.inventory.weapon.?);
    try std.testing.expect(ent.inventory.has(.short_sword));
    try std.testing.expectEqual(@as(u8, 12), ent.inventory.weaponDamageDie(ent));
}

test "loot from corpse leaves empty corpse on floor" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    try w.floor_objects.addItem(allocator, .corpse, loc.Loc.init(50, 49), "goblin_0", .short_sword);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("loot from corpse"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "picked up short sword from goblin_0") != null);

    buf = undefined;
    fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, .look, fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "corpse goblin_0 at (50,49)") != null);
    try std.testing.expect(w.floor_objects.at(loc.Loc.init(50, 49)) != null);
    try std.testing.expect(w.floor_objects.at(loc.Loc.init(50, 49)).?.item == null);
}

test "bare loot prefers adjacent corpse over floor item" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    // Floor item added first: a bare `get` (or the old `loot`) would grab it
    // before the corpse, since it takes the first nearby object in order.
    try w.floor_objects.addItem(allocator, .item, loc.Loc.init(48, 49), "leather_armour", .leather_armour);
    try w.floor_objects.addItem(allocator, .corpse, loc.Loc.init(50, 49), "goblin_0", .short_sword);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("loot"), fbs.writer());
    // `loot` takes the corpse's gear, leaving the floor item untouched.
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "picked up short sword from goblin_0") != null);
    try std.testing.expect(w.floor_objects.at(loc.Loc.init(50, 49)).?.item == null);
    try std.testing.expect(w.floor_objects.at(loc.Loc.init(48, 49)) != null);
    try std.testing.expect(w.floor_objects.at(loc.Loc.init(48, 49)).?.item.? == .leather_armour);
}

test "bare loot falls back to floor item when no corpse loot" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    // Only a floor item is adjacent (plus an already-empty corpse): `loot`
    // still picks up the floor item rather than reporting nothing.
    try w.floor_objects.addItem(allocator, .corpse, loc.Loc.init(50, 49), "goblin_0", null);
    try w.floor_objects.addItem(allocator, .item, loc.Loc.init(48, 49), "leather_armour", .leather_armour);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("loot"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "picked up leather armour") != null);
    try std.testing.expect(w.floor_objects.at(loc.Loc.init(48, 49)) == null);
}

test "examine corpse reports empty skeleton" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    var draft: session.CreationDraft = .{};
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var ctx = Context{ .allocator = allocator, .w = &w, .draft = &draft, .player_id = player_id };
    try w.floor_objects.addItem(allocator, .corpse, loc.Loc.init(49, 50), "skeleton_0", null);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("examine corpse"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "skeleton_0 is empty") != null);
}

test "kill via execute restores exploring status" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var ctx = try combatTestCtx(allocator, &w);
    const goblin_id = blk: {
        for (w.store.entities.items) |*ent| {
            if (ent.is_monster) break :blk ent.id;
        }
        return error.TestExpectedEqual;
    };
    for (w.store.get(ctx.player_id).?.char.attributes.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "STR")) attr.stat = 18;
    }
    w.store.get(goblin_id).?.current_hp = 1;
    try combat.enterCombat(&w, ctx.player_id, goblin_id);

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var attempts: u8 = 0;
    while (w.combat != null and attempts < 30) : (attempts += 1) {
        const active = combat.activeTurn(&w) orelse break;
        if (active == ctx.player_id) {
            _ = try execute(&ctx, parseLine("attack goblin_0"), fbs.writer());
        } else {
            _ = try execute(&ctx, parseLine("end turn"), fbs.writer());
        }
    }
    const goblin = w.store.get(goblin_id).?;
    try std.testing.expect(w.combat == null);
    try std.testing.expect(w.store.get(ctx.player_id).?.char.status == .exploring);
    try std.testing.expect(goblin.current_hp == 0 or goblin.conditions.has(.dead));
}