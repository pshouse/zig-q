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
    var player_hp_before: ?u32 = null;
    if (w.combat) |c| {
        if (w.store.get(c.player_id)) |player| {
            player_ex_before = conditions.exhaustionLevel(player);
            player_hp_before = player.current_hp;
        }
    }
    w.tickAction(1);
    if (w.combat) |c| {
        if (w.store.get(c.player_id)) |player| {
            if (player_hp_before) |hp_before| {
                try survival.printHpDotNotice(hp_before, player, writer);
            }
            if (player_ex_before) |before| {
                try survival.printExhaustionNotice(before, conditions.exhaustionLevel(player), writer);
            }
        }
    }
}

/// A single free swing at the fleeing player from an adjacent hostile. Mirrors the hit
/// math of `performAttack` but costs no turn and no clock tick — it is a reaction, not an
/// action, so it does not advance the survival clock or initiative.
fn opportunityAttack(
    w: *world.World,
    attacker: *const entity.Entity,
    target_id: entity.EntityId,
    writer: anytype,
) !void {
    const target = w.store.get(target_id) orelse return;
    const roll = attackRoll(w, attacker);
    const mod = attackModifier(attacker, target);
    const ac = targetAc(target);
    const hit = @as(i32, roll) + mod >= @as(i32, @intCast(ac));

    try writer.print("opportunity attack {s}->{s} roll={} mod={} vs AC {} ", .{
        attacker.name, target.name, roll, mod, ac,
    });

    if (!hit) {
        try writer.print("miss\n", .{});
        return;
    }

    const dmg = rollDamage(w, attacker);
    applyDamage(target, @intCast(dmg));
    try writer.print("hit damage={} hp={}/{}\n", .{ dmg, target.current_hp, target.max_hp });
    if (!isAlive(target)) {
        try writer.print("{s} is slain\n", .{target.name});
        if (!target.is_monster) w.markPlayerDead(target_id);
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
    try passTurnToOpponents(w, writer);
}

/// Advance past the actor's turn and resolve the monster counters that follow. Shared by
/// `endTurn` and `catchBreath` so their turn-handoff output stays byte-identical.
fn passTurnToOpponents(w: *world.World, writer: anytype) !void {
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

/// Player disengages from combat. Each adjacent living hostile gets one opportunity attack
/// (resolved in stable entity-id order) as the cost, then combat ends and the disengage
/// itself costs one clock tick. This is the escape hatch: once out of combat the player can
/// walk off, break line of sight around a corner, or reach stairs and `descend`.
pub fn flee(w: *world.World, actor_id: entity.EntityId, writer: anytype) !void {
    if (!isInCombat(w)) return error.NotInCombat;
    const active = activeTurn(w) orelse return error.NoActiveTurn;
    if (active != actor_id) return error.NotYourTurn;

    const player = w.store.get(actor_id) orelse return error.AttackerNotFound;
    try writer.print("{s} flees from combat\n", .{player.name});

    var ids: [32]entity.EntityId = undefined;
    var n: usize = 0;
    for (w.store.entities.items) |*ent| {
        if (!ent.is_monster) continue;
        if (!isAlive(ent)) continue;
        if (!isAdjacent(player.loc, ent.loc)) continue;
        if (n < ids.len) {
            ids[n] = ent.id;
            n += 1;
        }
    }
    std.mem.sort(entity.EntityId, ids[0..n], {}, std.sort.asc(entity.EntityId));

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const attacker = w.store.get(ids[i]) orelse continue;
        if (!isAlive(attacker)) continue;
        try opportunityAttack(w, attacker, actor_id, writer);
        if (w.isPlayerDead()) break;
    }

    if (w.isPlayerDead()) {
        endCombat(w);
        return;
    }

    // Disengaging costs a moment. Resolve the tick while still in combat so an exhaustion
    // or DoT death lands in the combat context (matching `performAttack`'s death handling).
    const before_ex = conditions.exhaustionLevel(player);
    const before_hp = player.current_hp;
    w.tickAction(1);
    if (w.store.get(actor_id)) |p| {
        try survival.printHpDotNotice(before_hp, p, writer);
        try survival.printExhaustionNotice(before_ex, conditions.exhaustionLevel(p), writer);
    }
    if (w.isPlayerDead()) {
        endCombat(w);
        return;
    }

    endCombat(w);
    try writer.print("combat ended\n", .{});
}

/// In-combat recovery: the player catches their breath, shedding a little fatigue (and
/// possibly easing exhaustion), but yields the turn so monsters still counterattack. Softens
/// the exhaustion→disadvantage attrition loop without escaping the fight.
pub fn catchBreath(w: *world.World, actor_id: entity.EntityId, writer: anytype) !void {
    if (!isInCombat(w)) return error.NotInCombat;
    const active = activeTurn(w) orelse return error.NoActiveTurn;
    if (active != actor_id) return error.NotYourTurn;

    const player = w.store.get(actor_id) orelse return error.AttackerNotFound;
    const before_ex = conditions.exhaustionLevel(player);
    if (player.fatigue >= survival.fatigue_restore_catch_breath) {
        player.fatigue -= survival.fatigue_restore_catch_breath;
    } else {
        player.fatigue = 0;
    }
    _ = survival.syncExhaustion(player);
    try writer.print("{s} catches their breath (fatigue={})\n", .{ player.name, player.fatigue });
    try survival.printExhaustionNotice(before_ex, conditions.exhaustionLevel(player), writer);

    try passTurnToOpponents(w, writer);
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

test "looting a weaker weapon never cuts a melee class's damage die" {
    // Reproduces the George-the-barbarian trap: an innate d12 brawler who loots
    // and equips a short sword (d6) must keep rolling the d12 baseline, not d6.
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49)); // barbarian, innate d12
    const player = w.store.get(player_id).?;
    for (player.char.attributes.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "STR")) attr.stat = 18; // +4 damage modifier
    }

    // Bare-fisted and short-sword-equipped must both report the d12 baseline.
    try std.testing.expectEqual(@as(u8, 12), inventory.State.weaponDamageDie(&player.inventory, player));
    try player.inventory.add(allocator, .short_sword, 1);
    player.inventory.weapon = .short_sword;
    try std.testing.expectEqual(@as(u8, 12), inventory.State.weaponDamageDie(&player.inventory, player));

    // Drive the real combat damage roll: with the sword equipped, damage must be
    // able to exceed 10 (d6+4's ceiling), proving the d12 baseline still applies.
    var max_dmg: i32 = 0;
    var min_dmg: i32 = std.math.maxInt(i32);
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const dmg = rollDamage(&w, player);
        max_dmg = @max(max_dmg, dmg);
        min_dmg = @min(min_dmg, dmg);
    }
    try std.testing.expect(max_dmg > 10); // impossible with the old d6+4 cap
    try std.testing.expect(max_dmg <= 16); // stays within the d12+4 ceiling
    try std.testing.expect(min_dmg >= 5); // d12 min (1) + STR mod (4)
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

test "flee ends combat and provokes an opportunity attack" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const goblin_id = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");
    // Enough HP to survive the parting swing so we can assert the exploring status.
    w.store.get(player_id).?.max_hp = 30;
    w.store.get(player_id).?.current_hp = 30;
    try enterCombat(&w, player_id, goblin_id);
    try std.testing.expect(isInCombat(&w));

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try flee(&w, player_id, fbs.writer());

    try std.testing.expect(!isInCombat(&w));
    try std.testing.expect(w.store.get(player_id).?.char.status == .exploring);
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "flees from combat") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "opportunity attack goblin_0->entity_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "combat ended") != null);
}

test "flee outside combat errors" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try std.testing.expectError(error.NotInCombat, flee(&w, player_id, fbs.writer()));
}

test "flee provokes each adjacent hostile in id order" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    w.store.get(player_id).?.max_hp = 60;
    w.store.get(player_id).?.current_hp = 60;
    const g0 = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");
    _ = try w.spawnMonster(.goblin, loc.Loc.init(48, 49), "goblin_1");
    try enterCombat(&w, player_id, g0);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try flee(&w, player_id, fbs.writer());
    const out = fbs.getWritten();
    const idx0 = std.mem.indexOf(u8, out, "goblin_0->entity_0");
    const idx1 = std.mem.indexOf(u8, out, "goblin_1->entity_0");
    try std.testing.expect(idx0 != null and idx1 != null);
    try std.testing.expect(idx0.? < idx1.?);
    try std.testing.expect(!isInCombat(&w));
}

test "catch breath sheds fatigue and eases exhaustion" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const goblin_id = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");
    const player = w.store.get(player_id).?;
    player.max_hp = 60;
    player.current_hp = 60;
    player.fatigue = 42; // exhaustion level 2 (55 > 42 >= 40)
    _ = survival.syncExhaustion(player);
    try std.testing.expectEqual(@as(u3, 2), conditions.exhaustionLevel(player));
    try enterCombat(&w, player_id, goblin_id);

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try catchBreath(&w, player_id, fbs.writer());
    // 42 - 8 = 34 (level 1); a single monster counter ticks it to 35, still level 1.
    try std.testing.expect(w.store.get(player_id).?.fatigue < 42);
    try std.testing.expect(conditions.exhaustionLevel(w.store.get(player_id).?) < 2);
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "catches their breath") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "exhaustion eased to level 1") != null);
}

test "catch breath outside combat errors" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try std.testing.expectError(error.NotInCombat, catchBreath(&w, player_id, fbs.writer()));
}