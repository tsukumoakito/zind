const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const Io = std.Io;
const Ast = std.zig.Ast;
const ArrayList = std.ArrayList;
const StringHashMap = std.array_hash_map.String;
const HashMap = std.hash_map.HashMap;
const Allocator = mem.Allocator;
const Dir = Io.Dir;
const Writer = Io.Writer;
const Terminal = Io.Terminal;
const ArenaAllocator = std.heap.ArenaAllocator;
const Alignment = std.mem.Alignment;
const SemanticVersion = std.SemanticVersion;
const builtin = @import("builtin");

const CLI = @import("../env/CLI.zig");
const Discovery = @import("../env/Discovery.zig");
const PathFinder = @import("../env/PathFinder.zig");
const Metrics = @import("../registry/Metrics.zig").Metrics;
const AstUtils = @import("AstUtils.zig");
const Context = @import("Context.zig");
const Formatter = @import("Formatter.zig");
const Scanner = @import("Scanner.zig");
const Types = @import("Types.zig");
const Utils = @import("Utils.zig");

fn estimateMetrics(allocator: Allocator, io: Io, root_path: []const u8) struct { file_count: usize, estimated_entries: usize } {
    var dir = Dir.openDirAbsolute(io, root_path, .{ .iterate = true }) catch return .{ .file_count = 512, .estimated_entries = 50000 };
    defer dir.close(io);

    var walker = dir.walk(allocator) catch return .{ .file_count = 512, .estimated_entries = 50000 };
    defer walker.deinit();

    var count: usize = 0;
    while (walker.next(io) catch null) |entry| {
        if (entry.kind == .file and mem.endsWith(u8, entry.path, ".zig")) {
            count += 1;
        }
    }

    return .{
        .file_count = count,
        .estimated_entries = count * 150,
    };
}

pub fn run(
    allocator: Allocator,
    io: Io,
    terminal: *Terminal,
    env: Discovery.Environment,
    config: *CLI.Config,
) !void {
    const version = SemanticVersion.parse(env.zig_version) catch builtin.zig_version;
    try CLI.normalizeConfig(config, version);

    const est = estimateMetrics(allocator, io, env.std_path);

    const abs_root = try PathFinder.findEntryPoint(allocator, io, env.std_path, config.direct_file);
    defer allocator.free(abs_root);

    const root_name = if (env.mode == .library) "std" else Dir.path.stem(abs_root);

    var registry = try ArrayList(Types.ApiEntry).initCapacity(allocator, est.estimated_entries);
    defer registry.deinit(allocator);

    var registry_arena = ArenaAllocator.init(allocator);
    defer registry_arena.deinit();
    const registry_allocator = registry_arena.allocator();

    var pool = Types.StringPool.init(allocator);
    try pool.map.ensureTotalCapacity(allocator, est.estimated_entries);
    defer pool.deinit(allocator);

    var path_cache = StringHashMap(Types.StringId).empty;
    defer path_cache.deinit(allocator);

    var ast_cache = Context.AstCacheManager{ .capacity = est.file_count + 64 };
    defer ast_cache.deinit(allocator);

    var count_cache = StringHashMap(usize).empty;
    defer count_cache.deinit(allocator);

    var unhandled_list = ArrayList(Types.UnhandledNode).empty;
    defer {
        for (unhandled_list.items) |*u| u.deinit(allocator);
        unhandled_list.deinit(allocator);
    }

    var dead_ends = ArrayList(Types.DeadEnd).empty;
    defer {
        for (dead_ends.items) |*de| de.deinit(allocator);
        dead_ends.deinit(allocator);
    }

    const workspace_buf = try allocator.alloc(u8, 64 * 1024);
    defer allocator.free(workspace_buf);

    var fqn_writer = Io.Writer.Allocating.init(allocator);
    defer fqn_writer.deinit();
    var path_buf: [Dir.max_path_bytes]u8 = undefined;

    var combined_scopes = ArrayList([]const u8).empty;
    defer combined_scopes.deinit(allocator);
    for (config.lib_specs.items) |spec| {
        for (spec.scopes.items) |s| {
            var exists = false;
            for (combined_scopes.items) |existing| if (mem.eql(u8, existing, s)) {
                exists = true;
                break;
            };
            if (!exists) try combined_scopes.append(allocator, s);
        }
    }
    if (combined_scopes.items.len == 0) try combined_scopes.append(allocator, root_name);

    const root_name_id = try pool.getOrPut(allocator, root_name);
    const abs_root_id = try pool.getOrPut(allocator, abs_root);

    const initial_prefix = try allocator.alloc(Types.StringId, 1);
    defer allocator.free(initial_prefix);
    initial_prefix[0] = root_name_id;

    const root_fqn = try registry_allocator.alloc(Types.StringId, 1);
    root_fqn[0] = root_name_id;
    try registry.append(allocator, .{
        .fqn_parts = root_fqn,
        .full_fqn_id = root_name_id,
        .cond_id = null,
        .dep_id = null,
        .rhs_id = null,
        .trace_chain = &.{},
        .coord = .{
            .file_id = abs_root_id,
            .node = .root,
        },
        .is_explicit_dep = false,
        .is_private = false,
        .is_target_hit = false,
        .child_count = 0,
        .priv_child_count = 0,
    });

    var global_pub_hidden: usize = 0;
    var global_priv_hidden: usize = 0;
    var initial_stack = ArrayList(Types.NodeIdentity).empty;
    defer initial_stack.deinit(allocator);

    var visited = HashMap(Types.VisitedKey, void, Types.VisitedContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer visited.deinit();
    try visited.ensureTotalCapacity(@intCast(est.file_count + 64));

    var logic_metrics = Metrics{};

    const scan_ctx = Context.AnalysisContext{
        .allocator = allocator,
        .registry_allocator = registry_allocator,
        .io = io,
        .root_path_id = abs_root_id,
        .root_name_id = root_name_id,
        .registry = &registry,
        .pool = &pool,
        .path_cache = &path_cache,
        .visited = &visited,
        .ast_cache = &ast_cache,
        .count_cache = &count_cache,
        .unhandled_list = &unhandled_list,
        .dead_ends = &dead_ends,
        .stack = &initial_stack,
        .pub_hidden_count = &global_pub_hidden,
        .priv_hidden_count = &global_priv_hidden,
        .fqn_writer = &fqn_writer,
        .terminal = terminal,
        .path_buf = &path_buf,
        .workspace_buf = workspace_buf,
        .filters = combined_scopes.items,
        .search_terms = &.{},
        .depth_limit = if (config.global_depth) |gd| gd else CLI.UNLIMITED_DEPTH,
        .pub_only = true,
        .show_private = config.show_private,
        .is_explicit_target = false,
        .flagged_deprecated = false,
        .show_counts = config.lib_show_counts,
        .is_dry_run = false,
        .exclude_layer1 = false,
        .current_cond_id = null,
        .inherited_dep_id = null,
        .debug_mode = config.debug_mode,
        .metrics = &logic_metrics,
        .link_libc = config.link_libc,
        .target_os = config.target_os,
        .target_arch = config.target_arch,
    };

    Scanner.processFile(scan_ctx, abs_root, initial_prefix) catch |err| {
        try terminal.writer.print("[ERROR] Failed to start analysis from '{s}': {s}\n", .{ abs_root, @errorName(err) });
        return err;
    };

    registry.items[0].child_count = global_pub_hidden;
    registry.items[0].priv_child_count = global_priv_hidden;

    const SortContext = struct {
        p: *const Types.StringPool,
        r: []const Types.ApiEntry,

        pub fn lessThan(self: @This(), a_idx: usize, b_idx: usize) bool {
            const entry_a = self.r[a_idx];
            const entry_b = self.r[b_idx];

            const parts_len = @min(entry_a.fqn_parts.len, entry_b.fqn_parts.len);
            for (0..parts_len) |i| {
                const ord = mem.order(u8, self.p.get(entry_a.fqn_parts[i]), self.p.get(entry_b.fqn_parts[i]));
                if (ord != .eq) return ord == .lt;
            }
            if (entry_a.fqn_parts.len != entry_b.fqn_parts.len) return entry_a.fqn_parts.len < entry_b.fqn_parts.len;

            const a_cond = if (entry_a.cond_id) |id| self.p.get(id) else "";
            const b_cond = if (entry_b.cond_id) |id| self.p.get(id) else "";
            const c_ord = mem.order(u8, a_cond, b_cond);
            if (c_ord != .eq) return c_ord == .lt;

            const trace_len = @min(entry_a.trace_chain.len, entry_b.trace_chain.len);
            for (0..trace_len) |i| {
                const ord = mem.order(u8, self.p.get(entry_a.trace_chain[i].formatted_id), self.p.get(entry_b.trace_chain[i].formatted_id));
                if (ord != .eq) return ord == .lt;
            }
            if (entry_a.trace_chain.len != entry_b.trace_chain.len) return entry_a.trace_chain.len < entry_b.trace_chain.len;

            if (entry_a.dep_id != entry_b.dep_id) {
                const a_dep = if (entry_a.dep_id) |id| self.p.get(id) else "";
                const b_dep = if (entry_b.dep_id) |id| self.p.get(id) else "";
                const d_ord = mem.order(u8, a_dep, b_dep);
                if (d_ord != .eq) return d_ord == .lt;
            }

            return false;
        }
    };

    const registry_indices = try allocator.alloc(usize, registry.items.len);
    for (registry_indices, 0..) |*idx, i| idx.* = i;
    defer allocator.free(registry_indices);

    const global_sort_ctx = SortContext{ .p = &pool, .r = registry.items };
    mem.sortUnstable(usize, registry_indices, global_sort_ctx, SortContext.lessThan);

    var sorted_registry = try ArrayList(Types.ApiEntry).initCapacity(allocator, registry.items.len);
    for (registry_indices) |idx| sorted_registry.appendAssumeCapacity(registry.items[idx]);
    registry.deinit(allocator);
    registry = sorted_registry;

    var task_display_idx: usize = 1;
    var task_arena = ArenaAllocator.init(allocator);
    defer task_arena.deinit();

    var master_task_indices = ArrayList(usize).empty;
    defer master_task_indices.deinit(allocator);

    for (config.lib_specs.items) |*spec| {
        _ = task_arena.reset(.retain_capacity);
        const task_alloc = task_arena.allocator();
        var task_indices = ArrayList(usize).empty;
        defer task_indices.deinit(task_alloc);

        mem.sortUnstable([]const u8, spec.scopes.items, {}, Utils.sortStrings);

        for (registry.items, 0..) |entry, reg_idx| {
            if (entry.fqn_parts.len == 0) continue;
            const prefix = if (entry.fqn_parts.len > 1) entry.fqn_parts[0 .. entry.fqn_parts.len - 1] else &[_]Types.StringId{};
            const name_id = entry.fqn_parts[entry.fqn_parts.len - 1];

            const match_filter = Utils.findMatchId(prefix, name_id, &pool, spec.scopes.items, spec.depth);
            const is_searching = spec.search_terms.items.len > 0;

            var hit = match_filter != null;
            if (is_searching) {
                const comment = if (entry.dep_id) |id| pool.get(id) else null;
                const rhs = if (entry.rhs_id) |id| pool.get(id) else null;
                const full_fqn = pool.get(entry.full_fqn_id);
                if (Utils.containsAllKeywordsDirect(full_fqn, comment, rhs, spec.search_terms.items)) {
                    hit = true;
                } else hit = false;
            }

            var should_include = false;
            if (!entry.is_private) {
                should_include = hit;
            } else {
                const is_unlimited = if (spec.depth) |d| d == CLI.UNLIMITED_DEPTH else true;
                if (is_unlimited) {
                    should_include = config.show_private;
                } else {
                    should_include = hit;
                }
            }

            if (should_include and spec.exclude_layer1) {
                if (Utils.isLayer1Id(prefix, name_id, &pool, root_name_id)) {
                    should_include = false;
                }
            }

            if (should_include) {
                if (spec.flagged_deprecated) {
                    if (entry.is_explicit_dep) try task_indices.append(task_alloc, reg_idx);
                } else {
                    try task_indices.append(task_alloc, reg_idx);
                }
            }
        }

        if (config.lib_merge_mode) {
            for (task_indices.items) |idx| {
                var exists = false;
                for (master_task_indices.items) |existing| if (existing == idx) {
                    exists = true;
                    break;
                };
                if (!exists) try master_task_indices.append(allocator, idx);
            }
        } else {
            try printScanHeader(terminal, spec.*, task_display_idx, task_alloc, root_name);
            task_display_idx += 1;

            if (!config.summary_only) {
                const task_sort_ctx = SortContext{ .p = &pool, .r = registry.items };
                mem.sortUnstable(usize, task_indices.items, task_sort_ctx, SortContext.lessThan);

                for (task_indices.items, 0..) |reg_idx, task_ptr| {
                    _ = task_ptr;
                    const entry = registry.items[reg_idx];
                    if (entry.coord.node == .root) continue;

                    var hidden_pub: usize = 0;
                    var hidden_priv: usize = 0;

                    if (config.lib_show_counts) {
                        var reg_pub_children: usize = 0;
                        var reg_priv_children: usize = 0;
                        var j = reg_idx + 1;
                        while (j < registry.items.len) : (j += 1) {
                            const other = registry.items[j];
                            if (other.fqn_parts.len <= entry.fqn_parts.len) break;
                            if (!mem.eql(Types.StringId, other.fqn_parts[0..entry.fqn_parts.len], entry.fqn_parts)) break;
                            if (other.is_private) reg_priv_children += 1 else reg_pub_children += 1;
                        }

                        hidden_pub = reg_pub_children + entry.child_count;
                        hidden_priv = reg_priv_children + entry.priv_child_count;
                    }

                    try Formatter.printApiEntry(terminal, &pool, entry, &fqn_writer, hidden_pub, hidden_priv);
                }
            }

            const breakdown_res = try Formatter.calculateBreakdown(task_alloc, &pool, registry.items, task_indices.items);
            defer breakdown_res.deinit(task_alloc);

            const is_special_mode = spec.flagged_deprecated or spec.is_probe;
            const should_print_breakdown = config.summary_only or !is_special_mode;

            if (should_print_breakdown) {
                var min_depth: usize = std.math.maxInt(usize);
                var max_depth: usize = 0;
                var found_visible = false;
                for (task_indices.items) |idx| {
                    const entry = registry.items[idx];
                    if (entry.coord.node == .root) continue;
                    const d = entry.fqn_parts.len;
                    if (d < min_depth) min_depth = d;
                    if (d > max_depth) max_depth = d;
                    found_visible = true;
                }
                const delta = if (max_depth >= min_depth) max_depth - min_depth else 0;
                if (config.summary_only or (found_visible and delta >= 3)) {
                    try Formatter.printStats(terminal, breakdown_res.entries);
                }
            }

            try printScanSummary(terminal, task_indices.items, registry.items, breakdown_res.total_pub_hidden, breakdown_res.total_priv_hidden);

            if (spec.is_probe) {
                for (task_indices.items) |reg_idx| {
                    const entry = registry.items[reg_idx];
                    fqn_writer.clearRetainingCapacity();
                    try fqn_writer.writer.writeAll(pool.get(entry.full_fqn_id));
                    const current_fqn = fqn_writer.written();
                    var is_exact_target = false;
                    for (spec.scopes.items) |s| if (mem.eql(u8, s, current_fqn)) {
                        is_exact_target = true;
                        break;
                    };
                    if (is_exact_target) try Formatter.printProbeSource(terminal, allocator, &pool, &ast_cache, entry, abs_root_id);
                }
            }
        }
    }

    if (config.lib_merge_mode) {
        const merge_sort_ctx = SortContext{ .p = &pool, .r = registry.items };
        mem.sortUnstable(usize, master_task_indices.items, merge_sort_ctx, SortContext.lessThan);
        try terminal.writer.writeAll("\n--- Merged Library Index ---\n");
        if (!config.summary_only) {
            for (master_task_indices.items) |idx| {
                if (registry.items[idx].coord.node == .root) continue;
                try Formatter.printApiEntry(terminal, &pool, registry.items[idx], &fqn_writer, 0, 0);
            }
        }

        const m_breakdown = try Formatter.calculateBreakdown(allocator, &pool, registry.items, master_task_indices.items);
        defer m_breakdown.deinit(allocator);

        if (m_breakdown.entries.len > 0) try Formatter.printStats(terminal, m_breakdown.entries);

        var m_entry_count: usize = 0;
        for (master_task_indices.items) |idx| if (registry.items[idx].coord.node != .root) {
            m_entry_count += 1;
        };

        try terminal.writer.print("\nTotal Merged Entries: {d}", .{m_entry_count});
        if (m_breakdown.total_pub_hidden > 0) try terminal.writer.print(" (+{d} items)", .{m_breakdown.total_pub_hidden});
        if (m_breakdown.total_priv_hidden > 0) try terminal.writer.print(" {{+{d} items}}", .{m_breakdown.total_priv_hidden});
        try terminal.writer.writeAll("\n");
    }

    if (config.debug_mode) {
        try logic_metrics.printPerformanceReport(terminal.writer, .{
            .reg_count = registry.items.len,
            .reg_cap = registry.capacity,
            .pool_count = pool.map.count(),
            .pool_cap = pool.map.capacity(),
            .ast_count = ast_cache.map.count(),
            .ast_limit = ast_cache.capacity,
            .visited_count = visited.count(),
            .visited_cap = visited.capacity(),
            .ws_len = workspace_buf.len,
            .fqn_len = fqn_writer.written().len,
            .fqn_cap = fqn_writer.toArrayList().capacity,
        });
    }
}

fn printScanHeader(terminal: *Terminal, spec: CLI.ScanSpec, idx: usize, allocator: Allocator, root_name: []const u8) !void {
    const stdout = terminal.writer;
    const depth_str = if (spec.depth) |d| (if (d == CLI.UNLIMITED_DEPTH) "Unlimited" else try fmt.allocPrint(allocator, "{d}", .{d})) else "Unlimited";
    try stdout.print("\n--- Scan {d} Index (Depth: {s}, Scopes: ", .{ idx, depth_str });
    if (spec.scopes.items.len == 0) {
        try stdout.writeAll(root_name);
    } else {
        for (spec.scopes.items, 0..) |s, s_idx| {
            try stdout.print("{s}{s}", .{ s, if (s_idx < spec.scopes.items.len - 1) "," else "" });
        }
    }

    var modes = ArrayList([]const u8).empty;
    defer modes.deinit(allocator);
    if (spec.is_search) {
        const kw_joined = try mem.join(allocator, ", ", spec.search_terms.items);
        defer allocator.free(kw_joined);
        try modes.append(allocator, try fmt.allocPrint(allocator, "Search ({s})", .{kw_joined}));
    }
    if (spec.flagged_deprecated) try modes.append(allocator, "Flagged Deprecated");
    if (spec.exclude_layer1) try modes.append(allocator, "Filter Layer 1");

    if (modes.items.len > 0) {
        try stdout.writeAll(", Mode: ");
        for (modes.items, 0..) |m, m_idx| {
            try stdout.writeAll(m);
            if (m_idx < modes.items.len - 1) try stdout.writeAll(", ");
            if (spec.is_search and m_idx == 0) allocator.free(m);
        }
    }
    try stdout.writeAll(") ---\n");
}

fn printScanSummary(
    terminal: *Terminal,
    task_indices: []const usize,
    items: []const Types.ApiEntry,
    total_pub_hidden: usize,
    total_priv_hidden: usize,
) !void {
    var entry_count: usize = 0;
    for (task_indices) |idx| if (items[idx].coord.node != .root) {
        entry_count += 1;
    };

    try terminal.writer.print("\nScan {s}: {d}", .{ if (entry_count == 1) "Entry" else "Entries", entry_count });
    if (total_pub_hidden > 0) try terminal.writer.print(" (+{d} items)", .{total_pub_hidden});
    if (total_priv_hidden > 0) try terminal.writer.print(" {{+{d} items}}", .{total_priv_hidden});
    try terminal.writer.writeAll("\n");
}
