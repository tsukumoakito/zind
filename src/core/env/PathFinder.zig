const std = @import("std");
const mem = std.mem;
const process = std.process;
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;

pub const PathError = error{
    ExecutablePathNotFound,
    NormalizationFailed,
    OutOfMemory,
    ZigBinaryNotFound,
    StdZigNotFound,
    EntryPointNotFound,
} || process.CurrentPathAllocError;

pub fn findZigInPath(allocator: mem.Allocator, io: Io, environ_map: *const process.Environ.Map) PathError![]const u8 {
    const path_env = environ_map.get("PATH") orelse return error.ZigBinaryNotFound;

    var it = mem.tokenizeScalar(u8, path_env, Dir.path.delimiter);
    while (it.next()) |dir| {
        const joined = Dir.path.join(allocator, &.{ dir, "zig" }) catch continue;
        defer allocator.free(joined);

        if (resolveRealPath(allocator, io, joined)) |real_path| {
            const st = Dir.statFile(Dir.cwd(), io, real_path, .{}) catch {
                allocator.free(real_path);
                continue;
            };
            if (st.kind == .file) return real_path;
            allocator.free(real_path);
        } else |_| continue;
    }

    return error.ZigBinaryNotFound;
}

pub fn findZigNearStd(allocator: mem.Allocator, io: Io, std_path: []const u8) ?[]const u8 {
    const strategies = [_][]const []const u8{
        &.{ std_path, "..", "..", "zig" },
        &.{ std_path, "..", "..", "bin", "zig" },
    };

    for (strategies) |nodes| {
        const candidate = Dir.path.resolve(allocator, nodes) catch continue;
        defer allocator.free(candidate);

        if (resolveRealPath(allocator, io, candidate)) |real_path| {
            const st = Dir.statFile(Dir.cwd(), io, real_path, .{}) catch {
                allocator.free(real_path);
                continue;
            };
            if (st.kind == .file) return real_path;
            allocator.free(real_path);
        } else |_| continue;
    }

    return null;
}

pub fn findStdFolder(allocator: mem.Allocator, io: Io, base_path: []const u8) ?[]const u8 {
    if (mem.endsWith(u8, base_path, "std.zig")) {
        const dir = Dir.path.dirname(base_path) orelse return null;
        return resolveRealPath(allocator, io, dir) catch null;
    }

    const strategies = [_][]const []const u8{
        &.{ base_path, "lib", "std", "std.zig" },
        &.{ base_path, "std", "std.zig" },
        &.{ base_path, "std.zig" },
    };

    for (strategies) |nodes| {
        const full_path = Dir.path.join(allocator, nodes) catch continue;
        defer allocator.free(full_path);

        Dir.accessAbsolute(io, full_path, .{}) catch continue;

        const std_dir = Dir.path.dirname(full_path) orelse continue;
        return resolveRealPath(allocator, io, std_dir) catch null;
    }

    return null;
}

pub fn findEntryPoint(
    allocator: mem.Allocator,
    io: Io,
    base_path: []const u8,
    direct_file: ?[]const u8,
) PathError![:0]const u8 {
    if (direct_file) |df| {
        return try resolveRealPath(allocator, io, df);
    }

    const fallbacks = [_][]const u8{ "std.zig", "root.zig", "main.zig" };
    for (fallbacks) |filename| {
        const joined = Dir.path.join(allocator, &.{ base_path, filename }) catch continue;
        defer allocator.free(joined);

        if (resolveRealPath(allocator, io, joined)) |real_path| {
            Dir.accessAbsolute(io, real_path, .{}) catch {
                allocator.free(real_path);
                continue;
            };
            return real_path;
        } else |_| continue;
    }

    return error.EntryPointNotFound;
}

pub fn resolveAbsolutePath(allocator: mem.Allocator, io: Io, raw_path: []const u8) PathError![]const u8 {
    if (Dir.path.isAbsolute(raw_path)) {
        return allocator.dupe(u8, raw_path) catch error.OutOfMemory;
    }

    const cwd = try process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);

    return Dir.path.resolve(allocator, &.{ cwd, raw_path }) catch error.NormalizationFailed;
}

pub fn resolveRealPath(allocator: mem.Allocator, io: Io, raw_path: []const u8) PathError![:0]const u8 {
    return Dir.realPathFileAlloc(Dir.cwd(), io, raw_path, allocator) catch {
        return error.NormalizationFailed;
    };
}
