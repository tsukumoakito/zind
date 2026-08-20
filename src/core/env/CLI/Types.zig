const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;
const math = std.math;
const Allocator = mem.Allocator;

pub const UNLIMITED_DEPTH = math.maxInt(usize);
pub const layer1_modules = &[_][]const u8{ "c", "os", "posix" };

pub const Mode = enum {
    project,
    library,
};

pub const ColorMode = enum {
    auto,
    always,
    none,
};

pub const Lang = enum {
    auto,
    en,
    ja,
};

pub const FilterMode = enum {
    none,
    exclude_layer1,
    only_layer1,
    top_level,
    top_level_sub,
    group_core,
    group_data_struct,
    group_system_io,
    group_data_proc,
    group_math_sec,
    group_dev_tool,
    group_agnostic_spec,
    group_os_linux_posix,
    group_os_windows,
    group_os_macos,
    group_os_other,
    group_external_c_tool,
    group_app_dev_core,

    pub fn fromNumeric(num: usize) ?FilterMode {
        return switch (num) {
            1 => .group_core,
            2 => .group_data_struct,
            3 => .group_system_io,
            4 => .group_data_proc,
            5 => .group_math_sec,
            6 => .group_dev_tool,
            7 => .group_agnostic_spec,
            8 => .group_os_linux_posix,
            9 => .group_os_windows,
            10 => .group_os_macos,
            11 => .group_os_other,
            12 => .group_external_c_tool,
            else => null,
        };
    }
};

pub const ScanSpec = struct {
    depth: ?usize = null,
    is_depth_explicit: bool = false,
    scopes: ArrayList([]const u8),
    show_counts: bool = true,
    is_probe: bool = false,
    probe_no_arg: bool = false,
    flagged_deprecated: bool = false,
    is_search: bool = false,
    exclude_layer1: bool = false,
    search_terms: ArrayList([]const u8),
    filter_modes: ArrayList(FilterMode),

    pub fn deinit(self: *ScanSpec, allocator: Allocator) void {
        for (self.scopes.items) |s| allocator.free(s);
        self.scopes.deinit(allocator);
        for (self.search_terms.items) |s| allocator.free(s);
        self.search_terms.deinit(allocator);
        self.filter_modes.deinit(allocator);
    }

    pub fn isEmpty(self: ScanSpec) bool {
        return self.scopes.items.len == 0 and
            self.filter_modes.items.len == 0 and
            !self.is_search and
            !self.flagged_deprecated and
            !self.is_probe and
            !self.exclude_layer1 and
            !self.is_depth_explicit;
    }
};

pub const Config = struct {
    std_path: ?[]const u8 = null,
    root_path: ?[]const u8 = null,
    target_files: ArrayList([]const u8),
    exclude_files: ArrayList([]const u8),
    mode: Mode = .library,
    color_mode: ColorMode = .auto,
    lang: Lang = .auto,
    filter: ?[]const u8 = null,
    trace_up: ?[]const u8 = null,
    probe_target: ?[]const u8 = null,
    users_target: ?[]const u8 = null,
    skeleton: bool = false,
    show_help: bool = false,
    allocator: Allocator,
    lib_specs: ArrayList(ScanSpec),
    lib_merge_mode: bool = false,
    lib_show_counts: bool = true,
    global_depth: ?usize = null,
    debug_mode: bool = false,
    summary_only: bool = false,
    link_libc: ?bool = null,
    target_os: ?[]const u8 = null,
    target_arch: ?[]const u8 = null,
    direct_file: ?[]const u8 = null,
    show_private: bool = false,

    pub fn deinit(self: *Config) void {
        if (self.std_path) |p| self.allocator.free(p);
        if (self.root_path) |p| self.allocator.free(p);
        if (self.filter) |p| self.allocator.free(p);
        if (self.trace_up) |p| self.allocator.free(p);
        if (self.probe_target) |p| self.allocator.free(p);
        if (self.users_target) |p| self.allocator.free(p);
        if (self.target_os) |p| self.allocator.free(p);
        if (self.target_arch) |p| self.allocator.free(p);
        if (self.direct_file) |p| self.allocator.free(p);
        for (self.target_files.items) |p| self.allocator.free(p);
        self.target_files.deinit(self.allocator);
        for (self.exclude_files.items) |p| self.allocator.free(p);
        self.exclude_files.deinit(self.allocator);
        for (self.lib_specs.items) |*s| s.deinit(self.allocator);
        self.lib_specs.deinit(self.allocator);
    }
};
