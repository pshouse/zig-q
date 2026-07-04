const std = @import("std");
const world = @import("world.zig");
const entity = @import("entity.zig");
const loc = @import("loc.zig");
const character = @import("character.zig");
const monsters = @import("monsters.zig");
const dice = @import("dice.zig");
const types = @import("types.zig");

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

pub fn activeTurn(w: *const world.World) ?entity.EntityId {
    const combat = w.combat orelse return null;
    if (combat.participants.items.len == 0) return null;
    return combat.participants.items[combat.turn_index % combat.participants.items.len];
}

pub fn targetArmorClass(char: *const types.Character) u32 {
    if (char.is_monster) return monsters.armorClass(char);
    return character.armorClass(char);
}

fn isAlive(ent: *const entity.Entity) bool {
    return !ent.conditions.has(.dead) and ent.char.current_hp > 0;
}

fn isAdjacent(a: loc.Loc, b: loc.Loc) bool {
    const dx = @as(i64, @intCast(a.x)) - @as(i64, @intCast(b.x));
    const dy = @as(i64, @intCast(a.y)) - @as(i64, @intCast(b.y));
    const adx = if (dx < 0) -dx else dx;
    const ady = if (dy < 0) -dy else dy;
    return adx + ady == 1;
}

fn attackRoll(w: *world.World, attacker: *const entity.Entity) u8 {
    if (attacker.conditions.has(.blinded) or attacker.conditions.has(.prone)) {
        const a = w.rng.rollDie(20);
        const b = w.rng.rollDie(20);
        return @min(a, b);
    }
    return w.rng.rollDie(20);
}

fn strModifier(char: *const types.Character) i32 {
    return character.abilityModifier(character.statByAbbr(char, "STR"));
}

fn rollDamage(w: *world.World, char: *const types.Character) i32 {
    var buf: [1]u8 = undefined;
    const mod = strModifier(char);
    const result = dice.roll(&w.rng, .{ .n = 1, .sides = char.damage_die, .modifier = mod }, &buf);
    return @max(result.sum, 0);
}

fn applyDamage(ent: *entity.Entity, amount: u32) void {
    if (amount >= ent.char.current_hp) {
        ent.char.current_hp = 0;
        ent.conditions.add(.dead);
    } else {
        ent.char.current_hp -= amount;
    }
}

pub fn findTarget(
    w: *const world.World,
    attacker_id: entity.EntityId,
    target_name: ?[]const u8,
) ?*entity.Entity {
    const attacker = w.store.get(attacker_id) orelse return null;

    if (target_name) |name| {
        for (w.store.entities.items) |*ent| {
            if (ent.id == attacker_id) continue;
            if (!isAlive(ent)) continue;
            if (std.mem.eql(u8, ent.name, name) or std.mem.eql(u8, ent.char.name, name))
                return ent;
        }
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

pub fn enterCombat(w: *world.World, player_id: entity.EntityId, enemy_id: entity.EntityId) !void {
    if (w.combat) |c| {
        c.deinit(w.allocator);
        w.allocator.destroy(c);
        w.combat = null;
    }

    const combat = try w.allocator.create(CombatState);
    combat.* = .{
        .participants = .empty,
        .turn_index = 0,
        .player_id = player_id,
    };
    errdefer {
        combat.participants.deinit(w.allocator);
        w.allocator.destroy(combat);
    }

    try combat.participants.append(w.allocator, player_id);
    try combat.participants.append(w.allocator, enemy_id);

    if (w.store.get(player_id)) |p| p.char.status = .fighting;
    if (w.store.get(enemy_id)) |e| e.char.status = .fighting;

    w.combat = combat;
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
    var attack_total = @as(i32, roll) + strModifier(attacker.char);
    if (target.conditions.has(.prone)) attack_total += 2;

    const ac = targetArmorClass(target.char);
    const hit = attack_total >= @as(i32, @intCast(ac));

    try writer.print("attack {s}->{s} roll={} mod={} vs AC {} ", .{
        attacker.name,
        target.name,
        roll,
        strModifier(attacker.char),
        ac,
    });

    if (hit) {
        const dmg = rollDamage(w, attacker.char);
        applyDamage(target, @intCast(dmg));
        try writer.print("hit damage={} hp={}/{}\n", .{
            dmg,
            target.char.current_hp,
            target.char.max_hp,
        });
        if (!isAlive(target)) {
            try writer.print("{s} is slain\n", .{target.name});
            if (livingParticipants(w) <= 1) endCombat(w);
        }
    } else {
        try writer.print("miss\n", .{});
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
    if (w.combat) |combat| {
        const active = activeTurn(w) orelse return error.NoActiveTurn;
        if (active != attacker_id) return error.NotYourTurn;
        _ = combat;
    }

    const target = findTarget(w, attacker_id, target_name) orelse return error.NoTarget;
    if (w.combat == null) {
        try enterCombat(w, attacker_id, target.id);
    }
    try performAttack(w, attacker_id, target.id, writer);
}

pub fn endTurn(w: *world.World, actor_id: entity.EntityId, writer: anytype) !void {
    if (w.combat == null) return error.NotInCombat;
    const active = activeTurn(w) orelse return error.NoActiveTurn;
    if (active != actor_id) return error.NotYourTurn;

    advanceTurn(w);
    if (livingParticipants(w) <= 1) {
        endCombat(w);
        try writer.print("combat ended\n", .{});
        return;
    }

    try processMonsterTurns(w, writer);

    if (w.combat != null) {
        if (activeTurn(w)) |next| {
            if (w.store.get(next)) |ent| {
                try writer.print("turn: {s}\n", .{ent.name});
            }
        }
    } else {
        try writer.print("combat ended\n", .{});
    }
}

test "combat attack reduces hp on hit" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    const player_id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const goblin_id = try w.spawnMonster(.goblin, loc.Loc.init(50, 49), "goblin_0");

    try enterCombat(&w, player_id, goblin_id);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const before = w.store.get(goblin_id).?.char.current_hp;
    try performAttack(&w, player_id, goblin_id, fbs.writer());
    const after = w.store.get(goblin_id).?.char.current_hp;
    try std.testing.expect(after <= before);
}