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

fn isAlive(ent: *const entity.Entity) bool {
    return !ent.conditions.has(.dead) and ent.current_hp > 0;
}

fn isAdjacent(a: loc.Loc, b: loc.Loc) bool {
    const dx = @as(i64, @intCast(a.x)) - @as(i64, @intCast(b.x));
    const dy = @as(i64, @intCast(a.y)) - @as(i64, @intCast(b.y));
    const adx = if (dx < 0) -dx else dx;
    const ady = if (dy < 0) -dy else dy;
    return adx + ady == 1;
}

pub fn targetAc(ent: *const entity.Entity) u32 {
    if (ent.is_monster) {
        if (std.mem.eql(u8, ent.char.name, "goblin")) return monsters.armorClass(.goblin);
        if (std.mem.eql(u8, ent.char.name, "skeleton")) return monsters.armorClass(.skeleton);
    }
    return character.armorClass(ent.char);
}

pub fn attackRoll(w: *world.World, attacker: *const entity.Entity) u8 {
    if (attacker.conditions.has(.blinded) or attacker.conditions.has(.prone)) {
        const a = w.rng.rollDie(20);
        const b = w.rng.rollDie(20);
        return @min(a, b);
    }
    return w.rng.rollDie(20);
}

pub fn attackModifier(attacker: *const entity.Entity, target: *const entity.Entity) i32 {
    var mod = character.abilityModifier(character.statByAbbr(attacker.char, "STR"));
    if (target.conditions.has(.prone)) mod += 2;
    return mod;
}

fn rollDamage(w: *world.World, attacker: *const entity.Entity) i32 {
    var buf: [1]u8 = undefined;
    const mod = character.abilityModifier(character.statByAbbr(attacker.char, "STR"));
    const die = if (attacker.damage_die > 0) attacker.damage_die else attacker.char.class.hit_die;
    const result = dice.roll(&w.rng, .{ .n = 1, .sides = die, .modifier = mod }, &buf);
    return @max(result.sum, 0);
}

fn applyDamage(ent: *entity.Entity, amount: u32) void {
    if (amount >= ent.current_hp) {
        ent.current_hp = 0;
        ent.conditions.add(.dead);
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

    const combat_ptr = try w.allocator.create(CombatState);
    combat_ptr.* = .{ .participants = .empty, .player_id = player_id };
    errdefer {
        combat_ptr.participants.deinit(w.allocator);
        w.allocator.destroy(combat_ptr);
    }

    try combat_ptr.participants.append(w.allocator, player_id);
    try combat_ptr.participants.append(w.allocator, enemy_id);

    if (w.store.get(player_id)) |p| p.char.status = .fighting;
    if (w.store.get(enemy_id)) |e| e.char.status = .fighting;

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
    if (w.combat != null) {
        const active = activeTurn(w) orelse return error.NoActiveTurn;
        if (active != attacker_id) return error.NotYourTurn;
    }

    const target = findTarget(w, attacker_id, target_name) orelse return error.NoTarget;
    if (w.combat == null) try enterCombat(w, attacker_id, target.id);
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

test "blinded attacker rolls twice" {
    var w = try world.World.init(std.testing.allocator, 42);
    defer w.deinit();
    const id = try w.spawnTestPlayer(loc.Loc.init(49, 49));
    const ent = w.store.get(id).?;
    ent.conditions.add(.blinded);

    const offset_before = w.rng.offset;
    _ = attackRoll(&w, ent);
    try std.testing.expect(w.rng.offset == offset_before + 2);
}

test "prone target grants +2 attack bonus" {
    const allocator = std.testing.allocator;
    var attacker_char = types.Character{
        .name = "a",
        .attributes = try types.defaultAttributes(allocator),
        .race = .{ .name = "human", .speed = 30, .attr_bonuses = .empty },
        .class = .{ .name = "fighter", .hit_die = 10 },
    };
    defer attacker_char.attributes.deinit(allocator);
    for (attacker_char.attributes.items) |*attr| {
        if (std.mem.eql(u8, attr.abbr, "STR")) attr.stat = 14;
    }

    var target_char = types.Character{
        .name = "t",
        .attributes = try types.defaultAttributes(allocator),
        .race = .{ .name = "human", .speed = 30, .attr_bonuses = .empty },
        .class = .{ .name = "fighter", .hit_die = 10 },
    };
    defer target_char.attributes.deinit(allocator);

    var attacker_name: [4]u8 = .{ 'a', 0, 0, 0 };
    var target_name: [4]u8 = .{ 't', 0, 0, 0 };
    const attacker = entity.Entity{
        .id = 0,
        .name = attacker_name[0..1],
        .loc = loc.Loc.init(0, 0),
        .char = &attacker_char,
        .conditions = types.ConditionSet.initEmpty(),
        .current_hp = 10,
        .max_hp = 10,
        .damage_die = 8,
    };
    var target_ent = entity.Entity{
        .id = 1,
        .name = target_name[0..1],
        .loc = loc.Loc.init(0, 1),
        .char = &target_char,
        .conditions = types.ConditionSet.initEmpty(),
        .current_hp = 10,
        .max_hp = 10,
        .damage_die = 8,
    };
    target_ent.conditions.add(.prone);

    try std.testing.expectEqual(@as(i32, 4), attackModifier(&attacker, &target_ent));
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