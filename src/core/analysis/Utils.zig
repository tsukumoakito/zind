const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;
const Ast = std.zig.Ast;

const CLI = @import("../env/CLI.zig");
const Types = @import("Types.zig");

pub fn sortStrings(_: void, lhs: []const u8, rhs: []const u8) bool {
    return mem.lessThan(u8, lhs, rhs);
}

pub fn containsDeprecated(comment: ?[]const u8) bool {
    const c = comment orelse return false;
    return ascii.findIgnoreCase(c, "deprecated") != null;
}

pub fn containsAllKeywordsDirect(
    full_fqn: []const u8,
    comment: ?[]const u8,
    rhs: ?[]const u8,
    terms: []const []const u8,
) bool {
    if (terms.len == 0) return false;

    for (terms) |term| {
        var found = false;

        if (ascii.findIgnoreCase(full_fqn, term) != null) {
            found = true;
        } else if (comment) |c| {
            if (ascii.findIgnoreCase(c, term) != null) found = true;
        } else if (rhs) |r| {
            if (ascii.findIgnoreCase(r, term) != null) found = true;
        }

        if (!found) return false;
    }

    return true;
}

pub fn findMatchId(
    prefix: []const Types.StringId,
    name: Types.StringId,
    pool: *const Types.StringPool,
    filters: []const []const u8,
    depth_limit: ?usize,
) ?[]const u8 {
    const fqn_len = prefix.len + 1;

    if (filters.len == 0) {
        if (depth_limit) |l| return if (fqn_len - 1 <= l) "std" else null;
        return "std";
    }

    for (filters) |f| {
        var it = mem.splitScalar(u8, f, '.');
        var filter_len: usize = 0;
        while (it.next()) |_| filter_len += 1;

        if (fqn_len < filter_len) continue;

        if (matchFqnWithFilter(prefix, name, pool, f)) |m| {
            if (depth_limit) |l| {
                if (fqn_len - filter_len <= l) return m;
            } else return m;
        }
    }

    return null;
}

pub fn isExactMatchId(
    prefix: []const Types.StringId,
    name: Types.StringId,
    pool: *const Types.StringPool,
    filters: []const []const u8,
) bool {
    if (filters.len == 0) return false;

    const fqn_len = prefix.len + 1;
    for (filters) |f| {
        var it = mem.splitScalar(u8, f, '.');
        var filter_segments: usize = 0;
        while (it.next()) |_| filter_segments += 1;

        if (filter_segments != fqn_len) continue;

        if (matchFqnWithFilter(prefix, name, pool, f) != null) return true;
    }
    return false;
}

pub fn isScopeParentId(
    prefix: []const Types.StringId,
    name: Types.StringId,
    pool: *const Types.StringPool,
    filters: []const []const u8,
) bool {
    const fqn_len = prefix.len + 1;

    for (filters) |f| {
        var it = mem.splitScalar(u8, f, '.');
        var i: usize = 0;
        var match = true;

        while (it.next()) |part| : (i += 1) {
            if (i >= fqn_len) return true;

            const fqn_part = if (i < prefix.len) pool.get(prefix[i]) else pool.get(name);
            if (!mem.eql(u8, fqn_part, part)) {
                match = false;
                break;
            }
        }

        if (match) continue;
    }

    return false;
}

pub fn isLayer1Id(
    prefix: []const Types.StringId,
    name: Types.StringId,
    pool: *const Types.StringPool,
    root_name_id: Types.StringId,
) bool {
    const parts_len = prefix.len + 1;
    if (parts_len < 2) return false;

    if (prefix[0] != root_name_id) return false;

    const second_id = if (prefix.len >= 2) prefix[1] else name;
    const second_name = pool.get(second_id);

    for (CLI.layer1_modules) |m| {
        if (mem.eql(u8, second_name, m)) return true;
    }

    return false;
}

pub fn canRecurseId(
    fqn: []const Types.StringId,
    pool: *const Types.StringPool,
    filter: []const u8,
    depth_limit: ?usize,
) bool {
    if (depth_limit == null) return true;
    const l = depth_limit.?;

    var it = mem.splitScalar(u8, filter, '.');
    var filter_len: usize = 0;
    while (it.next()) |_| filter_len += 1;

    if (filter_len > fqn.len) {
        it = mem.splitScalar(u8, filter, '.');
        for (fqn) |id| {
            const p = it.next() orelse return false;
            if (!mem.eql(u8, pool.get(id), p)) return false;
        }
        return true;
    }

    return (fqn.len - filter_len) < l;
}

pub fn matchFqnWithFilter(
    prefix: []const Types.StringId,
    name: Types.StringId,
    pool: *const Types.StringPool,
    filter: []const u8,
) ?[]const u8 {
    var it = mem.splitScalar(u8, filter, '.');
    var i: usize = 0;
    const fqn_len = prefix.len + 1;

    while (it.next()) |part| : (i += 1) {
        if (i >= fqn_len) return null;

        const fqn_part = if (i < prefix.len) pool.get(prefix[i]) else pool.get(name);
        if (!mem.eql(u8, fqn_part, part)) return null;
    }

    return filter;
}

pub fn getDeprecatedComment(allocator: Allocator, tree: *const Ast, node: Ast.Node.Index) !?[]const u8 {
    var i = tree.firstToken(node);
    var lines = ArrayList([]const u8).empty;
    defer lines.deinit(allocator);

    while (i > 0) {
        i -= 1;
        const tag = tree.tokenTag(i);
        if (tag != .doc_comment and tag != .container_doc_comment) break;
        var clean = mem.trimStart(u8, tree.tokenSlice(i), "/ ");
        clean = mem.trimEnd(u8, clean, " \r\n");
        try lines.append(allocator, clean);
    }
    if (lines.items.len == 0) return null;

    mem.reverse([]const u8, lines.items);
    var start: ?usize = null;
    for (lines.items, 0..) |l, idx| if (ascii.findIgnoreCase(l, "deprecated") != null) {
        start = idx;
        var s = idx;
        while (s > 0) {
            s -= 1;
            const p = lines.items[s];
            if (p.len == 0 or mem.endsWith(u8, p, ".") or mem.endsWith(u8, p, ";")) {
                start = s + 1;
                break;
            }
            if (s == 0) start = 0;
        }
        break;
    };

    return if (start) |s| try mem.join(allocator, " ", lines.items[s..]) else null;
}

pub fn mergeDepId(
    allocator: Allocator,
    pool: *Types.StringPool,
    p_id: ?Types.StringId,
    c_id: ?Types.StringId,
    workspace: []u8,
) !?Types.StringId {
    if (p_id == null and c_id == null) return null;

    var current_len: usize = 0;
    var count: usize = 0;

    if (p_id) |pid| {
        const p_str = pool.get(pid);
        var it = mem.splitSequence(u8, p_str, " *** ");
        while (it.next()) |seg| {
            const s = mem.trim(u8, seg, " ");
            if (s.len == 0) continue;
            if (current_len > 0) {
                if (current_len + 5 > workspace.len) break;
                @memcpy(workspace[current_len..][0..5], " *** ");
                current_len += 5;
            }
            if (current_len + s.len > workspace.len) break;
            @memcpy(workspace[current_len..][0..s.len], s);
            current_len += s.len;
            count += 1;
        }
    }

    if (c_id) |cid| {
        const c_str = pool.get(cid);
        var it = mem.splitSequence(u8, c_str, " *** ");
        while (it.next()) |seg| {
            const s = mem.trim(u8, seg, " ");
            if (s.len == 0) continue;

            const current_assembly = workspace[0..current_len];
            if (mem.find(u8, current_assembly, s) != null) continue;

            if (current_len > 0) {
                if (current_len + 5 > workspace.len) break;
                @memcpy(workspace[current_len..][0..5], " *** ");
                current_len += 5;
            }
            if (current_len + s.len > workspace.len) break;
            @memcpy(workspace[current_len..][0..s.len], s);
            current_len += s.len;
            count += 1;
        }
    }

    if (count == 0) return null;
    return try pool.getOrPut(allocator, workspace[0..current_len]);
}

pub fn hasComplexStructure(src: []const u8, start: usize) bool {
    var d: usize = 0;
    var sc: usize = 0;
    var cc: usize = 0;
    var j = start;

    while (j < src.len) : (j += 1) {
        const c = src[j];

        if (c == '{') {
            d += 1;
        } else if (c == '}') {
            if (d > 0) d -= 1;
            if (d == 0) break;
        }

        if (d == 1) {
            if (c == ';') sc += 1;
            if (c == ',') cc += 1;

            if (mem.startsWith(u8, src[j..], "return self.")) return true;
        }

        if (d > 1) return true;
    }

    return sc >= 2 or cc >= 7;
}

pub fn skipBraces(src: []const u8, start: usize) usize {
    var d: usize = 0;
    var j = start;
    while (j < src.len) : (j += 1) {
        if (src[j] == '{') d += 1 else if (src[j] == '}') {
            if (d > 0) d -= 1;
            if (d == 0) return j;
        }
    }
    return j;
}

pub fn joinIds(allocator: Allocator, pool: *const Types.StringPool, ids: []const Types.StringId) Allocator.Error![]u8 {
    var total_len: usize = 0;
    for (ids, 0..) |id, i| {
        total_len += pool.get(id).len;
        if (i + 1 < ids.len) total_len += 1;
    }
    const res = try allocator.alloc(u8, total_len);
    var pos: usize = 0;
    for (ids, 0..) |id, i| {
        const s = pool.get(id);
        @memcpy(res[pos..][0..s.len], s);
        pos += s.len;
        if (i + 1 < ids.len) {
            res[pos] = '.';
            pos += 1;
        }
    }
    return res;
}
