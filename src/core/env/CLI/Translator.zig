const std = @import("std");
const mem = std.mem;
const process = std.process;
const ArrayList = std.ArrayList;
const fmt = std.fmt;
const Allocator = mem.Allocator;
const SemanticVersion = std.SemanticVersion;

const Types = @import("Types.zig");
const Lang = Types.Lang;
const FilterMode = Types.FilterMode;

pub fn detectLanguage(map: *const process.Environ.Map) Lang {
    const keys = [_][]const u8{ "LC_ALL", "LC_MESSAGES", "LANG" };

    for (keys) |key| {
        if (map.get(key)) |val| {
            if (mem.startsWith(u8, val, "ja")) {
                return .ja;
            } else {
                return .en;
            }
        }
    }

    return .en;
}

pub fn getModuleList(mode: FilterMode, version: SemanticVersion, allocator: Allocator) ![]const []const u8 {
    const is_0_15 = version.major == 0 and version.minor == 15;

    const core_0160 = &[_][]const u8{ "mem", "heap", "Thread", "atomic", "meta", "builtin", "simd", "options", "Options", "start" };
    const core_0152 = &[_][]const u8{ "mem", "heap", "Thread", "atomic", "meta", "builtin", "simd", "options", "Options", "start", "once" };

    const ds_0160 = &[_][]const u8{ "ArrayList", "MultiArrayList", "array_list", "HashMap", "ArrayHashMapUnmanaged", "AutoArrayHashMapUnmanaged", "StringArrayHashMapUnmanaged", "AutoHashMap", "StringHashMap", "hash_map", "array_hash_map", "BufMap", "static_string_map", "BufSet", "bit_set", "BitStack", "Deque", "PriorityQueue", "PriorityDequeue", "Treap", "enums", "DoublyLinkedList", "SinglyLinkedList", "StaticBitSet", "DynamicBitSet" };
    const ds_0152 = &[_][]const u8{ "ArrayList", "MultiArrayList", "array_list", "HashMap", "ArrayHashMap", "AutoArrayHashMap", "StringArrayHashMap", "ArrayHashMapUnmanaged", "AutoArrayHashMapUnmanaged", "StringArrayHashMapUnmanaged", "StringHashMap", "hash_map", "array_hash_map", "BufMap", "static_string_map", "BufSet", "bit_set", "BitStack", "PriorityQueue", "PriorityDequeue", "Treap", "enums", "SegmentedList", "DoublyLinkedList", "SinglyLinkedList", "StaticBitSet", "DynamicBitSet" };

    const io_0160 = &[_][]const u8{ "Io", "fs", "http", "Uri", "process", "DynLib", "time", "tz", "Tz" };
    const io_0152 = &[_][]const u8{ "Io", "io", "fs", "net", "http", "Uri", "process", "DynLib", "time", "tz", "Tz", "os.getFdPath", "os.isGetFdPathSupportedOnTarget", "os.argv", "os.environ" };

    const data_proc = &[_][]const u8{ "json", "zon", "fmt", "ascii", "unicode", "base64", "leb", "compress", "zip", "tar" };
    const math_sec = &[_][]const u8{ "math", "Random", "sort", "crypto", "hash" };
    const dev_tool = &[_][]const u8{ "zig", "Build", "SemanticVersion", "testing", "debug", "log", "Progress" };
    const agnostic = &[_][]const u8{ "dwarf", "pie", "Target", "gpu" };

    const os_linux_0160 = &[_][]const u8{ "os.linux", "posix", "elf" };
    const os_linux_0152 = &[_][]const u8{ "os.linux", "os.freebsd", "posix", "elf" };

    const os_win_0160 = &[_][]const u8{ "os.windows", "coff", "pdb" };
    const os_win_0152 = &[_][]const u8{ "os.windows", "os.accessW", "coff", "pdb" };

    const os_mac = &[_][]const u8{"macho"};

    const os_other_0160 = &[_][]const u8{ "wasm", "os.wasi", "os.emscripten", "os.uefi", "os.plan9" };
    const os_other_0152 = &[_][]const u8{ "wasm", "os.wasi", "os.emscripten", "os.uefi", "os.plan9", "os.fstat_wasi", "os.fstatat_wasi" };

    const external = &[_][]const u8{ "c", "valgrind" };

    return switch (mode) {
        .group_core => if (is_0_15) core_0152 else core_0160,
        .group_data_struct => if (is_0_15) ds_0152 else ds_0160,
        .group_system_io => if (is_0_15) io_0152 else io_0160,
        .group_data_proc => data_proc,
        .group_math_sec => math_sec,
        .group_dev_tool => dev_tool,
        .group_agnostic_spec => agnostic,
        .group_os_linux_posix => if (is_0_15) os_linux_0152 else os_linux_0160,
        .group_os_windows => if (is_0_15) os_win_0152 else os_win_0160,
        .group_os_macos => os_mac,
        .group_os_other => if (is_0_15) os_other_0152 else os_other_0160,
        .group_external_c_tool => external,
        .only_layer1 => Types.layer1_modules,
        .group_app_dev_core => blk: {
            var list = ArrayList([]const u8).empty;
            try list.appendSlice(allocator, if (is_0_15) core_0152 else core_0160);
            try list.appendSlice(allocator, if (is_0_15) ds_0152 else ds_0160);
            try list.appendSlice(allocator, if (is_0_15) io_0152 else io_0160);
            try list.appendSlice(allocator, data_proc);
            try list.appendSlice(allocator, math_sec);
            try list.appendSlice(allocator, dev_tool);
            try list.appendSlice(allocator, agnostic);
            break :blk try list.toOwnedSlice(allocator);
        },
        else => &.{},
    };
}
