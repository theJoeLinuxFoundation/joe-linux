//! dave's answers for programs: with `--json`, a question (`list`, `info`,
//! `search`, `status`, `deployments`) or a look at a change (`install`,
//! `remove` or `upgrade` with `--dry-run`, `upgrade --check`) prints one JSON
//! document on standard output, and what is said for people goes to standard
//! error. The desktop's shell reads the system's state this way, and its
//! Packages application shows and drives changes.
//!
//! Every document names its schema, "dave.<kind>/<n>". A field may be added
//! without changing <n>; a field that goes or changes meaning makes it
//! <n+1>. A reader ignores fields it does not know and treats a schema it
//! does not know as unreadable. A failure prints a `dave.error/1` document
//! (its `message` is the sentence dave says to people) and exits 1.
//!
//! - `dave.list/1`: `packages`, each `name`, `version`, `requested`.
//! - `dave.info/1`: `name`, `description`, `license`, `installed` (null, or
//!   `version`, `reason` (requested, dependency or orphan), `needed_by`,
//!   `size`, `files`), `available` (null, or `version`, `repository`,
//!   `download_size`, `installed_size`), `depends`, `required_by`.
//! - `dave.search/1`: `index` (fresh, cached, or none when no index has been
//!   fetched), `packages`, each `name`, `version`, `description`,
//!   `installed` (null or the installed version). No match is an empty list.
//! - `dave.plan/1`: `operation` (install, remove, upgrade), `index`,
//!   `digest`, `install`, `upgrade` and `remove` (each entry `name`,
//!   `version`, `from` for an upgrade, `named`, `requested`),
//!   `download_size`, `disk_change` (null when a size is unknown) and, for
//!   an upgrade, `prepared` (null, or the upgrade already waiting for
//!   shutdown). Empty lists and a null digest: nothing to do.
//! - `dave.result/1`: after a change was made: `operation`, `digest`,
//!   `rollback_point` (the deployment that `dave rollback` returns to).
//! - `dave.status/1` and `dave.deployments/1`: see Status below.
//!
//! The digest names a change: the packages that come in, move and go, with
//! their versions. `--expect DIGEST` makes `install`, `remove` and `upgrade`
//! refuse unless the change they would make is the one the digest names, so
//! a program can show a plan, have it confirmed, and make exactly that
//! change, or none if the repositories or the system moved meanwhile.

const std = @import("std");
const Allocator = std.mem.Allocator;
const plan = @import("plan.zig");
const deploy = @import("deploy.zig");
const boot = @import("boot.zig");
const archive = @import("archive.zig");

pub const Index = enum { fresh, cached, none };

// -- packages -----------------------------------------------------------------

pub const Listed = struct { name: []const u8, version: []const u8, requested: bool };
pub const List = struct { schema: []const u8 = "dave.list/1", packages: []const Listed };

pub const Installed = struct {
    version: []const u8,
    reason: enum { requested, dependency, orphan },
    /// For a dependency: the installed package that needs it.
    needed_by: ?[]const u8,
    size: u64,
    files: usize,
};
pub const Available = struct {
    version: []const u8,
    repository: []const u8,
    download_size: u64,
    installed_size: ?u64,
};
pub const Info = struct {
    schema: []const u8 = "dave.info/1",
    name: []const u8,
    description: []const u8,
    license: []const u8,
    installed: ?Installed,
    available: ?Available,
    depends: []const []const u8,
    required_by: []const []const u8,
};

pub const Found = struct { name: []const u8, version: []const u8, description: []const u8, installed: ?[]const u8 };
pub const Search = struct { schema: []const u8 = "dave.search/1", index: Index, packages: []const Found };

// -- changes ------------------------------------------------------------------

pub const Change = struct {
    name: []const u8,
    version: []const u8,
    from: ?[]const u8 = null,
    named: bool,
    requested: bool,
};

pub const Prepared = struct {
    summary: []const u8,
    /// Packages to install or move to another version, and to remove.
    install: usize,
    remove: usize,

    pub fn of(s: deploy.Staged) Prepared {
        return .{ .summary = s.summary, .install = s.packages.len, .remove = s.remove.len };
    }
};

pub const Plan = struct {
    schema: []const u8 = "dave.plan/1",
    operation: plan.Kind,
    index: Index,
    digest: ?[]const u8,
    install: []const Change,
    upgrade: []const Change,
    remove: []const Change,
    download_size: u64,
    disk_change: ?i64,
    prepared: ?Prepared = null,
};

pub const Result = struct {
    schema: []const u8 = "dave.result/1",
    operation: plan.Kind,
    digest: ?[]const u8,
    rollback_point: ?u32,
};

fn changes(arena: Allocator, entries: []const plan.Entry) ![]const Change {
    const out = try arena.alloc(Change, entries.len);
    for (entries, out) |e, *c| c.* = .{ .name = e.name, .version = e.version, .from = e.from, .named = e.named, .requested = e.requested };
    return out;
}

pub fn planOf(arena: Allocator, kind: plan.Kind, p: plan.Plan, index: Index, prepared: ?deploy.Staged) !Plan {
    return .{
        .operation = kind,
        .index = index,
        .digest = try digest(arena, kind, p),
        .install = try changes(arena, p.install),
        .upgrade = try changes(arena, p.upgrade),
        .remove = try changes(arena, p.remove),
        .download_size = p.download,
        .disk_change = p.disk,
        .prepared = if (prepared) |s| Prepared.of(s) else null,
    };
}

/// "sha256:" and the hash of the change, one sorted line per package; null
/// for no change. Whether a package was named or requested is not part of
/// it: the same packages and versions are the same change.
pub fn digest(arena: Allocator, kind: plan.Kind, p: plan.Plan) !?[]const u8 {
    if (p.isEmpty()) return null;
    var lines: std.ArrayList([]const u8) = .empty;
    for (p.install) |e| try lines.append(arena, try std.fmt.allocPrint(arena, "install {s} {s}\n", .{ e.name, e.version }));
    for (p.upgrade) |e| try lines.append(arena, try std.fmt.allocPrint(arena, "upgrade {s} {s} {s}\n", .{ e.name, e.from orelse "", e.version }));
    for (p.remove) |e| try lines.append(arena, try std.fmt.allocPrint(arena, "remove {s} {s}\n", .{ e.name, e.version }));
    std.mem.sort([]const u8, lines.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);
    var text: std.Io.Writer.Allocating = .init(arena);
    try text.writer.print("dave.plan/1\n{t}\n", .{kind});
    for (lines.items) |l| try text.writer.writeAll(l);
    const hash = archive.hashBytes(text.written());
    return try std.fmt.allocPrint(arena, "sha256:{s}", .{&hash});
}

// -- status -------------------------------------------------------------------
//
// `dave.status/1`: `revision` (changes whenever anything below does, for a
// program that polls), `managed` (false for a system that is not made of
// deployments: an image, a container), `complete` (false when dave could see
// only the running deployment: run without root before dave-status.service
// published the rest at boot; treat the rest as unknown, not as empty),
// `running` and `next_boot` (deployment ids), `deployments` (each `id`,
// `running`, `next_boot`, `health`: good, untested, failed, or null without a
// boot entry; `pinned`, `reason`, `created`, `parent`), `prepared_upgrade`
// (null, or the upgrade waiting for shutdown: `summary`, `install`,
// `remove`) and `last_upgrade` (null, or how the last upgrade applied at
// shutdown went: see Outcome). `dave.deployments/1` has `running`,
// `complete` and `deployments` alone.

pub const Health = enum { good, untested, failed };

pub const Deployment = struct {
    id: u32,
    running: bool,
    next_boot: bool,
    health: ?Health,
    pinned: bool,
    reason: []const u8,
    created: ?i64,
    parent: ?u32,
};

/// How the last upgrade applied at shutdown turned out, read from the boot
/// loader's own counting of attempts, never guessed from which deployment
/// is running:
///
/// - `succeeded`: the upgraded deployment is running and passed its boot
///   check.
/// - `checking`: it is running and its boot check has not passed yet.
/// - `fallback`: it failed its boot check on every attempt, and the boot
///   loader went back to the system before by itself. `deployment` is the
///   upgrade that failed; `running` is the system restored.
/// - `not_running`: another deployment was chosen, at the boot menu or with
///   `dave rollback`. Nothing failed.
/// - `not_applied`: the upgrade could not be applied at shutdown; the system
///   before it kept running. `message` says why.
/// - `unknown`: its deployment is gone, or has no boot entry.
///
/// `event` names the upgrade, so that a program that tells people about it
/// can tell them once.
pub const Outcome = enum { succeeded, checking, fallback, not_running, not_applied, unknown };

pub const LastUpgrade = struct {
    event: []const u8,
    outcome: Outcome,
    /// The deployment the upgrade made; null when none was made.
    deployment: ?u32,
    /// Why it was not applied, or what it changed.
    message: []const u8,
};

pub const Status = struct {
    schema: []const u8 = "dave.status/1",
    revision: []const u8 = "",
    managed: bool,
    complete: bool,
    running: ?u32,
    next_boot: ?u32,
    deployments: []const Deployment,
    prepared_upgrade: ?Prepared,
    last_upgrade: ?LastUpgrade,
};

pub const Deployments = struct {
    schema: []const u8 = "dave.deployments/1",
    running: u32,
    complete: bool,
    deployments: []const Deployment,
};

fn health(h: ?boot.Health) ?Health {
    return switch (h orelse return null) {
        .good => .good,
        .trial => .untested,
        .bad => .failed,
    };
}

pub fn deploymentsOf(arena: Allocator, view: deploy.System.Overview) ![]const Deployment {
    const out = try arena.alloc(Deployment, view.deployments.len);
    for (view.deployments, out) |d, *o| o.* = .{
        .id = d.id,
        .running = d.running,
        .next_boot = d.next_boot,
        .health = health(d.health),
        .pinned = if (d.record) |r| r.pinned else false,
        .reason = if (d.record) |r| r.reason else "",
        .created = if (d.record) |r| (if (r.created != 0) r.created else null) else null,
        .parent = if (d.record) |r| r.parent else null,
    };
    return out;
}

pub fn lastUpgrade(arena: Allocator, running: u32, view: deploy.System.Overview) !?LastUpgrade {
    const last = view.last_finalize orelse return null;
    const attempt = try std.fmt.allocPrint(arena, "attempt-{d}", .{last.at});
    if (!last.ok) return .{ .event = attempt, .outcome = .not_applied, .deployment = null, .message = last.message };
    const id = last.deployment orelse return .{ .event = attempt, .outcome = .unknown, .deployment = null, .message = last.message };
    const event = try std.fmt.allocPrint(arena, "deployment-{d}", .{id});
    const d = for (view.deployments) |d| {
        if (d.id == id) break d;
    } else return .{ .event = event, .outcome = .unknown, .deployment = id, .message = last.message };
    const h = d.health orelse return .{ .event = event, .outcome = .unknown, .deployment = id, .message = last.message };
    const outcome: Outcome = if (id == running)
        // On its last attempt a deployment counts as failed until its boot
        // check passes; while it runs, that is still checking.
        (if (h == .good) .succeeded else .checking)
    else if (h == .bad)
        .fallback
    else
        .not_running;
    return .{ .event = event, .outcome = outcome, .deployment = id, .message = last.message };
}

pub fn statusOf(arena: Allocator, running: u32, view: deploy.System.Overview) !Status {
    var next: ?u32 = null;
    for (view.deployments) |d| if (d.next_boot) {
        next = d.id;
    };
    return .{
        .managed = true,
        .complete = true,
        .running = running,
        .next_boot = next,
        .deployments = try deploymentsOf(arena, view),
        .prepared_upgrade = if (view.staged) |s| Prepared.of(s) else null,
        .last_upgrade = try lastUpgrade(arena, running, view),
    };
}

/// The status with its revision: a hash of everything else in it.
pub fn withRevision(arena: Allocator, s: Status) !Status {
    var text: std.Io.Writer.Allocating = .init(arena);
    var without = s;
    without.revision = "";
    try std.json.Stringify.value(without, .{}, &text.writer);
    const hash = archive.hashBytes(text.written());
    var out = s;
    out.revision = try arena.dupe(u8, hash[0..16]);
    return out;
}

pub const Error = struct { schema: []const u8 = "dave.error/1", message: []const u8 };

// -- tests --------------------------------------------------------------------

const testing = std.testing;

fn overviewOf(deployments: []const deploy.System.DeploymentView, last: ?deploy.FinalizeOutcome) deploy.System.Overview {
    return .{ .deployments = deployments, .staged = null, .last_finalize = last };
}

fn dv(id: u32, running: bool, next: bool, h: ?boot.Health) deploy.System.DeploymentView {
    return .{ .id = id, .running = running, .next_boot = next, .health = h, .priority = null, .record = null };
}

test "an upgrade that boots and passes its check succeeded" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const v = overviewOf(&.{ dv(5, true, true, .good), dv(4, false, false, .good) }, .{ .ok = true, .deployment = 5, .message = "2 to install or upgrade, 0 to remove" });
    const last = (try lastUpgrade(arena.allocator(), 5, v)).?;
    try testing.expectEqual(Outcome.succeeded, last.outcome);
    try testing.expectEqualStrings("deployment-5", last.event);
    // Before its boot check passes, it is still being checked.
    const trial = overviewOf(&.{ dv(5, true, true, .trial), dv(4, false, false, .good) }, v.last_finalize);
    try testing.expectEqual(Outcome.checking, (try lastUpgrade(arena.allocator(), 5, trial)).?.outcome);
    const last_try = overviewOf(&.{ dv(5, true, true, .bad), dv(4, false, false, .good) }, v.last_finalize);
    try testing.expectEqual(Outcome.checking, (try lastUpgrade(arena.allocator(), 5, last_try)).?.outcome);
}

test "an upgrade that used up its boot attempts fell back by itself" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const v = overviewOf(&.{ dv(4, true, true, .good), dv(5, false, false, .bad) }, .{ .ok = true, .deployment = 5 });
    const last = (try lastUpgrade(arena.allocator(), 4, v)).?;
    try testing.expectEqual(Outcome.fallback, last.outcome);
    try testing.expectEqual(@as(?u32, 5), last.deployment);
}

test "choosing an older deployment is not a failed upgrade" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    // At the boot menu, before the upgrade had been tried, or after it
    // succeeded and `dave rollback` was run.
    for ([_]boot.Health{ .trial, .good }) |h| {
        const v = overviewOf(&.{ dv(5, false, h == .good, h), dv(4, true, h != .good, .good) }, .{ .ok = true, .deployment = 5 });
        try testing.expectEqual(Outcome.not_running, (try lastUpgrade(arena.allocator(), 4, v)).?.outcome);
    }
}

test "an upgrade that could not be applied names why" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const v = overviewOf(&.{dv(4, true, true, .good)}, .{ .ok = false, .message = "no space left on device", .at = 1700000000 });
    const last = (try lastUpgrade(arena.allocator(), 4, v)).?;
    try testing.expectEqual(Outcome.not_applied, last.outcome);
    try testing.expectEqualStrings("attempt-1700000000", last.event);
    try testing.expectEqualStrings("no space left on device", last.message);
    try testing.expect(last.deployment == null);
}

test "an upgrade whose deployment is gone is unknown, and no upgrade is null" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gone = overviewOf(&.{dv(9, true, true, .good)}, .{ .ok = true, .deployment = 5 });
    try testing.expectEqual(Outcome.unknown, (try lastUpgrade(arena.allocator(), 9, gone)).?.outcome);
    try testing.expect((try lastUpgrade(arena.allocator(), 9, overviewOf(&.{dv(9, true, true, .good)}, null))) == null);
}

test "status says explicitly that nothing is prepared, and its revision follows its contents" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const v = overviewOf(&.{ dv(5, true, true, .good), dv(4, false, false, .good) }, null);
    const s = try withRevision(a, try statusOf(a, 5, v));
    var text: std.Io.Writer.Allocating = .init(a);
    try std.json.Stringify.value(s, .{}, &text.writer);
    try testing.expect(std.mem.indexOf(u8, text.written(), "\"schema\":\"dave.status/1\"") != null);
    try testing.expect(std.mem.indexOf(u8, text.written(), "\"prepared_upgrade\":null") != null);
    try testing.expect(std.mem.indexOf(u8, text.written(), "\"health\":\"good\"") != null);
    try testing.expectEqual(@as(usize, 16), s.revision.len);

    var staged = v;
    staged.staged = .{ .db_hash = "x", .summary = "1 to install or upgrade, 0 to remove", .packages = &.{"a.dave"} };
    const t = try withRevision(a, try statusOf(a, 5, staged));
    try testing.expect(!std.mem.eql(u8, s.revision, t.revision));
    try testing.expectEqual(@as(usize, 1), t.prepared_upgrade.?.install);
    try testing.expectEqualStrings(s.revision, (try withRevision(a, try statusOf(a, 5, v))).revision);
}

test "a change's digest names its packages and versions, in any order" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const one: plan.Plan = .{
        .install = &.{ .{ .name = "b", .version = "1-r1", .named = true }, .{ .name = "a", .version = "2-r1" } },
        .upgrade = &.{.{ .name = "c", .version = "3-r2", .from = "3-r1" }},
        .remove = &.{},
        .download = 10,
        .disk = null,
    };
    var two = one;
    two.install = &.{ .{ .name = "a", .version = "2-r1", .named = true }, .{ .name = "b", .version = "1-r1" } };
    const d1 = (try digest(a, .install, one)).?;
    try testing.expect(std.mem.startsWith(u8, d1, "sha256:"));
    try testing.expectEqualStrings(d1, (try digest(a, .install, two)).?);
    var moved = one;
    moved.upgrade = &.{.{ .name = "c", .version = "3-r3", .from = "3-r1" }};
    try testing.expect(!std.mem.eql(u8, d1, (try digest(a, .install, moved)).?));
    try testing.expect(!std.mem.eql(u8, d1, (try digest(a, .remove, one)).?));
    const empty: plan.Plan = .{ .install = &.{}, .upgrade = &.{}, .remove = &.{}, .download = 0, .disk = null };
    try testing.expect((try digest(a, .install, empty)) == null);
}
