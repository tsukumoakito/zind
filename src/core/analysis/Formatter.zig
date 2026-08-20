const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const fmt = std.fmt;
const Io = std.Io;
const Ast = std.zig.Ast;
const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;
const Dir = Io.Dir;
const Writer = Io.Writer;
const Terminal = Io.Terminal;
const StringHashMap = std.array_hash_map.String;

const AstUtils = @import("AstUtils.zig");
const Context = @import("Context.zig");
const Types = @import("Types.zig");
const Utils = @import("Utils.zig");

const Styles = struct {
    const fqn = "\x1b[1;38;5;81m";
    const private_fqn = "\x1b[38;5;244m";
    const breakdown_fqn = "\x1b[1;38;5;110m";
    const hidden_fqn = "\x1b[38;5;137m";
    const condition = "\x1b[38;5;222m";
    const arrow = "\x1b[38;5;244m";
    const deprecated = "\x1b[1;38;5;203m";
    const hidden = "\x1b[38;5;170m";
    const private_hidden = "\x1b[38;5;172m";
    const operator = "\x1b[38;5;250m";
    const reset = "\x1b[0m";
};

fn apply(terminal: *Terminal, style: []const u8) void {
    if (terminal.mode == .no_color) return;
    terminal.writer.writeAll(style) catch {};
}

pub const BreakdownEntry = struct {
    name: []const u8,
    count: usize,
    hidden: usize = 0,
    priv_count: usize = 0,
    priv_hidden: usize = 0,
};

pub const BreakdownResult = struct {
    entries: []BreakdownEntry,
    total_pub_hidden: usize,
    total_priv_hidden: usize,

    pub fn deinit(self: BreakdownResult, allocator: Allocator) void {
        for (self.entries) |e| allocator.free(e.name);
        allocator.free(self.entries);
    }
};

pub fn calculateBreakdown(
    allocator: Allocator,
    pool: *const Types.StringPool,
    items: []const Types.ApiEntry,
    task_indices: []const usize,
) !BreakdownResult {
    if (task_indices.len == 0) return .{
        .entries = &.{},
        .total_pub_hidden = 0,
        .total_priv_hidden = 0,
    };

    var min_len: usize = 1000;
    var found_any = false;
    for (task_indices) |idx| {
        const entry = items[idx];
        if (entry.coord.node == .root) continue;
        if (entry.fqn_parts.len > 0) {
            min_len = @min(min_len, entry.fqn_parts.len);
            found_any = true;
        }
    }

    if (!found_any) return .{
        .entries = &.{},
        .total_pub_hidden = 0,
        .total_priv_hidden = 0,
    };

    var min_len_count: usize = 0;
    for (task_indices) |idx| {
        const entry = items[idx];
        if (entry.coord.node == .root) continue;
        if (entry.fqn_parts.len == min_len) min_len_count += 1;
    }

    const target_depth = if (min_len_count == 1) min_len + 1 else min_len;

    const Stats = struct {
        pub_visible: usize = 0,
        pub_hidden: usize = 0,
        priv_visible: usize = 0,
        priv_hidden: usize = 0,
    };

    var counts = StringHashMap(Stats).empty;
    defer counts.deinit(allocator);

    for (task_indices, 0..) |reg_idx, task_ptr| {
        const entry = items[reg_idx];
        if (entry.coord.node == .root) continue;

        const actual_depth = if (entry.fqn_parts.len < target_depth) entry.fqn_parts.len else target_depth;
        const key = try Utils.joinIds(allocator, pool, entry.fqn_parts[0..actual_depth]);
        const res = try counts.getOrPut(allocator, key);

        if (res.found_existing) {
            allocator.free(key);
        } else {
            res.value_ptr.* = .{};
        }

        if (entry.is_private) res.value_ptr.priv_visible += 1 else res.value_ptr.pub_visible += 1;

        if (entry.fqn_parts.len == target_depth) {
            var total_pub_children: usize = 0;
            var total_priv_children: usize = 0;
            var j = reg_idx + 1;
            while (j < items.len) : (j += 1) {
                const other = items[j];
                if (other.fqn_parts.len <= entry.fqn_parts.len) break;
                if (!mem.eql(Types.StringId, other.fqn_parts[0..entry.fqn_parts.len], entry.fqn_parts)) break;
                if (other.is_private) total_priv_children += 1 else total_pub_children += 1;
            }

            var visible_pub_children: usize = 0;
            var visible_priv_children: usize = 0;
            var k = task_ptr + 1;
            while (k < task_indices.len) : (k += 1) {
                const next_reg_idx = task_indices[k];
                const other = items[next_reg_idx];
                if (other.fqn_parts.len <= entry.fqn_parts.len) break;
                if (!mem.eql(Types.StringId, other.fqn_parts[0..entry.fqn_parts.len], entry.fqn_parts)) break;
                if (other.is_private) visible_priv_children += 1 else visible_pub_children += 1;
            }

            res.value_ptr.pub_hidden += (total_pub_children - visible_pub_children) + entry.child_count;
            res.value_ptr.priv_hidden += (total_priv_children - visible_priv_children) + entry.priv_child_count;
        }
    }

    var result_entries = try ArrayList(BreakdownEntry).initCapacity(allocator, counts.count());
    var total_pub_hidden: usize = 0;
    var total_priv_hidden: usize = 0;

    var it = counts.iterator();
    while (it.next()) |entry| {
        try result_entries.append(allocator, .{
            .name = try allocator.dupe(u8, entry.key_ptr.*),
            .count = entry.value_ptr.pub_visible,
            .hidden = entry.value_ptr.pub_hidden,
            .priv_count = entry.value_ptr.priv_visible,
            .priv_hidden = entry.value_ptr.priv_hidden,
        });
        total_pub_hidden += entry.value_ptr.pub_hidden;
        total_priv_hidden += entry.value_ptr.priv_hidden;
        allocator.free(entry.key_ptr.*);
    }

    const SortCtx = struct {
        pub fn lessThan(_: void, a: BreakdownEntry, b: BreakdownEntry) bool {
            return mem.lessThan(u8, a.name, b.name);
        }
    };
    mem.sortUnstable(BreakdownEntry, result_entries.items, {}, SortCtx.lessThan);

    return .{
        .entries = try result_entries.toOwnedSlice(allocator),
        .total_pub_hidden = total_pub_hidden,
        .total_priv_hidden = total_priv_hidden,
    };
}

pub fn printStats(
    terminal: *Terminal,
    stats: []const BreakdownEntry,
) !void {
    if (stats.len == 0) return;
    const stdout = terminal.writer;

    try stdout.writeAll("\nBreakdown:\n");
    for (stats) |s| {
        if (s.count > 0) {
            apply(terminal, Styles.breakdown_fqn);
        } else {
            apply(terminal, Styles.hidden_fqn);
        }
        try stdout.print("  {s}", .{s.name});
        apply(terminal, Styles.reset);

        if (s.count > 0) {
            const pub_label = if (s.count == 1) "item" else "items";
            try stdout.print(": {d} {s}", .{ s.count, pub_label });
        }

        if (s.hidden > 0) {
            const h_label = if (s.hidden == 1) "item" else "items";
            try stdout.writeAll(" ");
            apply(terminal, Styles.hidden);
            try stdout.print("(+{d} {s})", .{ s.hidden, h_label });
            apply(terminal, Styles.reset);
        }

        if (s.priv_count > 0) {
            const p_label = if (s.priv_count == 1) "item" else "items";
            try stdout.writeAll(" ");
            apply(terminal, Styles.private_fqn);
            try stdout.print("{{{d} {s}}}", .{ s.priv_count, p_label });
            apply(terminal, Styles.reset);
        }

        if (s.priv_hidden > 0) {
            const ph_label = if (s.priv_hidden == 1) "item" else "items";
            try stdout.writeAll(" ");
            apply(terminal, Styles.private_hidden);
            try stdout.print("{{+{d} {s}}}", .{ s.priv_hidden, ph_label });
            apply(terminal, Styles.reset);
        }
        try stdout.writeAll("\n");
    }
}

pub fn printApiEntry(
    terminal: *Terminal,
    pool: *const Types.StringPool,
    entry: Types.ApiEntry,
    fqn_writer: *Io.Writer.Allocating,
    hidden_pub: usize,
    hidden_priv: usize,
) !void {
    const stdout = terminal.writer;

    if (entry.is_private) {
        apply(terminal, Styles.private_fqn);
    } else {
        apply(terminal, Styles.fqn);
    }
    try stdout.writeAll(pool.get(entry.full_fqn_id));
    apply(terminal, Styles.reset);

    if (entry.cond_id) |c_id| {
        try stdout.writeAll(" ");
        apply(terminal, Styles.condition);
        try stdout.print("[{s}]", .{pool.get(c_id)});
        apply(terminal, Styles.reset);
    }

    apply(terminal, Styles.operator);
    try stdout.writeAll(" = ");
    apply(terminal, Styles.reset);

    if (entry.trace_chain.len > 0) {
        for (entry.trace_chain, 0..) |step, i| {
            if (i > 0) {
                apply(terminal, Styles.arrow);
                try stdout.writeAll(" >>> ");
                apply(terminal, Styles.reset);
            }
            try stdout.writeAll(pool.get(step.formatted_id));
        }
    } else if (entry.rhs_id) |r_id| {
        const rhs_src = pool.get(r_id);
        const formatted = try formatApiLine(fqn_writer.allocator, rhs_src);
        defer fqn_writer.allocator.free(formatted);
        try stdout.writeAll(formatted);
    }

    if (entry.dep_id) |d_id| {
        try stdout.writeAll(" ");
        apply(terminal, Styles.deprecated);
        try stdout.print("*** {s}", .{pool.get(d_id)});
        apply(terminal, Styles.reset);
    }

    if (hidden_pub > 0) {
        const item_label = if (hidden_pub == 1) "item" else "items";
        try stdout.writeAll(" ");
        apply(terminal, Styles.hidden);
        try stdout.print("(+{d} {s})", .{ hidden_pub, item_label });
        apply(terminal, Styles.reset);
    }

    if (hidden_priv > 0) {
        const item_label = if (hidden_priv == 1) "item" else "items";
        try stdout.writeAll(" ");
        apply(terminal, Styles.private_hidden);
        try stdout.print("{{+{d} {s}}}", .{ hidden_priv, item_label });
        apply(terminal, Styles.reset);
    }

    try stdout.writeAll("\n");
}

pub fn printProbeSource(
    terminal: *Terminal,
    allocator: Allocator,
    pool: *const Types.StringPool,
    ast_cache: *const Context.AstCacheManager,
    entry: Types.ApiEntry,
    root_path_id: Types.StringId,
) !void {
    const root_path = pool.get(root_path_id);
    const base_dir = Dir.path.dirname(root_path) orelse "";

    if (entry.trace_chain.len == 0) {
        try printSingleNode(terminal, allocator, pool, ast_cache, entry.coord.file_id, entry.coord.node, null, base_dir, true);
    } else {
        for (entry.trace_chain, 0..) |step, i| {
            const is_last = (i == entry.trace_chain.len - 1);
            try printSingleNode(terminal, allocator, pool, ast_cache, step.path_id, step.node, step.formatted_id, base_dir, is_last);
        }
    }
}

fn printSingleNode(
    terminal: *Terminal,
    allocator: Allocator,
    pool: *const Types.StringPool,
    ast_cache: *const Context.AstCacheManager,
    file_id: Types.StringId,
    node: Ast.Node.Index,
    formatted_id: ?Types.StringId,
    base_dir: []const u8,
    is_last: bool,
) !void {
    const stdout = terminal.writer;
    const path = pool.get(file_id);
    const tree = ast_cache.get(file_id) orelse return;

    if (node == .root) {
        const info = AstUtils.getLineAndCount(tree.source, 0, tree.source.len);
        const label = if (formatted_id) |fid| pool.get(fid) else Dir.path.basename(path);
        try stdout.print("\nSOURCE: {s} (Full File) | LINES: {d}-{d} | ROWS: {d}\n", .{
            label,
            info.start_line,
            info.end_line,
            info.total,
        });
        try stdout.print("{s}\n", .{path});
        try stdout.writeAll("```zig\n");
        try stdout.writeAll(tree.source);
        if (tree.source.len > 0 and tree.source[tree.source.len - 1] != '\n') try stdout.writeAll("\n");
        try stdout.writeAll("```\n");
        return;
    }

    const range = AstUtils.getExtendedNodeRange(tree, node);
    const info = AstUtils.getLineAndCount(tree.source, range.start, range.end);
    const snippet = tree.source[range.start..range.end];

    const label = if (formatted_id) |fid| pool.get(fid) else blk: {
        var rel = path;
        if (mem.startsWith(u8, path, base_dir)) {
            rel = path[base_dir.len..];
            if (rel.len > 0 and (rel[0] == '/' or rel[0] == '\\')) rel = rel[1..];
        }
        break :blk rel;
    };

    try stdout.print("\nSOURCE: {s} | LINES: {d}-{d} | ROWS: {d}\n", .{
        label,
        info.start_line,
        info.end_line,
        info.total,
    });
    try stdout.print("{s}\n", .{path});
    try stdout.writeAll("```zig\n");
    try stdout.writeAll(snippet);
    if (snippet.len > 0 and snippet[snippet.len - 1] != '\n') try stdout.writeAll("\n");
    try stdout.writeAll("```\n");

    if (is_last) {
        var target_node = node;
        if (tree.fullVarDecl(node)) |v| {
            if (v.ast.init_node.unwrap()) |init| target_node = init;
        }

        if (AstUtils.getNakedImportPath(tree.*, target_node)) |imp_path| {
            const dir = Dir.path.dirname(path) orelse ".";
            const abs_imp = try Dir.path.resolve(allocator, &.{ dir, imp_path });
            defer allocator.free(abs_imp);

            const imp_path_id = try @constCast(pool).getOrPut(allocator, abs_imp);
            if (ast_cache.get(imp_path_id)) |imp_tree| {
                const f_info = AstUtils.getLineAndCount(imp_tree.source, 0, imp_tree.source.len);
                try stdout.print("\nSOURCE: {s} (Full File) | LINES: {d}-{d} | ROWS: {d}\n", .{
                    imp_path,
                    f_info.start_line,
                    f_info.end_line,
                    f_info.total,
                });
                try stdout.print("{s}\n", .{abs_imp});
                try stdout.writeAll("```zig\n");
                try stdout.writeAll(imp_tree.source);
                if (imp_tree.source.len > 0 and imp_tree.source[imp_tree.source.len - 1] != '\n') try stdout.writeAll("\n");
                try stdout.writeAll("```\n");
            }
        }
    }
}

pub fn formatApiLine(allocator: Allocator, src: []const u8) ![]const u8 {
    var list = ArrayList(u8).empty;
    defer list.deinit(allocator);
    var space = false;
    var depth: usize = 0;
    var i: usize = 0;

    while (i < src.len) {
        const c = src[i];

        if (c == '/' and i + 1 < src.len and src[i + 1] == '/') {
            while (i < src.len and src[i] != '\n') i += 1;
            continue;
        }

        if (c == '.' and i + 1 < src.len and src[i + 1] == '{') {
            const complex = Utils.hasComplexStructure(src, i + 1);
            if (depth >= 1 or complex) {
                try list.appendSlice(allocator, ".{...}");
                i = Utils.skipBraces(src, i + 1);
                if (i < src.len) i += 1;
                space = false;
                continue;
            }
        }

        if (c == '{') {
            depth += 1;
            if (depth >= 2 or Utils.hasComplexStructure(src, i)) {
                try list.appendSlice(allocator, "{...}");
                i = Utils.skipBraces(src, i);
                if (i < src.len) i += 1;
                if (depth > 0) depth -= 1;
                space = false;
                continue;
            }
            try list.append(allocator, '{');
            i += 1;
            continue;
        }

        if (c == '}') {
            if (depth > 0) depth -= 1;
            try list.append(allocator, '}');
            i += 1;
            continue;
        }

        if (ascii.isWhitespace(c)) {
            if (!space) {
                try list.append(allocator, ' ');
                space = true;
            }
            i += 1;
        } else {
            try list.append(allocator, c);
            space = false;
            i += 1;
        }
    }

    return try allocator.dupe(u8, mem.trim(u8, list.items, " "));
}

pub fn cleanConditionLabel(allocator: Allocator, src: []const u8) ![]const u8 {
    var list = ArrayList(u8).empty;
    defer list.deinit(allocator);
    var i: usize = 0;
    var space = false;

    while (i < src.len) {
        const c = src[i];

        if (c == '/' and i + 1 < src.len and src[i + 1] == '/') {
            while (i < src.len and src[i] != '\n') i += 1;
            continue;
        }

        if (c == '{') {
            try list.appendSlice(allocator, "{...}");
            var depth: usize = 1;
            i += 1;
            while (i < src.len and depth > 0) : (i += 1) {
                if (src[i] == '{') {
                    depth += 1;
                } else if (src[i] == '}') {
                    depth -= 1;
                }
            }
            space = false;
            continue;
        }

        if (c == ',') {
            if (list.items.len > 0 and list.items[list.items.len - 1] == ' ') {
                list.items.len -= 1;
            }
            try list.append(allocator, ',');
            try list.append(allocator, ' ');
            space = true;
            i += 1;
            while (i < src.len and ascii.isWhitespace(src[i])) i += 1;
            continue;
        }

        if (ascii.isWhitespace(c)) {
            if (!space) {
                try list.append(allocator, ' ');
                space = true;
            }
            i += 1;
        } else {
            try list.append(allocator, c);
            space = false;
            i += 1;
        }
    }

    return try allocator.dupe(u8, mem.trim(u8, list.items, " "));
}
