//! Package repositories.
//!
//! A repository is a directory (served over HTTPS or HTTP, or read from a
//! local path) holding package files, `repo.zon` describing them, and
//! `repo.zon.sig`, an Ed25519 signature over the exact bytes of the index. The
//! index records the SHA-256 of every package, so trusting the signature is
//! enough to trust every package file, however it was transported.
//!
//! What HTTPS adds is what a signature cannot give. An old index stays validly
//! signed forever, so someone on the network path could keep serving one and
//! hold a machine back from security fixes; with HTTPS only the server can.
//! It also keeps what a machine installs from being read off the wire.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Ed25519 = std.crypto.sign.Ed25519;
const manifest_mod = @import("manifest.zig");
const archive = @import("archive.zig");
const db = @import("db.zig");
const seal = @import("seal.zig");
const Version = @import("solver/version.zig").Version;

pub const index_name = "repo.zon";
pub const signature_name = "repo.zon.sig";
pub const config_path = "etc/dave/repos.zon";
pub const keys_path = "etc/dave/keys";
const max_index_bytes = 256 * 1024 * 1024;

pub const IndexEntry = struct {
    name: []const u8,
    version: []const u8,
    arch: []const u8 = "x86_64",
    description: []const u8 = "",
    depends: []const []const u8 = &.{},
    conflicts: []const []const u8 = &.{},
    filename: []const u8,
    /// Of the package file, which is what is downloaded.
    size: u64,
    sha256: []const u8,
    license: []const u8 = "",
    /// What its files take once installed. Indexes written by dave 0.2 and
    /// earlier do not say.
    installed_size: ?u64 = null,
};

pub const Index = struct {
    format: u32 = 1,
    packages: []const IndexEntry = &.{},
};

pub const RepoConfig = struct {
    name: []const u8,
    /// `https://host/path`, `http://host/path` or a local directory.
    url: []const u8,
};

pub const Config = struct {
    repos: []const RepoConfig = &.{},
};

/// An index entry together with where to fetch it from.
pub const Candidate = struct {
    entry: IndexEntry,
    repo_url: []const u8,
    /// The repository's name in the configuration.
    repo_name: []const u8 = "",
};

// ---------------------------------------------------------------------------
// Keys and signatures
// ---------------------------------------------------------------------------

pub const PublicKey = [Ed25519.PublicKey.encoded_length]u8;
pub const secret_hex_len = Ed25519.SecretKey.encoded_length * 2;
pub const public_hex_len = Ed25519.PublicKey.encoded_length * 2;
pub const signature_hex_len = Ed25519.Signature.encoded_length * 2;

pub const GeneratedKey = struct {
    secret_hex: [secret_hex_len]u8,
    public_hex: [public_hex_len]u8,
};

pub fn generateKey(io: Io) GeneratedKey {
    const pair = Ed25519.KeyPair.generate(io);
    return .{
        .secret_hex = std.fmt.bytesToHex(pair.secret_key.toBytes(), .lower),
        .public_hex = std.fmt.bytesToHex(pair.public_key.toBytes(), .lower),
    };
}

pub fn sign(secret_hex: []const u8, message: []const u8) ![signature_hex_len]u8 {
    var secret: [Ed25519.SecretKey.encoded_length]u8 = undefined;
    const trimmed = std.mem.trim(u8, secret_hex, " \t\r\n");
    if (trimmed.len != secret_hex_len) return error.InvalidKey;
    _ = std.fmt.hexToBytes(&secret, trimmed) catch return error.InvalidKey;
    const pair = Ed25519.KeyPair.fromSecretKey(Ed25519.SecretKey.fromBytes(secret) catch return error.InvalidKey) catch
        return error.InvalidKey;
    const signature = pair.sign(message, null) catch return error.InvalidKey;
    return std.fmt.bytesToHex(signature.toBytes(), .lower);
}

pub fn parsePublicKey(text: []const u8) !PublicKey {
    var key: PublicKey = undefined;
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len != public_hex_len) return error.InvalidKey;
    _ = std.fmt.hexToBytes(&key, trimmed) catch return error.InvalidKey;
    return key;
}

/// Succeeds if `signature_hex` is a valid signature of `message` by any of the
/// trusted keys.
pub fn verify(signature_hex: []const u8, message: []const u8, trusted: []const PublicKey) error{BadSignature}!void {
    var raw: [Ed25519.Signature.encoded_length]u8 = undefined;
    const trimmed = std.mem.trim(u8, signature_hex, " \t\r\n");
    if (trimmed.len != signature_hex_len) return error.BadSignature;
    _ = std.fmt.hexToBytes(&raw, trimmed) catch return error.BadSignature;
    const signature = Ed25519.Signature.fromBytes(raw);
    for (trusted) |key_bytes| {
        const key = Ed25519.PublicKey.fromBytes(key_bytes) catch continue;
        signature.verify(message, key) catch continue;
        return;
    }
    return error.BadSignature;
}

/// Reads every `*.pub` file in the root's key directory.
pub fn loadTrustedKeys(arena: Allocator, io: Io, root: Io.Dir) ![]PublicKey {
    var keys: std.ArrayList(PublicKey) = .empty;
    var dir = root.openDir(io, keys_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return keys.items,
        else => return err,
    };
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".pub")) continue;
        const text = try dir.readFileAlloc(io, entry.name, arena, .limited(4096));
        try keys.append(arena, parsePublicKey(text) catch continue);
    }
    return keys.items;
}

pub fn loadConfig(arena: Allocator, io: Io, root: Io.Dir) !Config {
    const text = root.readFileAlloc(io, config_path, arena, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    return manifest_mod.parseZon(Config, arena, text) catch |err| switch (err) {
        error.InvalidManifest => error.InvalidConfig,
        else => |e| e,
    };
}

// ---------------------------------------------------------------------------
// Building a repository
// ---------------------------------------------------------------------------

/// Scans `dir` for package files and writes `repo.zon`, signing it when a
/// secret key is given. Returns the number of packages indexed.
pub fn writeIndex(gpa: Allocator, arena: Allocator, io: Io, dir: Io.Dir, secret_hex: ?[]const u8) !usize {
    var entries: std.ArrayList(IndexEntry) = .empty;
    var it = dir.iterate();
    while (try it.next(io)) |e| {
        if (e.kind != .file or !std.mem.endsWith(u8, e.name, ".dave")) continue;
        const filename = try arena.dupe(u8, e.name);
        const m = try archive.readManifestOf(gpa, arena, io, dir, filename);
        const st = try dir.statFile(io, filename, .{});
        const digest = try archive.hashFile(io, dir, filename);
        try entries.append(arena, .{
            .name = m.name,
            .version = m.version,
            .arch = m.arch,
            .description = m.description,
            .depends = m.depends,
            .conflicts = m.conflicts,
            .filename = filename,
            .size = st.size,
            .sha256 = try arena.dupe(u8, &digest),
            .license = m.license,
            .installed_size = m.installedSize(),
        });
    }
    std.mem.sort(IndexEntry, entries.items, {}, struct {
        fn lessThan(_: void, a: IndexEntry, b: IndexEntry) bool {
            return std.mem.order(u8, a.filename, b.filename) == .lt;
        }
    }.lessThan);

    var text: Io.Writer.Allocating = .init(arena);
    try std.zon.stringify.serialize(Index{ .packages = entries.items }, .{ .emit_default_optional_fields = false }, &text.writer);
    try text.writer.writeByte('\n');
    try db.writeAtomic(arena, io, dir, index_name, text.written());
    if (secret_hex) |secret| {
        const signature = try sign(secret, text.written());
        try db.writeAtomic(arena, io, dir, signature_name, &signature);
    } else {
        dir.deleteFile(io, signature_name) catch {};
    }
    return entries.items.len;
}

// The manifest describes metadata, not ELF headers. Recognize the usual
// library names, leaving set-id and file-capability checks independent.
fn sharedObject(path: []const u8) bool {
    const name = std.fs.path.basename(path);
    if (std.mem.endsWith(u8, name, ".so")) return true;
    const pos = std.mem.lastIndexOf(u8, name, ".so.") orelse return false;
    var parts = std.mem.splitScalar(u8, name[pos + 4 ..], '.');
    while (parts.next()) |part| {
        if (part.len == 0) return false;
        for (part) |c| if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

const Findings = struct {
    lines: std.ArrayList([]const u8) = .empty,

    fn add(self: *Findings, arena: Allocator, name: []const u8, path: []const u8, reason: []const u8) !void {
        try self.lines.append(arena, try std.fmt.allocPrint(arena, "{s}: {s}: {s}", .{ name, path, reason }));
    }
};

fn auditManifest(m: manifest_mod.Manifest, scratch: Allocator, arena: Allocator, findings: *Findings) !void {
    // Validate even unmatched and shadowed declarations.
    var operations_valid = true;
    for (m.operations) |declaration| {
        _ = seal.operationsText(scratch, &.{.{ .allow = declaration.allow }}, "") catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidOperation => {
                operations_valid = false;
                const path = if (declaration.programs.len > 0) declaration.programs[0] else "-";
                try findings.add(arena, m.name, path, "invalid operations");
            },
        };
    }
    for (m.files) |f| {
        if (f.kind != .file or f.config) continue;
        if (f.seal == null and f.verity == null) {
            try findings.add(arena, m.name, f.path, "not sealed");
        } else if (f.seal == null or f.verity == null) {
            try findings.add(arena, m.name, f.path, "incomplete seal");
        } else if (seal.parseSignature(f.seal.?) == null or seal.parseDigest(f.verity.?) == null) {
            try findings.add(arena, m.name, f.path, "malformed seal");
        }

        const privileged = (f.mode & 0o111 != 0 and !sharedObject(f.path)) or (f.mode & 0o6000 != 0) or f.caps != null;
        if (!operations_valid or !privileged) continue;
        const ops = try seal.operationsText(scratch, m.operations, f.path);
        if (std.mem.eql(u8, ops, seal.undeclared))
            try findings.add(arena, m.name, f.path, "undeclared privileged program");
    }
}

/// Report the latest releases' seal metadata and declarations. Signatures
/// cannot be verified here without a trusted public key. Baselines are saved
/// audit output: only exact finding lines match, across package upgrades.
pub fn audit(gpa: Allocator, arena: Allocator, io: Io, dir: Io.Dir, baseline: []const u8, out: *Io.Writer) !usize {
    var known: std.StringHashMapUnmanaged(void) = .empty;
    var lines = std.mem.tokenizeAny(u8, baseline, "\r\n");
    while (lines.next()) |line| try known.put(arena, line, {});

    const Release = struct { version: Version, findings: Findings = .{} };
    var latest: std.StringHashMapUnmanaged(Release) = .empty;
    var report: Findings = .{};
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".dave")) continue;
        var package_arena = std.heap.ArenaAllocator.init(gpa);
        defer package_arena.deinit();
        const scratch = package_arena.allocator();
        const m = archive.readManifestOf(gpa, scratch, io, dir, entry.name) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try report.add(arena, entry.name, "-", try std.fmt.allocPrint(scratch, "unreadable package ({t})", .{err}));
                continue;
            },
        };
        var v = Version.parse(m.version) catch {
            try report.add(arena, entry.name, "-", "invalid package version");
            continue;
        };
        const release = try latest.getOrPut(arena, m.name);
        if (release.found_existing) {
            switch (v.order(release.value_ptr.version)) {
                .lt => continue,
                .eq => {
                    // Repositories may carry the same release for several architectures.
                    try auditManifest(m, scratch, arena, &release.value_ptr.findings);
                    continue;
                },
                .gt => {},
            }
        } else {
            release.key_ptr.* = try arena.dupe(u8, m.name);
        }
        v.upstream = try arena.dupe(u8, v.upstream);
        release.value_ptr.* = .{ .version = v };
        try auditManifest(m, scratch, arena, &release.value_ptr.findings);
    }
    var releases = latest.valueIterator();
    while (releases.next()) |release| try report.lines.appendSlice(arena, release.findings.lines.items);
    std.mem.sort([]const u8, report.lines.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);
    var count: usize = 0;
    for (report.lines.items) |line| {
        if (known.contains(line)) continue;
        try out.print("{s}\n", .{line});
        count += 1;
    }
    return count;
}

// ---------------------------------------------------------------------------
// Using repositories
// ---------------------------------------------------------------------------

fn isRemote(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "https://") or std.mem.startsWith(u8, url, "http://");
}

/// Told how many bytes of a file have arrived so far.
pub const ByteProgress = struct {
    context: *anyopaque,
    report: *const fn (context: *anyopaque, bytes: u64) void,
};

/// What a failed download was, for saying so.
pub const FetchDiagnostic = struct {
    url: []const u8 = "",
    /// Set when the server answered, but not with the file.
    status: ?std.http.Status = null,
};

pub const FetchOptions = struct {
    progress: ?ByteProgress = null,
    diag: ?*FetchDiagnostic = null,
};

/// Counts what passes through a writer (std.Io.Writer.Hashed's hasher).
const Counter = struct {
    bytes: u64 = 0,
    progress: ?ByteProgress = null,

    pub fn update(c: *Counter, data: []const u8) void {
        c.bytes += data.len;
        if (c.progress) |p| p.report(p.context, c.bytes);
    }
};

/// Copies or downloads `<base>/<name>` to `dest_dir/dest_name`, atomically.
///
/// An HTTPS server must present a certificate for its host name that chains to
/// a certificate in the store of the system dave is running on (on joe,
/// `/etc/pki/tls/certs/ca-bundle.crt`, from make-ca). That is the running
/// system's store even when dave works on another root with `--root`.
pub fn fetch(gpa: Allocator, arena: Allocator, io: Io, base: []const u8, name: []const u8, dest_dir: Io.Dir, dest_name: []const u8, options: FetchOptions) !void {
    const tmp = try std.fmt.allocPrint(arena, "{s}.partial", .{dest_name});
    errdefer dest_dir.deleteFile(io, tmp) catch {};
    if (isRemote(base)) {
        const url = try std.fmt.allocPrint(arena, "{s}/{s}", .{ std.mem.trimEnd(u8, base, "/"), name });
        if (options.diag) |d| d.* = .{ .url = url };
        var file = try dest_dir.createFile(io, tmp, .{});
        defer file.close(io);
        var buf: [64 * 1024]u8 = undefined;
        var fw = file.writer(io, &buf);
        var count_buf: [16 * 1024]u8 = undefined;
        var counted = Io.Writer.Hashed(Counter).initHasher(&fw.interface, .{ .progress = options.progress }, &count_buf);
        var client: std.http.Client = .{ .allocator = gpa, .io = io };
        defer client.deinit();
        const result = client.fetch(.{ .location = .{ .url = url }, .response_writer = &counted.writer, .keep_alive = false }) catch |e| {
            // Writing failed: the file writer knows why (a full disk).
            if (e == error.WriteFailed) return fw.err orelse e;
            return e;
        };
        if (result.status != .ok) {
            if (options.diag) |d| d.status = result.status;
            return error.DownloadFailed;
        }
        counted.writer.flush() catch return fw.err orelse error.WriteFailed;
        fw.interface.flush() catch return fw.err orelse error.WriteFailed;
        try file.sync(io);
    } else {
        if (options.diag) |d| d.* = .{ .url = base };
        var src = Io.Dir.cwd().openDir(io, base, .{}) catch return error.RepositoryNotFound;
        defer src.close(io);
        try src.copyFile(name, dest_dir, tmp, io, .{});
        if (options.progress) |p| {
            const st = try dest_dir.statFile(io, tmp, .{});
            p.report(p.context, st.size);
        }
    }
    try dest_dir.rename(tmp, dest_dir, dest_name, io);
}

/// Downloads and verifies every configured repository's index into `cache`,
/// and returns all candidates. An index that fails verification is discarded
/// and the previously cached one, if any, is left in place.
pub fn refresh(gpa: Allocator, arena: Allocator, io: Io, config: Config, trusted: []const PublicKey, cache: Io.Dir) ![]Candidate {
    for (config.repos) |r| try refreshRepo(gpa, arena, io, r, trusted, cache, .{});
    return loadCached(arena, io, config, trusted, cache);
}

/// Downloads and verifies one repository's index into `cache/<name>`.
pub fn refreshRepo(gpa: Allocator, arena: Allocator, io: Io, r: RepoConfig, trusted: []const PublicKey, cache: Io.Dir, options: FetchOptions) !void {
    if (!manifest_mod.validName(r.name)) return error.InvalidConfig;
    try cache.createDirPath(io, r.name);
    var dir = try cache.openDir(io, r.name, .{});
    defer dir.close(io);
    try fetch(gpa, arena, io, r.url, index_name, dir, index_name ++ ".new", options);
    try fetch(gpa, arena, io, r.url, signature_name, dir, signature_name ++ ".new", .{ .diag = options.diag });
    const text = try dir.readFileAlloc(io, index_name ++ ".new", arena, .limited(max_index_bytes));
    const signature = try dir.readFileAlloc(io, signature_name ++ ".new", arena, .limited(4096));
    verify(signature, text, trusted) catch |err| {
        dir.deleteFile(io, index_name ++ ".new") catch {};
        dir.deleteFile(io, signature_name ++ ".new") catch {};
        return err;
    };
    try dir.rename(index_name ++ ".new", dir, index_name, io);
    try dir.rename(signature_name ++ ".new", dir, signature_name, io);
}

/// Loads the cached indexes, re-verifying their signatures.
pub fn loadCached(arena: Allocator, io: Io, config: Config, trusted: []const PublicKey, cache: Io.Dir) ![]Candidate {
    var out: std.ArrayList(Candidate) = .empty;
    for (config.repos) |r| {
        const index_path = try std.fmt.allocPrint(arena, "{s}/" ++ index_name, .{r.name});
        const sig_path = try std.fmt.allocPrint(arena, "{s}/" ++ signature_name, .{r.name});
        const text = cache.readFileAlloc(io, index_path, arena, .limited(max_index_bytes)) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        const signature = cache.readFileAlloc(io, sig_path, arena, .limited(4096)) catch return error.BadSignature;
        try verify(signature, text, trusted);
        const index = manifest_mod.parseZon(Index, arena, text) catch return error.InvalidIndex;
        for (index.packages) |p| {
            if (!manifest_mod.validName(p.name)) return error.InvalidIndex;
            if (std.mem.indexOfScalar(u8, p.filename, '/') != null or std.mem.startsWith(u8, p.filename, ".")) return error.InvalidIndex;
            try out.append(arena, .{ .entry = p, .repo_url = r.url, .repo_name = r.name });
        }
    }
    return out.items;
}

pub const packages_dir = "pkgs";

/// Makes sure the package file for `c` is in `cache/pkgs`, verified against
/// the signed index, and returns its path relative to `cache`.
pub fn ensurePackage(gpa: Allocator, arena: Allocator, io: Io, c: Candidate, cache: Io.Dir, options: FetchOptions) ![]const u8 {
    try cache.createDirPath(io, packages_dir);
    const rel = try std.fmt.allocPrint(arena, packages_dir ++ "/{s}", .{c.entry.filename});
    if (try matches(io, cache, rel, c.entry)) return rel;
    var dir = try cache.openDir(io, packages_dir, .{});
    defer dir.close(io);
    try fetch(gpa, arena, io, c.repo_url, c.entry.filename, dir, c.entry.filename, options);
    if (!try matches(io, cache, rel, c.entry)) {
        cache.deleteFile(io, rel) catch {};
        return error.ChecksumMismatch;
    }
    return rel;
}

/// Whether a file of the right size for `entry` is in the cache already: a
/// cheap guess at what is left to download, for saying so. ensurePackage
/// checks properly.
pub fn isCached(io: Io, cache: Io.Dir, entry: IndexEntry) bool {
    var buf: [512]u8 = undefined;
    const rel = std.fmt.bufPrint(&buf, packages_dir ++ "/{s}", .{entry.filename}) catch return false;
    const st = cache.statFile(io, rel, .{}) catch return false;
    return st.size == entry.size;
}

fn matches(io: Io, cache: Io.Dir, rel: []const u8, entry: IndexEntry) !bool {
    const st = cache.statFile(io, rel, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    if (st.size != entry.size) return false;
    const digest = try archive.hashFile(io, cache, rel);
    return std.mem.eql(u8, &digest, entry.sha256);
}

const testing = std.testing;

fn writeAuditTestPackage(arena: Allocator, io: Io, dir: Io.Dir, filename: []const u8, m: manifest_mod.Manifest) !void {
    var text: Io.Writer.Allocating = .init(arena);
    try m.write(&text.writer);
    var file = try dir.createFile(io, filename, .{});
    defer file.close(io);
    var child = try std.process.spawn(io, .{
        .argv = &.{ "zstd", "-q", "-c" },
        .stdin = .pipe,
        .stdout = .{ .file = file },
    });
    errdefer child.kill(io);
    var buf: [4096]u8 = undefined;
    var pipe = child.stdin.?.writer(io, &buf);
    var tar: std.tar.Writer = .{ .underlying_writer = &pipe.interface };
    try tar.writeFileBytes(archive.manifest_member, text.written(), .{ .mode = 0o644 });
    try tar.finishPedantically();
    try pipe.interface.flush();
    child.stdin.?.close(io);
    child.stdin = null;
    if (!(try child.wait(io)).success()) return error.CompressionFailed;
}

test "audit accepts sealed declarations and finds undeclared programs" {
    const io = testing.io;
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const key = try seal.SigningKey.parse(&seal.generateKey(io).secret_hex);

    try tmp.dir.createDirPath(io, "clean-stage");
    var clean_stage = try tmp.dir.openDir(io, "clean-stage", .{ .iterate = true });
    defer clean_stage.close(io);
    try clean_stage.writeFile(io, .{ .sub_path = "data", .data = "clean\n" });
    _ = try archive.pack(arena, io, .{
        .meta = .{ .name = "clean", .version = "1-r1", .operations = &.{.{ .allow = &.{"none"} }} },
        .src = clean_stage,
        .out_dir = tmp.dir,
        .code_key = key,
    });
    var clean_report: Io.Writer.Allocating = .init(arena);
    try testing.expectEqual(@as(usize, 0), try audit(testing.allocator, arena, io, tmp.dir, "", &clean_report.writer));
    try testing.expectEqualStrings("", clean_report.written());

    try tmp.dir.createDirPath(io, "undeclared-stage");
    var undeclared_stage = try tmp.dir.openDir(io, "undeclared-stage", .{ .iterate = true });
    defer undeclared_stage.close(io);
    try undeclared_stage.writeFile(io, .{ .sub_path = "program", .data = "#!/bin/sh\n" });
    try undeclared_stage.setFilePermissions(io, "program", .fromMode(0o755), .{});
    try undeclared_stage.writeFile(io, .{ .sub_path = "data", .data = "not a program\n" });
    _ = try archive.pack(arena, io, .{
        .meta = .{ .name = "undeclared", .version = "1-r1" },
        .src = undeclared_stage,
        .out_dir = tmp.dir,
        .code_key = key,
    });
    var report: Io.Writer.Allocating = .init(arena);
    try testing.expectEqual(@as(usize, 1), try audit(testing.allocator, arena, io, tmp.dir, "", &report.writer));
    const expected = "undeclared: program: undeclared privileged program\n";
    try testing.expectEqualStrings(expected, report.written());
}

test "audit checks the latest release and keeps seal and privilege checks on libraries" {
    const io = testing.io;
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    // Use manifest identities even when filenames sort in the opposite order.
    for ([_][]const u8{ "1.9-r20", "1.10-r2" }, 0..) |version, i| {
        try writeAuditTestPackage(arena, io, tmp.dir, if (i == 0) "z.dave" else "y.dave", .{
            .name = "tool",
            .version = version,
            .files = &.{.{ .path = "obsolete" }},
        });
    }
    try writeAuditTestPackage(arena, io, tmp.dir, "a.dave", .{
        .name = "tool",
        .version = "1.10-r10",
        .files = &.{
            .{ .path = "lib.so", .mode = 0o755 },
            .{ .path = "lib.so.1.2", .mode = 0o755 },
            .{ .path = "setid.so", .mode = 0o4755 },
            .{ .path = "cap.so.1", .caps = "01" },
            .{ .path = "lib.so.d/program", .mode = 0o755 },
            .{ .path = "tool.so.sh", .mode = 0o755 },
        },
    });
    const baseline = "tool: lib.so: not sealed\r\n" ++
        "tool: tool.so.sh: not sealed\n" ++
        "2 security problem(s) found.\n";
    var report: Io.Writer.Allocating = .init(arena);
    try testing.expectEqual(@as(usize, 8), try audit(testing.allocator, arena, io, tmp.dir, baseline, &report.writer));
    try testing.expectEqualStrings(
        "tool: cap.so.1: not sealed\n" ++
            "tool: cap.so.1: undeclared privileged program\n" ++
            "tool: lib.so.1.2: not sealed\n" ++
            "tool: lib.so.d/program: not sealed\n" ++
            "tool: lib.so.d/program: undeclared privileged program\n" ++
            "tool: setid.so: not sealed\n" ++
            "tool: setid.so: undeclared privileged program\n" ++
            "tool: tool.so.sh: undeclared privileged program\n",
        report.written(),
    );
}

test "audit detects absent and malformed seals and invalid operations" {
    const io = testing.io;
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "unsigned-stage");
    var stage = try tmp.dir.openDir(io, "unsigned-stage", .{ .iterate = true });
    defer stage.close(io);
    try stage.writeFile(io, .{ .sub_path = "data", .data = "unsigned\n" });
    _ = try archive.pack(arena, io, .{
        .meta = .{ .name = "unsigned", .version = "1-r1", .operations = &.{.{ .allow = &.{"none"} }} },
        .src = stage,
        .out_dir = tmp.dir,
    });

    const digest: [seal.digest_len * 2]u8 = @splat('0');
    const signature: [seal.signature_len * 2]u8 = @splat('0');
    try writeAuditTestPackage(arena, io, tmp.dir, "malformed.dave", .{
        .name = "malformed",
        .version = "1-r1",
        .operations = &.{.{ .allow = &.{"none"} }},
        .files = &.{.{ .path = "bad", .verity = &digest, .seal = "not hex" }},
    });
    try writeAuditTestPackage(arena, io, tmp.dir, "invalid.dave", .{
        .name = "invalid",
        .version = "1-r1",
        .operations = &.{.{ .allow = &.{"not-an-operation"} }},
        .files = &.{.{ .path = "bad", .verity = &digest, .seal = &signature }},
    });
    try writeAuditTestPackage(arena, io, tmp.dir, "reserved.dave", .{
        .name = "reserved",
        .version = "1-r1",
        .operations = &.{.{ .programs = &.{"not-installed"}, .allow = &.{"undeclared"} }},
        .files = &.{.{ .path = "data", .verity = &digest, .seal = &signature }},
    });

    var report: Io.Writer.Allocating = .init(arena);
    try testing.expectEqual(@as(usize, 4), try audit(testing.allocator, arena, io, tmp.dir, "", &report.writer));
    const expected = "invalid: -: invalid operations\n" ++
        "malformed: bad: malformed seal\n" ++
        "reserved: not-installed: invalid operations\n" ++
        "unsigned: data: not sealed\n";
    try testing.expectEqualStrings(expected, report.written());
}

test "sign and verify" {
    const key = generateKey(testing.io);
    const other = generateKey(testing.io);
    const signature = try sign(&key.secret_hex, "the index");
    const trusted = [_]PublicKey{try parsePublicKey(&key.public_hex)};
    const untrusted = [_]PublicKey{try parsePublicKey(&other.public_hex)};

    try verify(&signature, "the index", &trusted);
    try testing.expectError(error.BadSignature, verify(&signature, "the index, tampered", &trusted));
    try testing.expectError(error.BadSignature, verify(&signature, "the index", &untrusted));
    try testing.expectError(error.BadSignature, verify(&signature, "the index", &.{}));
    try testing.expectError(error.BadSignature, verify("garbage", "the index", &trusted));
    try testing.expectError(error.InvalidKey, sign("not a key", "x"));
}

test "index, refresh from a local repository, and fetch a package" {
    const io = testing.io;
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "repo");
    try tmp.dir.createDirPath(io, "stage/usr/bin");
    try tmp.dir.createDirPath(io, "cache");
    var repo_dir = try tmp.dir.openDir(io, "repo", .{ .iterate = true });
    defer repo_dir.close(io);
    var stage = try tmp.dir.openDir(io, "stage", .{ .iterate = true });
    defer stage.close(io);
    var cache = try tmp.dir.openDir(io, "cache", .{});
    defer cache.close(io);
    try stage.writeFile(io, .{ .sub_path = "usr/bin/hello", .data = "hello\n" });
    _ = try archive.pack(arena, io, .{ .meta = .{ .name = "hello", .version = "1.0-r1", .license = "MIT", .depends = &.{"glibc"} }, .src = stage, .out_dir = repo_dir });

    const key = generateKey(io);
    try testing.expectEqual(@as(usize, 1), try writeIndex(testing.allocator, arena, io, repo_dir, &key.secret_hex));

    var path_buf: [4096]u8 = undefined;
    const n = try repo_dir.realPath(io, &path_buf);
    const config: Config = .{ .repos = &.{.{ .name = "test", .url = path_buf[0..n] }} };
    const trusted = [_]PublicKey{try parsePublicKey(&key.public_hex)};

    const candidates = try refresh(testing.allocator, arena, io, config, &trusted, cache);
    try testing.expectEqual(@as(usize, 1), candidates.len);
    try testing.expectEqualStrings("hello", candidates[0].entry.name);
    try testing.expectEqualStrings("glibc", candidates[0].entry.depends[0]);
    try testing.expectEqualStrings("MIT", candidates[0].entry.license);
    try testing.expectEqual(@as(?u64, 6), candidates[0].entry.installed_size);
    try testing.expectEqualStrings("test", candidates[0].repo_name);
    try testing.expect(!isCached(io, cache, candidates[0].entry));

    const Seen = struct {
        bytes: u64 = 0,
        fn report(ctx: *anyopaque, bytes: u64) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.bytes = bytes;
        }
    };
    var seen: Seen = .{};
    const rel = try ensurePackage(testing.allocator, arena, io, candidates[0], cache, .{ .progress = .{ .context = &seen, .report = Seen.report } });
    try testing.expectEqual(candidates[0].entry.size, seen.bytes);
    try testing.expect(isCached(io, cache, candidates[0].entry));
    const m = try archive.readManifestOf(testing.allocator, arena, io, cache, rel);
    try testing.expectEqualStrings("1.0-r1", m.version);

    // An index signed by an unknown key is refused, and the good cached copy survives.
    const stranger = generateKey(io);
    _ = try writeIndex(testing.allocator, arena, io, repo_dir, &stranger.secret_hex);
    try testing.expectError(error.BadSignature, refresh(testing.allocator, arena, io, config, &trusted, cache));
    try testing.expectEqual(@as(usize, 1), (try loadCached(arena, io, config, &trusted, cache)).len);

    // A package altered after the index was signed is refused.
    _ = try writeIndex(testing.allocator, arena, io, repo_dir, &key.secret_hex);
    try cache.deleteFile(io, rel);
    try repo_dir.writeFile(io, .{ .sub_path = candidates[0].entry.filename, .data = "tampered" });
    try testing.expectError(error.ChecksumMismatch, ensurePackage(testing.allocator, arena, io, candidates[0], cache, .{}));
}

test "an index from an older dave is read" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const index = try manifest_mod.parseZon(Index, arena_state.allocator(),
        \\.{ .packages = .{ .{ .name = "hello", .version = "1.0-r1", .filename = "hello-1.0-r1-x86_64.dave", .size = 10, .sha256 = "ab" } } }
    );
    try testing.expectEqual(@as(?u64, null), index.packages[0].installed_size);
    try testing.expectEqualStrings("", index.packages[0].license);
}
