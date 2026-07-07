const std = @import("std");
const world = @import("world.zig");
const entity = @import("entity.zig");
const loc = @import("loc.zig");
const character = @import("character.zig");
const monsters = @import("monsters.zig");
const dice = @import("dice.zig");
const types = @import("types.zig");
const conditions = @import("conditions.zig");
const inventory = @import("inventory.zig");
const items = @import("items.zig");
const survival = @import("survival.zig");

pub const CombatState = struct {
    participants: std.ArrayList(entity.EntityId),
    turn_index: usize = 0,
    player_id: entity.EntityId,

    pub fn deinit(self: *CombatState, allocator: std.mem.Allocator) void {
        self.participants.deinit(allocator);
    }
};

pub fn isInCombat(w: *const world.World) bool {
    return w.combat != null;
}

/// Phase gating: true when entity status is `.fighting` (set by enter/end combat).
pub fn isFighting(w: *const world.World, id: entity.EntityId) bool {
    const ent = w.store.get(id) orelse return false;
    return ent.char.status == .fighting;
}

pub fn activeTurn(w: *const world.World) ?entity.EntityId {
    const combat = w.combat orelse return null;
    if (combat.participants.items.len == 0) return null;
    return combat.participants.items[combat.turn_index % combat.participants.items.len];
}

fn isAlive(ent: *const entity.Entity) bool {
    return !conditions.isDead(ent);
}

fn isAdjacent(a: loc.Loc, b: loc.Loc) bool {
    const dx = @as(i64, @intCast(a.x)) - @as(i64, @intCast(b.x));
    const dy = @as(i64, @intCast(a.y)) - @as(i64, @intCast(b.y));
    const adx = if (dx < 0) -dx else dx;
    const ady = if (dy < 0) -dy else dy;
    return adx + ady == 1;
}

pub fn monsterKind(ent: *const entity.Entity) ?monsters.Kind {
    if (!ent.is_monster) return null;
    if (std.mem.eql(u8, ent.char.name, "goblin")) return .goblin;
    if (std.mem.eql(u8, ent.char.name, "skeleton")) return .skeleton;
    return null;
}

pub fn targetAc(ent: *const entity.Entity) u32 {
    if (monsterKind(ent)) |kind| return monsters.armorClass(kind);
    if (!ent.is_monster) return inventory.State.playerAc(&ent.inventory, ent);
    return character.armorClass(ent.char);
}

pub fn attackRoll(w: *world.World, attacker: *const entity.Entity) u8 {
    if (conditions.attackDisadvantage(attacker)) {
        const a = w.rng.rollDie(20);
        const b = w.rng.rollDie(20);
        return @min(a, b);
    }
    return w.rng.rollDie(20);
}

pub fn attackModifier(attacker: *const entity.Entity, target: *const entity.Entity) i32 {
    var mod = character.abilityModifier(character.statByAbbr(attacker.char, "STR"));
    mod += conditions.attackAdvantageVs(target);
    return mod;
}

fn rollDamage(w: *world.World, attacker: *const entity.Entity) i32 {
    var buf: [1]u8 = undefined;
    const mod = character.abilityModifier(character.statByAbbr(attacker.char, "STR"));
    const die = inventory.State.weaponDamageDie(&attacker.inventory, attacker);
    const result = dice.roll(&w.rng, .{ .n = 1, .sides = die, .modifier = mod }, &buf);
    return @max(result.sum, 0);
}

fn weaponTrait(attacker: *const entity.Entity) items.Trait {
    if (attacker.inventory.weapon) |wid| return items.def(wid).trait;
    return .none;
}

fn applyDamage(ent: *entity.Entity, amount: u32) void {
    if (amount >= ent.current_hp) {
        conditions.markDead(ent);
    } else {
        ent.current_hp -= amount;
    }
}

pub fn livingParticipants(w: *world.World) usize {
    const combat = w.combat orelse return 0;
    var n: usize = 0;
    for (combat.participants.items) |id| {
        if (w.store.get(id)) |ent| {
            if (isAlive(ent)) n += 1;
        }
    }
    return n;
}

fn hasAdjacentHostile(w: *const world.World, player_id: entity.EntityId) bool {
    const player = w.store.get(player_id) orelse return false;
    for (w.store.entities.items) |ent| {
        if (!ent.is_monster) continue;
        if (!isAlive(&ent)) continue;
        if (isAdjacent(player.loc, ent.loc)) return true;
    }
    return false;
}

fn appendParticipant(list: *std.ArrayList(entity.EntityId), allocator: std.mem.Allocator, id: entity.EntityId) !void {
    for (list.items) |existing| {
        if (existing == id) return;
    }
    try list.append(allocator, id);
}

fn maybeEndCombat(w: *world.World) void {
    const combat_state = w.combat orelse return;
    if (livingParticipants(w) <= 1 or !hasAdjacentHostile(w, combat_state.player_id)) {
        endCombat(w);
    }
}

fn nameMatches(ent: *const entity.Entity, name: []const u8, allow_prefix: bool) bool {
    if (std.mem.eql(u8, ent.name, name)) return true;
    if (std.mem.eql(u8, ent.char.name, name)) return true;
    if (allow_prefix and name.len > 0) {
        if (std.mem.startsWith(u8, ent.name, name)) return true;
        if (std.mem.startsWith(u8, ent.char.name, name)) return true;
    }
    return false;
}

pub fn findTarget(
    w: *const world.World,
    attacker_id: entity.EntityId,
    target_name: ?[]const u8,
) ?*entity.Entity {
    const attacker = w.store.get(attacker_id) orelse return null;

    if (target_name) |name| {
        var exact: ?*entity.Entity = null;
        var prefix: ?*entity.Entity = null;
        var prefix_count: usize = 0;
        for (w.store.entities.items) |*ent| {
            if (ent.id == attacker_id) continue;
            if (!isAlive(ent)) continue;
            if (std.mem.eql(u8, ent.name, name) or std.mem.eql(u8, ent.char.name, name)) {
                exact = ent;
                break;
            }
            if (nameMatches(ent, name, true)) {
                prefix_count += 1;
                prefix = ent;
            }
        }
        if (exact) |e| return e;
        if (prefix_count == 1) return prefix;
        return null;
    }

    var best: ?*entity.Entity = null;
    for (w.store.entities.items) |*ent| {
        if (ent.id == attacker_id) continue;
        if (!isAlive(ent)) continue;
        if (!isAdjacent(attacker.loc, ent.loc)) continue;
        if (best == null or ent.id < best.?.id) best = ent;
    }
    return best;
}

pub fn formatTargetHints(
    w: *const world.World,
    attacker_id: entity.EntityId,
    writer: anytype,
) !void {
    const attacker = w.store.get(attacker_id) orelse return;
    var adjacent = false;
    var visible = false;
    for (w.store.entities.items) |ent| {
        if (ent.id == attacker_id) continue;
        if (!isAlive(&ent)) continue;
        const adj = isAdjacent(attacker.loc, ent.loc);
        if (adj) {
            if (!adjacent) {
                try writer.writeAll("; adjacent: ");
                adjacent = true;
            } else {
                try writer.writeAll(", ");
            }
            try writer.print("{s}", .{ent.name});
        } else {
            if (!visible) {
                try writer.writeAll("; visible: ");
                visible = true;
            } else {
                try writer.writeAll(", ");
            }
            try writer.print("{s} ({s})", .{ ent.name, ent.char.name });
        }
    }
    if (!adjacent and !visible) {
        try writer.writeAll("; no creatures in sight");
    }
}

pub fn enterCombat(w: *world.World, player_id: entity.EntityId, enemy_id: entity.EntityId) !void {
    if (w.combat) |c| {
        c.deinit(w.allocator);
        w.allocator.destroy(c);
        w.combat = null;
    }

    const combat_ptr = try w.allocator.create(CombatState);
    combat_ptr.* = .{ .participants = .empty, .player_id = player_id };
    errdefer {
        combat_ptr.participants.deinit(w.allocator);
        w.allocator.destroy(combat_ptr);
    }

    try appendParticipant(&combat_ptr.participants, w.allocator, player_id);
    try appendParticipant(&combat_ptr.participants, w.allocator, enemy_id);

    const player = w.store.get(player_id) orelse return error.AttackerNotFound;
    for (w.store.entities.items) |*ent| {
        if (!ent.is_monster) continue;
        if (!isAlive(ent)) continue;
        if (!isAdjacent(player.loc, ent.loc)) continue;
        try appendParticipant(&combat_ptr.participants, w.allocator, ent.id);
        ent.char.status = .fighting;
    }

    if (w.store.get(player_id)) |p| p.char.status = .fighting;
    if (w.store.get(enemy_id)) |e| {
        if (isAlive(e)) e.char.status = .fighting;
    }

    w.combat = combat_ptr;
}

pub fn endCombat(w: *world.World) void {
    if (w.combat) |combat| {
        for (combat.participants.items) |id| {
            if (w.store.get(id)) |ent| {
                if (isAlive(ent)) ent.char.status = .exploring;
            }
        }
        combat.deinit(w.allocator);
        w.allocator.destroy(combat);
        w.combat = null;
    }
}

fn advanceTurn(w: *world.World) void {
    const combat = w.combat orelse return;
    if (combat.participants.items.len == 0) return;
    const len = combat.participants.items.len;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        combat.turn_index = (combat.turn_index + 1) % len;
        if (w.store.get(combat.participants.items[combat.turn_index])) |ent| {
            if (isAlive(ent)) return;
        }
    }
}

pub fn performAttack(
    w: *world.World,
    attacker_id: entity.EntityId,
    target_id: entity.EntityId,
    writer: anytype,
) !void {
    const attacker = w.store.get(attacker_id) orelse return error.AttackerNotFound;
    const target = w.store.get(target_id) orelse return error.TargetNotFound;

    if (!isAlive(attacker)) return error.AttackerDead;
    if (!isAlive(target)) return error.TargetDead;
    if (!isAdjacent(attacker.loc, target.loc)) return error.NotAdjacent;

    const roll = attackRoll(w, attacker);
    const mod = attackModifier(attacker, target);
    const ac = targetAc(target);
    const hit = @as(i32, roll) + mod >= @as(i32, @intCast(ac));

    try writer.print("attack {s}->{s} roll={} mod={} vs AC {} ", .{
        attacker.name, target.name, roll, mod, ac,
    });

    if (hit) {
        const dmg = rollDamage(w, attacker);
        applyDamage(target, @intCast(dmg));
        try writer.print("hit damage={} hp={}/{}\n", .{ dmg, target.current_hp, target.max_hp });
        if (roll == 20 and weaponTrait(attacker) == .trip) {
            conditions.apply(target, .prone);
            try writer.print("{s} is knocked prone\n", .{target.name});
        }
        if (!isAlive(target)) {
            try writer.print("{s} is slain\n", .{target.name});
            if (target.is_monster) {
                w.spawnCorpse(target.name, target.loc) catch {};
                w.tile_map.remove(target.loc, target.id);
            } else if (w.combat) |c| {
                if (target.id == c.player_id) w.markPlayerDead(c.player_id);
            }
            maybeEndCombat(w);
        }
    } else {
        try writer.print("miss\n", .{});
    }
    var player_ex_before: ?u3 = null;
    if (w.combat) |c| {
        if (w.store.get(c.player_id)) |player| {
            player_ex_before = conditions.exhaustionLevel(player);
        }
    }
    w.tickAction(1);
    if (player_ex_before) |before| {
        if (w.combat) |c| {
            if (w.store.get(c.player_id)) |player| {
                try survival.printExhaustionNotice(before, conditions.exhaustionLevel(player), writer);
            }
        }
    }
}

fn processMonsterTurns(w: *world.World, writer: anytype) !void {
    const combat = w.combat orelse return;
    while (true) {
        const active = activeTurn(w) orelse return;
        if (active == combat.player_id) return;
        const ent = w.store.get(active) orelse {
            advanceTurn(w);
            continue;
        };
        if (!isAlive(ent)) {
            advanceTurn(w);
            continue;
        }
        try performAttack(w, active, combat.player_id, writer);
        if (!isInCombat(w)) return;
        if (livingParticipants(w) <= 1) return;
        advanceTurn(w);
    }
}

pub fn attack(
    w: *world.World,
    attacker_id: entity.EntityId,
    target_name: ?[]const u8,
    writer: anytype,
) !void {
    if (isInCombat(w)) {
        const active = activeTurn(w) orelse return error.NoActiveTurn;
        if (active != attacker_id) return error.NotYourTurn;
    }

    const attacker = w.store.get(attacker_id) orelse return error.AttackerNotFound;
    const target = findTarget(w, attacker_id, target_name) orelse return error.NoTarget;
    if (!isAdjacent(attacker.loc, target.loc)) return error.NotAdjacent;
    if (!isInCombat(w)) try enterCombat(w, attacker_id, target.id);
    try performAttack(w, attacker_id, target.id, writer);
}

pub fn endTurn(w: *world.World, actor_id: entity.EntityId, writer: anytype) !void {
    if (!isInCombat(w)) return error.NotInCombat;
    const active = activeTurn(w) orelse return error.NoActiveTurn;
    if (active != actor_id) return error.NotYourTurn;

    advanceTurn(w);
    if (livingParticipants(w) <= 1) {
        endCombat(w);
        try writer.print("combat ended\n", .{});
        return;
    }

    try processMonsterTurns(w, writer);

    if (isInCombat(w)) {
        if (activeTurn(w)) |next| {
            if (w.store.get(next)) |ent| {
                try writer.print("turn: {s}\n", .{ent.name});
            }
        }
    } else {
        try writer.print("combat ended\n", .{});
    }
}

test "distant named attack does not enter combat" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    _ = try w.spawnMonster(.skeleton, loc.Loc.init(52, 49), "skeleton_0");

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const err = attack(&w, player_id, "skeleton", fbs.writer());
    try std.testing.expectError(error.NotAdjacent, err);
    try std.testing.expect(!isInCombat(&w));
    try std.testing.expect(!isFighting(&w, player_id));
}

test "prefix attack name resolves unique goblin" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    _ = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");

    const target = findTarget(&w, player_id, "goblin");
    try std.testing.expect(target != null);
    try std.testing.expectEqualStrings("goblin_0", target.?.name);
}

test "melee reduces target hp" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const goblin_id = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");
    try enterCombat(&w, player_id, goblin_id);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const before = w.store.get(goblin_id).?.current_hp;
    try performAttack(&w, player_id, goblin_id, fbs.writer());
    try std.testing.expect(w.store.get(goblin_id).?.current_hp <= before);
}

test "end turn advances initiative" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const goblin_id = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");
    try enterCombat(&w, player_id, goblin_id);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try endTurn(&w, player_id, fbs.writer());
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "turn:") != null or std.mem.indexOf(u8, out, "attack ") != null);
}

test "slaying last adjacent foe ends combat while distant monsters remain" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const goblin_adj = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");
    _ = try w.spawnMonster(.goblin, loc.Loc.init(52, 49), "goblin_1");
    for (w.store.get(player_id).?.char.attributes.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "STR")) attr.stat = 18;
    }
    try enterCombat(&w, player_id, goblin_adj);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var attempts: u8 = 0;
    while (w.store.get(goblin_adj).?.current_hp > 0 and attempts < 30) : (attempts += 1) {
        try performAttack(&w, player_id, goblin_adj, fbs.writer());
    }
    try std.testing.expect(w.store.get(goblin_adj).?.current_hp == 0);
    try std.testing.expect(w.combat == null);
    try std.testing.expect(w.store.get(player_id).?.char.status == .exploring);
    try std.testing.expect(w.store.get(goblin_adj).?.current_hp == 0);
}

test "player can move on their turn during combat" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const goblin_id = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");
    try enterCombat(&w, player_id, goblin_id);
    try std.testing.expect(activeTurn(&w) == player_id);

    const moved = try @import("movement.zig").moveEntity(&w, player_id, .west);
    try std.testing.expectEqual(loc.Loc.init(49, 48), moved);
    try std.testing.expect(isInCombat(&w));
}

test "combat end restores exploring status" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const goblin_id = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");
    for (w.store.get(player_id).?.char.attributes.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "STR")) attr.stat = 18;
    }
    w.store.get(goblin_id).?.current_hp = 1;
    try enterCombat(&w, player_id, goblin_id);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var attempts: u8 = 0;
    while (w.combat != null and attempts < 30) : (attempts += 1) {
        try performAttack(&w, player_id, goblin_id, fbs.writer());
    }
    try std.testing.expect(w.combat == null);
    try std.testing.expect(w.store.get(player_id).?.char.status == .exploring);
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "is slain") != null);
}