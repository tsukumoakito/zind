const std = @import("std");
const mem = std.mem;
const process = std.process;
const ArrayList = std.ArrayList;
const fmt = std.fmt;
const Allocator = mem.Allocator;

const Types = @import("Types.zig");
const Config = Types.Config;
const ScanSpec = Types.ScanSpec;
const FilterMode = Types.FilterMode;

pub const ParseError = error{
    UnknownArgument,
    MissingValue,
    InvalidMode,
    InvalidGroupNumber,
    InvalidDepth,
    OutOfMemory,
};

pub fn parse(allocator: Allocator, args_iter: *process.Args.Iterator) ParseError!Config {
    var config = Config{
        .allocator = allocator,
        .target_files = ArrayList([]const u8).empty,
        .exclude_files = ArrayList([]const u8).empty,
        .lib_specs = ArrayList(ScanSpec).empty,
    };
    errdefer config.deinit();

    var active_show_counts: bool = true;

    _ = args_iter.skip();

    var arg_opt = args_iter.next();
    while (arg_opt) |arg| {
        if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
            config.show_help = true;
        } else if (mem.eql(u8, arg, "--debug")) {
            config.debug_mode = true;
        } else if (mem.eql(u8, arg, "--lang")) {
            const val = args_iter.next() orelse return error.MissingValue;
            if (mem.eql(u8, val, "en")) {
                config.lang = .en;
            } else if (mem.eql(u8, val, "ja")) {
                config.lang = .ja;
            } else return error.InvalidMode;
        } else if (mem.eql(u8, arg, "--std-path")) {
            const val = args_iter.next() orelse return error.MissingValue;
            if (config.std_path) |p| allocator.free(p);
            config.std_path = try allocator.dupe(u8, val);
        } else if (mem.eql(u8, arg, "--root-path")) {
            const val = args_iter.next() orelse return error.MissingValue;
            if (config.root_path) |p| allocator.free(p);
            config.root_path = try allocator.dupe(u8, val);
        } else if (mem.eql(u8, arg, "--target-os")) {
            const val = args_iter.next() orelse return error.MissingValue;
            if (config.target_os) |p| allocator.free(p);
            config.target_os = try allocator.dupe(u8, val);
        } else if (mem.eql(u8, arg, "--target-arch")) {
            const val = args_iter.next() orelse return error.MissingValue;
            if (config.target_arch) |p| allocator.free(p);
            config.target_arch = try allocator.dupe(u8, val);
        } else if (mem.eql(u8, arg, "--libc")) {
            config.link_libc = true;
        } else if (mem.eql(u8, arg, "--no-libc")) {
            config.link_libc = false;
        } else if (mem.eql(u8, arg, "--summary-only")) {
            config.summary_only = true;
        } else if (mem.eql(u8, arg, "--file")) {
            const val = args_iter.next() orelse return error.MissingValue;
            if (config.direct_file) |p| allocator.free(p);
            config.direct_file = try allocator.dupe(u8, val);
        } else if (mem.eql(u8, arg, "--include")) {
            const val = args_iter.next() orelse return error.MissingValue;
            var it = mem.splitScalar(u8, val, ',');
            while (it.next()) |p| try config.target_files.append(allocator, try allocator.dupe(u8, p));
        } else if (mem.eql(u8, arg, "--exclude")) {
            const val = args_iter.next() orelse return error.MissingValue;
            var it = mem.splitScalar(u8, val, ',');
            while (it.next()) |p| try config.exclude_files.append(allocator, try allocator.dupe(u8, p));
        } else if (mem.eql(u8, arg, "--mode")) {
            const val = args_iter.next() orelse return error.MissingValue;
            if (mem.eql(u8, val, "lib") or mem.eql(u8, val, "library")) {
                config.mode = .library;
            } else if (mem.eql(u8, val, "project")) {
                config.mode = .project;
            } else return error.InvalidMode;
        } else if (mem.eql(u8, arg, "--color")) {
            const val = args_iter.next() orelse return error.MissingValue;
            if (mem.eql(u8, val, "auto")) {
                config.color_mode = .auto;
            } else if (mem.eql(u8, val, "always")) {
                config.color_mode = .always;
            } else if (mem.eql(u8, val, "none")) {
                config.color_mode = .none;
            } else return error.InvalidMode;
        } else if (mem.eql(u8, arg, "--no-color")) {
            config.color_mode = .none;
        } else if (mem.eql(u8, arg, "--groups")) {
            const val = args_iter.next() orelse return error.MissingValue;
            const spec = try nextSpec(allocator, &config.lib_specs, config.global_depth, active_show_counts, false);
            var it = mem.splitScalar(u8, val, ',');
            while (it.next()) |num_str| {
                const n = fmt.parseInt(usize, num_str, 10) catch return error.InvalidGroupNumber;
                const mode = FilterMode.fromNumeric(n) orelse return error.InvalidGroupNumber;
                try spec.filter_modes.append(allocator, mode);
            }
        } else if (mem.startsWith(u8, arg, "--group-")) {
            const spec = try nextSpec(allocator, &config.lib_specs, config.global_depth, active_show_counts, false);
            const suffix = arg[8..];
            if (mem.eql(u8, suffix, "core")) {
                try spec.filter_modes.append(allocator, .group_core);
            } else if (mem.eql(u8, suffix, "data-struct")) {
                try spec.filter_modes.append(allocator, .group_data_struct);
            } else if (mem.eql(u8, suffix, "system-io")) {
                try spec.filter_modes.append(allocator, .group_system_io);
            } else if (mem.eql(u8, suffix, "data-proc")) {
                try spec.filter_modes.append(allocator, .group_data_proc);
            } else if (mem.eql(u8, suffix, "math-sec")) {
                try spec.filter_modes.append(allocator, .group_math_sec);
            } else if (mem.eql(u8, suffix, "dev-tool")) {
                try spec.filter_modes.append(allocator, .group_dev_tool);
            } else if (mem.eql(u8, suffix, "agnostic-spec")) {
                try spec.filter_modes.append(allocator, .group_agnostic_spec);
            } else if (mem.eql(u8, suffix, "os-linux-posix")) {
                try spec.filter_modes.append(allocator, .group_os_linux_posix);
            } else if (mem.eql(u8, suffix, "os-windows")) {
                try spec.filter_modes.append(allocator, .group_os_windows);
            } else if (mem.eql(u8, suffix, "os-macos")) {
                try spec.filter_modes.append(allocator, .group_os_macos);
            } else if (mem.eql(u8, suffix, "os-other")) {
                try spec.filter_modes.append(allocator, .group_os_other);
            } else if (mem.eql(u8, suffix, "external-c-tool")) {
                try spec.filter_modes.append(allocator, .group_external_c_tool);
            } else if (mem.eql(u8, suffix, "app-dev-core")) {
                try spec.filter_modes.append(allocator, .group_app_dev_core);
            } else {
                const n = fmt.parseInt(usize, suffix, 10) catch return error.InvalidGroupNumber;
                const mode = FilterMode.fromNumeric(n) orelse return error.InvalidGroupNumber;
                try spec.filter_modes.append(allocator, mode);
            }
        } else if (mem.eql(u8, arg, "--filter-layer1")) {
            const spec = try ensureCurrentSpec(allocator, &config.lib_specs, config.global_depth, active_show_counts, false);
            spec.exclude_layer1 = true;
        } else if (mem.eql(u8, arg, "--only-layer1")) {
            const spec = try ensureCurrentSpec(allocator, &config.lib_specs, config.global_depth, active_show_counts, false);
            try spec.filter_modes.append(allocator, .only_layer1);
        } else if (mem.eql(u8, arg, "--top-level")) {
            const spec = try nextSpec(allocator, &config.lib_specs, 1, active_show_counts, true);
            try spec.scopes.append(allocator, try allocator.dupe(u8, "std"));
        } else if (mem.eql(u8, arg, "--top-level-sub")) {
            const spec = try nextSpec(allocator, &config.lib_specs, 2, active_show_counts, true);
            try spec.scopes.append(allocator, try allocator.dupe(u8, "std"));
        } else if (mem.eql(u8, arg, "--trace-up")) {
            const val = args_iter.next() orelse return error.MissingValue;
            if (config.trace_up) |p| allocator.free(p);
            config.trace_up = try allocator.dupe(u8, val);
        } else if (mem.eql(u8, arg, "--users")) {
            const val = args_iter.next() orelse return error.MissingValue;
            if (config.users_target) |p| allocator.free(p);
            config.users_target = try allocator.dupe(u8, val);
        } else if (mem.eql(u8, arg, "--skeleton")) {
            config.skeleton = true;
        } else if (mem.eql(u8, arg, "--scope")) {
            const val = args_iter.next() orelse return error.MissingValue;
            const spec = blk: {
                if (config.lib_specs.items.len > 0) {
                    const last = &config.lib_specs.items[config.lib_specs.items.len - 1];
                    if (last.scopes.items.len > 0 or last.flagged_deprecated or last.is_search or last.is_probe) {
                        break :blk try nextSpec(allocator, &config.lib_specs, config.global_depth, active_show_counts, false);
                    }
                }
                break :blk try ensureCurrentSpec(allocator, &config.lib_specs, config.global_depth, active_show_counts, false);
            };
            var it = mem.splitScalar(u8, val, ',');
            while (it.next()) |part| try spec.scopes.append(allocator, try allocator.dupe(u8, part));
        } else if (mem.eql(u8, arg, "--depth")) {
            const val = args_iter.next() orelse return error.MissingValue;
            const d = if (mem.eql(u8, val, "unlimited")) Types.UNLIMITED_DEPTH else fmt.parseInt(usize, val, 10) catch return error.InvalidDepth;
            config.global_depth = d;
            for (config.lib_specs.items) |*spec| if (!spec.is_depth_explicit) {
                spec.depth = d;
            };
        } else if (mem.eql(u8, arg, "--no-counts")) {
            active_show_counts = false;
            config.lib_show_counts = false;
            for (config.lib_specs.items) |*spec| spec.show_counts = false;
        } else if (mem.eql(u8, arg, "--merge")) {
            config.lib_merge_mode = true;
        } else if (mem.eql(u8, arg, "--depth-scope")) {
            const d_val = args_iter.next() orelse return error.MissingValue;
            const s_val = args_iter.next() orelse return error.MissingValue;
            const spec = try nextSpec(allocator, &config.lib_specs, null, active_show_counts, true);
            spec.depth = if (mem.eql(u8, d_val, "unlimited")) Types.UNLIMITED_DEPTH else fmt.parseInt(usize, d_val, 10) catch return error.InvalidDepth;
            var it = mem.splitScalar(u8, s_val, ',');
            while (it.next()) |part| try spec.scopes.append(allocator, try allocator.dupe(u8, part));
        } else if (mem.eql(u8, arg, "--depth-probe")) {
            const d_val = args_iter.next() orelse return error.MissingValue;
            const s_val = args_iter.next() orelse return error.MissingValue;
            const spec = try nextSpec(allocator, &config.lib_specs, null, active_show_counts, true);
            spec.is_probe = true;
            spec.depth = if (mem.eql(u8, d_val, "unlimited")) Types.UNLIMITED_DEPTH else fmt.parseInt(usize, d_val, 10) catch return error.InvalidDepth;
            var it = mem.splitScalar(u8, s_val, ',');
            while (it.next()) |part| try spec.scopes.append(allocator, try allocator.dupe(u8, part));
        } else if (mem.eql(u8, arg, "--probe")) {
            const next_arg = args_iter.next();
            if (next_arg) |val| {
                if (mem.startsWith(u8, val, "-")) {
                    const spec = try ensureCurrentSpec(allocator, &config.lib_specs, config.global_depth, active_show_counts, false);
                    spec.is_probe = true;
                    spec.probe_no_arg = true;
                    arg_opt = val;
                    continue;
                } else {
                    var it = mem.splitScalar(u8, val, ',');
                    while (it.next()) |part| {
                        const spec = try nextSpec(allocator, &config.lib_specs, config.global_depth, active_show_counts, false);
                        spec.is_probe = true;
                        try spec.scopes.append(allocator, try allocator.dupe(u8, part));
                    }
                }
            } else {
                const spec = try ensureCurrentSpec(allocator, &config.lib_specs, config.global_depth, active_show_counts, false);
                spec.is_probe = true;
                spec.probe_no_arg = true;
            }
        } else if (mem.eql(u8, arg, "--flagged-deprecated")) {
            const spec = try nextSpec(allocator, &config.lib_specs, Types.UNLIMITED_DEPTH, active_show_counts, true);
            spec.flagged_deprecated = true;
            try spec.scopes.append(allocator, try allocator.dupe(u8, "std"));
        } else if (mem.eql(u8, arg, "--show-private")) {
            config.show_private = true;
        } else if (mem.eql(u8, arg, "--search")) {
            const val = args_iter.next() orelse return error.MissingValue;
            const spec = try nextSpec(allocator, &config.lib_specs, Types.UNLIMITED_DEPTH, active_show_counts, true);
            spec.is_search = true;
            try spec.scopes.append(allocator, try allocator.dupe(u8, "std"));
            var it = mem.splitScalar(u8, val, ',');
            while (it.next()) |part| try spec.search_terms.append(allocator, try allocator.dupe(u8, part));
        } else if (config.std_path == null and !mem.startsWith(u8, arg, "-")) {
            config.std_path = try allocator.dupe(u8, arg);
        } else return error.UnknownArgument;
        arg_opt = args_iter.next();
    }
    if (config.mode == .library and config.lib_specs.items.len == 0) {
        _ = try ensureCurrentSpec(allocator, &config.lib_specs, config.global_depth, active_show_counts, false);
    }
    return config;
}

fn ensureCurrentSpec(allocator: Allocator, specs: *ArrayList(ScanSpec), d: ?usize, sc: bool, explicit: bool) !*ScanSpec {
    if (specs.items.len == 0) {
        try specs.append(allocator, .{
            .depth = d,
            .is_depth_explicit = explicit,
            .show_counts = sc,
            .scopes = ArrayList([]const u8).empty,
            .search_terms = ArrayList([]const u8).empty,
            .filter_modes = ArrayList(FilterMode).empty,
        });
    }
    return &specs.items[specs.items.len - 1];
}

fn nextSpec(allocator: Allocator, specs: *ArrayList(ScanSpec), d: ?usize, sc: bool, explicit: bool) !*ScanSpec {
    if (specs.items.len > 0) {
        if (specs.items[specs.items.len - 1].isEmpty()) {
            const s = &specs.items[specs.items.len - 1];
            s.depth = d;
            s.is_depth_explicit = explicit;
            s.show_counts = sc;
            return s;
        }
    }
    try specs.append(allocator, .{
        .depth = d,
        .is_depth_explicit = explicit,
        .show_counts = sc,
        .scopes = ArrayList([]const u8).empty,
        .search_terms = ArrayList([]const u8).empty,
        .filter_modes = ArrayList(FilterMode).empty,
    });
    return &specs.items[specs.items.len - 1];
}
