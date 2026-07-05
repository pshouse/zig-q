const std = @import("std");
const save_state = @import("save_state.zig");
const world = @import("world.zig");
const entity = @import("entity.zig");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const default_path = "zig-q.sqlite";
pub const dst_path = "zig-q-dst.sqlite";

pub const LoadResult = struct {
    world: world.World,
    player_id: entity.EntityId,
};

fn check(rc: c_int, db: ?*c.sqlite3, msg: []const u8) !void {
    if (rc == c.SQLITE_OK or rc == c.SQLITE_DONE or rc == c.SQLITE_ROW) return;
    if (db) |handle| {
        const err = c.sqlite3_errmsg(handle);
        if (err != null) {
            std.log.err("{s}: {s}", .{ msg, std.mem.span(err) });
        }
    }
    return error.SqliteError;
}

fn exec(db: ?*c.sqlite3, sql: [*:0]const u8) !void {
    var err_msg: [*c]u8 = null;
    const rc = c.sqlite3_exec(db, sql, null, null, &err_msg);
    if (rc != c.SQLITE_OK) {
        if (err_msg) |m| {
            std.log.err("sqlite exec: {s}", .{std.mem.span(m)});
            c.sqlite3_free(m);
        }
        return error.SqliteError;
    }
}

pub fn initSchema(db: ?*c.sqlite3) !void {
    try exec(db,
        \\PRAGMA busy_timeout = 5000;
        \\PRAGMA foreign_keys = ON;
        \\CREATE TABLE IF NOT EXISTS meta (
        \\  schema_version INTEGER NOT NULL
        \\);
        \\INSERT OR IGNORE INTO meta(schema_version) VALUES (1);
        \\CREATE TABLE IF NOT EXISTS saves (
        \\  slot INTEGER PRIMARY KEY,
        \\  payload BLOB NOT NULL,
        \\  saved_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
        \\);
    );
}

pub fn deleteDb(path: []const u8) void {
    const cwd = std.fs.cwd();
    cwd.deleteFile(path) catch {};
    inline for (.{ "-wal", "-journal", "-shm" }) |suffix| {
        var buf: [512]u8 = undefined;
        if (std.fmt.bufPrint(&buf, "{s}{s}", .{ path, suffix })) |sidecar| {
            cwd.deleteFile(sidecar) catch {};
        } else |_| {}
    }
}

pub fn open(allocator: std.mem.Allocator, path: []const u8) !?*c.sqlite3 {
    const zpath = try allocator.dupeZ(u8, path);
    defer allocator.free(zpath);
    var db: ?*c.sqlite3 = null;
    try check(c.sqlite3_open(zpath.ptr, &db), db, "sqlite3_open");
    errdefer close(db);
    try initSchema(db);
    return db;
}

pub fn close(db: ?*c.sqlite3) void {
    _ = c.sqlite3_close(db);
}

pub fn saveSlot(
    allocator: std.mem.Allocator,
    path: []const u8,
    slot: u32,
    w: *const world.World,
    player_id: entity.EntityId,
    writer: anytype,
) !void {
    var save = try save_state.capture(allocator, w, player_id);
    defer save.deinit(allocator);

    const json_blob = try std.json.Stringify.valueAlloc(allocator, save, .{});
    defer allocator.free(json_blob);

    const db = try open(allocator, path);
    defer close(db);

    var stmt: ?*c.sqlite3_stmt = null;
    try check(c.sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO saves(slot, payload) VALUES(?1, ?2);", -1, &stmt, null), db, "prepare save");
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int(stmt, 1, @intCast(slot));
    _ = c.sqlite3_bind_blob(stmt, 2, json_blob.ptr, @intCast(json_blob.len), c.SQLITE_TRANSIENT);
    try check(c.sqlite3_step(stmt), db, "save step");

    try writer.print("saved slot {} seed={} entities={} rng_offset={}\n", .{
        slot,
        w.seed,
        w.store.count(),
        w.rng.offset,
    });
}

pub fn loadSlot(
    allocator: std.mem.Allocator,
    path: []const u8,
    slot: u32,
    writer: anytype,
) !LoadResult {
    const db = try open(allocator, path);
    defer close(db);

    var stmt: ?*c.sqlite3_stmt = null;
    try check(c.sqlite3_prepare_v2(db, "SELECT payload FROM saves WHERE slot = ?1;", -1, &stmt, null), db, "prepare load");
    defer _ = c.sqlite3_finalize(stmt);
    _ = c.sqlite3_bind_int(stmt, 1, @intCast(slot));

    const rc = c.sqlite3_step(stmt);
    if (rc == c.SQLITE_DONE) return error.SaveSlotEmpty;
    try check(rc, db, "load step");

    const blob_ptr = c.sqlite3_column_blob(stmt, 0);
    const blob_len: usize = @intCast(c.sqlite3_column_bytes(stmt, 0));
    const blob: []const u8 = @as([*]const u8, @ptrCast(blob_ptr))[0..blob_len];

    const parsed = try std.json.parseFromSlice(save_state.WorldSave, allocator, blob, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    if (parsed.value.schema_version != save_state.schema_version) return error.UnsupportedSchema;

    var owned = parsed.value;
    // parsed owns strings; transfer by moving into apply before deinit
    const restored = try save_state.apply(allocator, &owned);

    try writer.print("loaded slot {} seed={} entities={} rng_offset={}\n", .{
        slot,
        restored.seed,
        restored.store.count(),
        restored.rng.offset,
    });

    return .{
        .world = restored,
        .player_id = owned.player_id,
    };
}

test "sqlite save load roundtrip" {
    const allocator = std.testing.allocator;
    const path = "zig-q-test.sqlite";
    defer deleteDb(path);

    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);
    const player_id = try w.spawnTestPlayer(@import("loc.zig").Loc.init(49, 49));
    w.tick();

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try saveSlot(allocator, path, 1, &w, player_id, fbs.writer());

    var before = try save_state.capture(allocator, &w, player_id);
    defer before.deinit(allocator);

    var out2: [256]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(&out2);
    var loaded = try loadSlot(allocator, path, 1, fbs2.writer());
    defer loaded.world.deinit();

    var after = try save_state.capture(allocator, &loaded.world, loaded.player_id);
    defer after.deinit(allocator);
    try save_state.expectEqual(&before, &after);
}

test "sqlite save load roundtrip preserves floor 2 after descend" {
    const allocator = std.testing.allocator;
    const path = "zig-q-floor2-test.sqlite";
    defer deleteDb(path);

    var w = try world.World.init(allocator, 42);
    defer w.deinit();
    try w.loadFloor(1);

    var draft = @import("session.zig").CreationDraft{};
    _ = @import("session.zig").draftRoll(&w, &draft);
    try @import("session.zig").draftAssign(&draft, .{ 6, 5, 4, 3, 2, 1 });
    try @import("session.zig").draftChooseRace(&draft, 2);
    try @import("session.zig").draftChooseClass(&draft, 1);
    const char = try @import("session.zig").draftBuildCharacter(allocator, &w, &draft, "George");
    w.stageCharacter(char);
    const player_id = try w.spawnStagedPlayer(@import("loc.zig").Loc.init(49, 53), "entity_0");
    try w.descend(player_id);
    try std.testing.expectEqual(@as(u32, 2), w.floor_index);

    var save_buf: [256]u8 = undefined;
    var save_stream = std.io.fixedBufferStream(&save_buf);
    try saveSlot(allocator, path, 1, &w, player_id, save_stream.writer());

    var before = try save_state.capture(allocator, &w, player_id);
    defer before.deinit(allocator);

    var load_buf: [256]u8 = undefined;
    var load_stream = std.io.fixedBufferStream(&load_buf);
    var loaded = try loadSlot(allocator, path, 1, load_stream.writer());
    defer loaded.world.deinit();
    try std.testing.expectEqual(@as(u32, 2), loaded.world.floor_index);

    var after = try save_state.capture(allocator, &loaded.world, loaded.player_id);
    defer after.deinit(allocator);
    try save_state.expectEqual(&before, &after);
}