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
    save,
    save_slot: u32,
    save_usage,
    load_slot: u32,
    load_usage,
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
};

pub fn parseLine(line: []const u8) Command {
    var trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return .help;

    if (std.mem.eql(u8, trimmed, "look")) return .look;
    if (std.mem.eql(u8, trimmed, "time")) return .time;
    if (std.mem.eql(u8, trimmed, "help")) return .help;
    if (std.mem.eql(u8, trimmed, "exit")) return .exit;
    if (std.mem.eql(u8, trimmed, "roll")) return .roll;
    if (std.mem.eql(u8, trimmed, "spawn")) return .spawn;
    if (std.mem.eql(u8, trimmed, "stats")) return .stats;
    if (std.mem.eql(u8, trimmed, "attack")) return .attack;
    if (std.mem.eql(u8, trimmed, "end turn")) return .end_turn;
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

fn isSpawned(ctx: *const Context) bool {
    return ctx.player_id != entity.invalid_id;
}

fn rejectCreationAfterSpawn(ctx: *const Context, writer: anytype, verb: []const u8) !bool {
    if (!isSpawned(ctx)) return false;
    try writer.print("character already spawned ({s} disabled in crawl phase)\n", .{verb});
    return true;
}

pub fn execute(ctx: *Context, cmd: Command, writer: anytype) !Result {
    switch (cmd) {
        .look => {
            const ent = ctx.w.store.get(ctx.player_id) orelse {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            };
            _ = ent;
            try map_render.renderLook(ctx.w, ctx.player_id, writer);
        },
        .time => {
            try writer.print("time ticks={} time_of_day={d:.4}\n", .{
                ctx.w.game_clock.ticks,
                ctx.w.game_clock.time_of_day,
            });
        },
        .move => |dir| {
            if (ctx.w.store.get(ctx.player_id) == null) {
                try writer.print("no player spawned\n", .{});
                return .continue_repl;
            }
            if (combat.isInCombat(ctx.w) and combat.isFighting(ctx.w, ctx.player_id)) {
                try writer.print("cannot move during combat\n", .{});
                return .continue_repl;
            }
            const new_loc = movement.moveEntity(ctx.w, ctx.player_id, dir) catch |err| switch (err) {
                error.Blocked => {
                    try writer.print("You cannot move there.\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
            try writer.print("moved to ({},{})\n", .{ new_loc.x, new_loc.y });
        },
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
            const char = session.draftBuildCharacter(ctx.allocator, ctx.w, ctx.draft, "George") catch |err| switch (err) {
                error.IncompleteDraft => {
                    try writer.print("complete creation first (roll, assign, race, class)\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
            ctx.w.stageCharacter(char);
            ctx.player_id = try ctx.w.spawnStagedPlayer(loc.Loc.init(49, 49), "entity_0");
            try writer.print("spawned id={} at (49,49)\n", .{ ctx.player_id });
        },
        .stats => {
            if (ctx.w.store.get(ctx.player_id)) |ent| {
                try character.formatStats(ent.char, writer);
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
                    try writer.print("no valid attack target\n", .{});
                    return .continue_repl;
                },
                error.NotYourTurn => {
                    try writer.print("not your turn\n", .{});
                    return .continue_repl;
                },
                error.NotAdjacent => {
                    try writer.print("target not adjacent\n", .{});
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
                    try writer.print("no valid attack target\n", .{});
                    return .continue_repl;
                },
                error.NotYourTurn => {
                    try writer.print("not your turn\n", .{});
                    return .continue_repl;
                },
                error.NotAdjacent => {
                    try writer.print("target not adjacent\n", .{});
                    return .continue_repl;
                },
                else => |e| return e,
            };
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
            try writer.print(
                \\creation: roll, assign <6 picks>, race <1-3>, class <1-3>, spawn, stats
                \\explore:  look, time, move <north|south|east|west>, help, exit
                \\combat:   attack [target], end turn
                \\persist:  save [slot], load <slot>
                \\
                \\example: assign 6 5 4 3 2 1
                \\         race 2
                \\         class 1
                \\         spawn
                \\
            , .{});
        },
        .exit => return .exit_repl,
        .unknown => |text| {
            try writer.print("unknown command: {s}\n", .{text});
        },
    }
    return .continue_repl;
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

test "move blocked while fighting via execute" {
    const allocator = std.testing.allocator;
    var w = try world.World.init(allocator, 42);
    defer w.deinit();

    var ctx = try combatTestCtx(allocator, &w);
    _ = try execute(&ctx, parseLine("attack goblin_0"), std.io.null_writer);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    _ = try execute(&ctx, parseLine("move east"), fbs.writer());
    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "cannot move during combat") != null);
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