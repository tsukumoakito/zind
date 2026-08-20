const std = @import("std");
const process = std.process;
const Io = std.Io;
const File = std.Io.File;
const Allocator = std.mem.Allocator;
const fmt = std.fmt;

const Library = @import("core/analysis/Library.zig");
const Project = @import("core/analysis/Project.zig");
const CLI = @import("core/env/CLI.zig");
const Discovery = @import("core/env/Discovery.zig");
const Metrics = @import("core/registry/Metrics.zig").Metrics;

pub fn main(init: process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var stdout_buffer: [16384]u8 = undefined;
    var stdout_file_writer: File.Writer = .init(File.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var args_iter = init.minimal.args.iterate();

    var config = CLI.parse(allocator, &args_iter) catch |err| {
        try stdout.print("[FATAL] CLI Argument Error: {s}\n", .{@errorName(err)});
        try stdout.flush();
        return;
    };
    defer config.deinit();

    const no_color_env = if (init.environ_map.get("NO_COLOR")) |v| v.len > 0 else false;
    const force_color_env = if (init.environ_map.get("CLICOLOR_FORCE")) |v| v.len > 0 else false;

    const term_mode: Io.Terminal.Mode = switch (config.color_mode) {
        .none => .no_color,
        .always => .escape_codes,
        .auto => try Io.Terminal.Mode.detect(io, File.stdout(), no_color_env, force_color_env),
    };

    var terminal = Io.Terminal{
        .writer = stdout,
        .mode = term_mode,
    };

    if (config.show_help) {
        const env_info = Discovery.discover(
            allocator,
            io,
            stdout,
            init.environ_map,
            config,
        ) catch null;
        const ver = if (env_info) |e| e.zig_version else "unknown";
        const path = if (env_info) |e| e.std_path else (config.std_path orelse "not detected");
        try CLI.printHelp(&config, stdout, ver, path, init.environ_map);
        try stdout.flush();
        return;
    }

    const env = Discovery.discover(
        allocator,
        io,
        stdout,
        init.environ_map,
        config,
    ) catch |err| {
        try stdout.print("[FATAL] Environment Discovery Failed: {s}\n", .{@errorName(err)});
        try stdout.flush();
        return;
    };

    try stdout.print("=== Zind: Environment Sync Success ===\n", .{});
    try stdout.print("Detected Zig Version: {s}\n", .{env.zig_version});
    try stdout.print("Standard Library    : {s}\n", .{env.std_path});
    if (env.mode == .project) try stdout.print("Project Root        : {s}\n", .{env.root_path});
    try stdout.print("Execution Mode      : {s}\n", .{@tagName(env.mode)});
    if (config.debug_mode) try stdout.print("Debug Mode          : enabled\n", .{});
    try stdout.print("======================================\n", .{});

    if (Project.checkUnimplemented(&terminal, &config)) {
        try stdout.flush();
        return;
    }

    try Library.run(
        allocator,
        io,
        &terminal,
        env,
        &config,
    );

    try stdout.flush();
}
