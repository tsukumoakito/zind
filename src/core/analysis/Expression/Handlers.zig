const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const ascii = std.ascii;
const Ast = std.zig.Ast;
const ArrayList = std.ArrayList;
const StringHashMap = std.array_hash_map.String;

const Context = @import("../Context.zig");
const Expression = @import("../Expression.zig");
const Formatter = @import("../Formatter.zig");
const Walker = @import("../Scanner/Walker.zig");
const Types = @import("../Types.zig");

pub fn handleBlock(
    ctx: Context.AnalysisContext,
    tree: *const Ast,
    node: Ast.Node.Index,
    file_path: []const u8,
    prefix_parts: []const Types.StringId,
    scope: Types.SymbolScope,
) anyerror!void {
    var buf: [2]Ast.Node.Index = undefined;
    if (tree.blockStatements(&buf, node)) |stmts| {
        try Walker.walkNodes(ctx, tree, stmts, file_path, prefix_parts, scope);
    }
}

pub fn handleIf(
    ctx: Context.AnalysisContext,
    tree: *const Ast,
    node: Ast.Node.Index,
    file_path: []const u8,
    prefix_parts: []const Types.StringId,
    scope: Types.SymbolScope,
) anyerror!void {
    if (tree.fullIf(node)) |f| {
        const cond_src = tree.getNodeSource(f.ast.cond_expr);
        const cleaned = try Formatter.cleanConditionLabel(ctx.allocator, cond_src);
        defer ctx.allocator.free(cleaned);

        const eval = evaluateCondition(ctx, cleaned);

        const current_prefix = if (ctx.current_cond_id) |id| ctx.pool.get(id) else "";

        if (eval != .definitely_false) {
            const then_assembled = if (current_prefix.len > 0)
                try fmt.bufPrint(ctx.workspace_buf, "{s} and {s}", .{ current_prefix, cleaned })
            else
                cleaned;
            const then_id = try ctx.pool.getOrPut(ctx.allocator, then_assembled);
            try Expression.scanExpression(ctx.withCond(then_id), tree, f.ast.then_expr, file_path, prefix_parts, scope);
        }

        if (f.ast.else_expr.unwrap()) |el| {
            if (eval != .definitely_true) {
                const else_assembled = if (current_prefix.len > 0)
                    try fmt.bufPrint(ctx.workspace_buf, "{s} and else (not ({s}))", .{ current_prefix, cleaned })
                else
                    try fmt.bufPrint(ctx.workspace_buf, "else (not ({s}))", .{cleaned});
                const else_id = try ctx.pool.getOrPut(ctx.allocator, else_assembled);
                try Expression.scanExpression(ctx.withCond(else_id), tree, el, file_path, prefix_parts, scope);
            }
        }
    }
}

pub fn handleSwitch(
    ctx: Context.AnalysisContext,
    tree: *const Ast,
    node: Ast.Node.Index,
    file_path: []const u8,
    prefix_parts: []const Types.StringId,
    scope: Types.SymbolScope,
) anyerror!void {
    if (tree.fullSwitch(node)) |sw| {
        const switch_val_src = tree.getNodeSource(sw.ast.condition);
        const cleaned_val = try Formatter.cleanConditionLabel(ctx.allocator, switch_val_src);
        defer ctx.allocator.free(cleaned_val);

        const control_type = identifyControlType(cleaned_val);

        for (sw.ast.cases) |case_node| {
            if (tree.fullSwitchCase(case_node)) |sc| {
                var labels_buf = ArrayList(u8).empty;
                defer labels_buf.deinit(ctx.allocator);

                var is_else = false;
                if (sc.ast.values.len == 0) {
                    try labels_buf.appendSlice(ctx.allocator, "else");
                    is_else = true;
                } else {
                    for (sc.ast.values, 0..) |v_node, i| {
                        if (i > 0) try labels_buf.appendSlice(ctx.allocator, ", ");
                        try labels_buf.appendSlice(ctx.allocator, tree.getNodeSource(v_node));
                    }
                }
                const case_labels = labels_buf.items;

                if (shouldSkipCase(ctx, control_type, case_labels, is_else)) continue;

                const target_cleaned = try Formatter.cleanConditionLabel(
                    ctx.allocator,
                    tree.getNodeSource(sc.ast.target_expr),
                );
                defer ctx.allocator.free(target_cleaned);

                const current_prefix = if (ctx.current_cond_id) |id| ctx.pool.get(id) else "";

                const switch_line = if (mem.find(u8, target_cleaned, "{...}") != null)
                    try fmt.bufPrint(ctx.workspace_buf, "{s} is {s} >>> {s}", .{ cleaned_val, target_cleaned, case_labels })
                else
                    try fmt.bufPrint(ctx.workspace_buf, "{s} is {s}", .{ cleaned_val, target_cleaned });
                const switch_line_id = try ctx.pool.getOrPut(ctx.allocator, switch_line);

                const final_cond_id = if (current_prefix.len > 0) blk: {
                    const final_assembled = try fmt.bufPrint(ctx.workspace_buf, "{s} and {s}", .{ current_prefix, ctx.pool.get(switch_line_id) });
                    break :blk try ctx.pool.getOrPut(ctx.allocator, final_assembled);
                } else switch_line_id;

                try Expression.scanExpression(ctx.withCond(final_cond_id), tree, sc.ast.target_expr, file_path, prefix_parts, scope);
            }
        }
    }
}

pub fn handleReturn(
    ctx: Context.AnalysisContext,
    tree: *const Ast,
    node: Ast.Node.Index,
    file_path: []const u8,
    prefix_parts: []const Types.StringId,
    scope: Types.SymbolScope,
) anyerror!void {
    if (tree.nodeData(node).opt_node.unwrap()) |ret_val| {
        try Expression.scanExpression(ctx, tree, ret_val, file_path, prefix_parts, scope);
    }
}

const EvalResult = enum { definitely_true, definitely_false, unknown };
const ControlType = enum { os, arch, libc, other };

fn evaluateCondition(ctx: Context.AnalysisContext, cond: []const u8) EvalResult {
    if (ctx.target_os) |target| {
        if (mem.find(u8, cond, "native_os") != null or mem.find(u8, cond, "builtin.os.tag") != null or mem.find(u8, cond, "os.tag") != null) {
            const has_target = mem.find(u8, cond, target) != null;
            const is_eq = mem.find(u8, cond, "==") != null;
            const is_ne = mem.find(u8, cond, "!=") != null;

            if (is_eq and !has_target) return .definitely_false;
            if (is_ne and has_target) return .definitely_false;
            if (is_eq and has_target) return .definitely_true;
        }
    }

    if (ctx.target_arch) |target| {
        if (mem.find(u8, cond, "native_arch") != null or mem.find(u8, cond, "builtin.cpu.arch") != null or mem.find(u8, cond, "cpu.arch") != null) {
            const has_target = mem.find(u8, cond, target) != null;
            const is_eq = mem.find(u8, cond, "==") != null;
            const is_ne = mem.find(u8, cond, "!=") != null;

            if (is_eq and !has_target) return .definitely_false;
            if (is_ne and has_target) return .definitely_false;
            if (is_eq and has_target) return .definitely_true;
        }
    }

    if (mem.find(u8, cond, "use_libc") != null or mem.find(u8, cond, "builtin.link_libc") != null) {
        if (ctx.link_libc) |manual_link| {
            return if (manual_link) .definitely_true else .definitely_false;
        }
        if (ctx.target_os) |os| {
            if (mem.eql(u8, os, "windows") or mem.eql(u8, os, "wasi")) return .definitely_true;
        }
    }

    return .unknown;
}

fn identifyControlType(src: []const u8) ControlType {
    if (mem.find(u8, src, "native_os") != null or mem.find(u8, src, "os.tag") != null or mem.find(u8, src, "builtin.os.tag") != null) return .os;
    if (mem.find(u8, src, "native_arch") != null or mem.find(u8, src, "cpu.arch") != null or mem.find(u8, src, "builtin.cpu.arch") != null) return .arch;
    if (mem.find(u8, src, "use_libc") != null or mem.find(u8, src, "builtin.link_libc") != null) return .libc;
    return .other;
}

fn shouldSkipCase(ctx: Context.AnalysisContext, ctype: ControlType, labels: []const u8, is_else: bool) bool {
    switch (ctype) {
        .os => if (ctx.target_os) |target| {
            const matched = mem.find(u8, labels, target) != null;
            if (is_else) return false;
            return !matched;
        },
        .arch => if (ctx.target_arch) |target| {
            const matched = mem.find(u8, labels, target) != null;
            if (is_else) return false;
            return !matched;
        },
        .libc => {
            const wants_libc = ctx.link_libc orelse blk: {
                if (ctx.target_os) |os| {
                    if (mem.eql(u8, os, "windows") or mem.eql(u8, os, "wasi")) break :blk true;
                }
                return false;
            };
            const case_true = mem.find(u8, labels, "true") != null;
            if (wants_libc and !case_true and !is_else) return true;
            if (!wants_libc and case_true) return true;
        },
        else => {},
    }
    return false;
}
