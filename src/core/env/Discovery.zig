const std = @import("std");
const mem = std.mem;
const process = std.process;
const Io = std.Io;
const Dir = Io.Dir;
const Writer = Io.Writer;

const BinaryParser = @import("../system/BinaryParser.zig");
const CLI = @import("CLI.zig");
const PathFinder = @import("PathFinder.zig");

pub const Environment = struct {
    std_path: []const u8,
    root_path: []const u8,
    zig_version: []const u8,
    mode: CLI.Mode,
    allocator: mem.Allocator,

    pub fn deinit(self: *Environment) void {
        self.allocator.free(self.std_path);
        self.allocator.free(self.root_path);
        self.allocator.free(self.zig_version);
    }
};

pub const DiscoveryError = error{
    StdPathNotFound,
    RootPathNotFound,
    ZigBinaryNotFound,
    VersionDetectionFailed,
    InvalidProjectRoot,
} || PathFinder.PathError || BinaryParser.ParseError || process.CurrentPathAllocError || mem.Allocator.Error || Writer.Error;

pub fn discover(
    allocator: mem.Allocator,
    io: Io,
    writer: *Writer,
    environ_map: *const process.Environ.Map,
    config: CLI.Config,
) DiscoveryError!Environment {
    const resolved_root = if (config.root_path) |p|
        try PathFinder.resolveAbsolutePath(allocator, io, p)
    else
        try process.currentPathAlloc(io, allocator);

    if (config.root_path != null or config.mode == .project) {
        validateProjectRoot(allocator, io, resolved_root) catch |err| {
            try writer.print("[ERROR] Root Path Validation FAILED: {s}\n", .{resolved_root});
            return err;
        };
    }

    const raw_std = if (config.std_path) |p| blk: {
        const abs_p = try PathFinder.resolveAbsolutePath(allocator, io, p);
        if (PathFinder.findStdFolder(allocator, io, abs_p)) |folder| {
            allocator.free(abs_p);
            break :blk folder;
        }
        break :blk abs_p;
    } else Inferred: {
        const cwd = try process.currentPathAlloc(io, allocator);
        defer allocator.free(cwd);
        if (PathFinder.findStdFolder(allocator, io, cwd)) |path| break :Inferred path;

        const zig_path = try PathFinder.findZigInPath(allocator, io, environ_map);
        defer allocator.free(zig_path);
        const zig_dir = Dir.path.dirname(zig_path) orelse return error.NormalizationFailed;
        if (PathFinder.findStdFolder(allocator, io, zig_dir)) |path| break :Inferred path;

        return error.StdPathNotFound;
    };

    const resolved_std = try PathFinder.resolveRealPath(allocator, io, raw_std);
    allocator.free(raw_std);

    const zig_exe_path = if (PathFinder.findZigNearStd(allocator, io, resolved_std)) |path|
        path
    else
        try PathFinder.findZigInPath(allocator, io, environ_map);
    defer allocator.free(zig_exe_path);

    var version_buf: [32]u8 = undefined;
    const version_str = try BinaryParser.findZigVersion(allocator, io, zig_exe_path, &version_buf);
    const resolved_version = try allocator.dupe(u8, version_str);

    try validateStdRoot(allocator, io, resolved_std);

    return Environment{
        .std_path = resolved_std,
        .root_path = resolved_root,
        .zig_version = resolved_version,
        .mode = config.mode,
        .allocator = allocator,
    };
}

fn validateProjectRoot(allocator: mem.Allocator, io: Io, root_path: []const u8) DiscoveryError!void {
    const anchors = [_][]const []const u8{
        &.{"build.zig"},
        &.{ "src", "root.zig" },
        &.{ "src", "main.zig" },
    };

    for (anchors) |nodes| {
        const sub_path = try Dir.path.join(allocator, nodes);
        defer allocator.free(sub_path);

        const full_path = try Dir.path.resolve(allocator, &.{ root_path, sub_path });
        defer allocator.free(full_path);

        Dir.accessAbsolute(io, full_path, .{}) catch continue;
        return;
    }

    return error.InvalidProjectRoot;
}

fn validateStdRoot(allocator: mem.Allocator, io: Io, std_path: []const u8) DiscoveryError!void {
    const std_zig = try Dir.path.resolve(allocator, &.{ std_path, "std.zig" });
    defer allocator.free(std_zig);

    Dir.accessAbsolute(io, std_zig, .{}) catch {
        return error.StdPathNotFound;
    };
}
