const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const Io = std.Io;
const Ast = std.zig.Ast;
const ArrayList = std.ArrayList;
const StringHashMap = std.array_hash_map.String;
const Allocator = mem.Allocator;
const Dir = Io.Dir;
const Alignment = mem.Alignment;

const PathFinder = @import("../../env/PathFinder.zig");
const AstUtils = @import("../AstUtils.zig");
const Context = @import("../Context.zig");
const Expression = @import("../Expression.zig");
const Resolver = @import("../Resolver.zig");
const Types = @import("../Types.zig");
const Utils = @import("../Utils.zig");
const Walker = @import("Walker.zig");

pub fn processFile(
    ctx: Context.AnalysisContext,
    file_path: []const u8,
    prefix_parts: []const Types.StringId,
) anyerror!void {
    if (ctx.debug_mode) {
        try ctx.terminal.writer.print("DEBUG: [File] {s} | [FQN] ", .{file_path});
        for (prefix_parts) |id| try ctx.terminal.writer.print("{s}.", .{ctx.pool.get(id)});
        try ctx.terminal.writer.writeAll("\n");
    }

    if (prefix_parts.len > 128) return;

    const file_id = if (ctx.path_cache.get(file_path)) |id| id else blk: {
        const resolved = try PathFinder.resolveAbsolutePath(ctx.allocator, ctx.io, file_path);
        defer ctx.allocator.free(resolved);
        const id = try ctx.pool.getOrPut(ctx.allocator, resolved);
        try ctx.path_cache.put(ctx.allocator, try ctx.allocator.dupe(u8, file_path), id);
        break :blk id;
    };
    const abs_path = ctx.pool.get(file_id);

    const key = Types.VisitedKey{
        .file_id = file_id,
        .fqn_parts = prefix_parts,
        .cond_id = ctx.current_cond_id,
    };

    if (ctx.visited.contains(key)) return;
    try ctx.visited.put(key, {});
    ctx.metrics.recordFile();

    const tree = if (ctx.ast_cache.get(file_id)) |t| t else blk: {
        const source: [:0]u8 = Dir.readFileAllocOptions(
            Dir.cwd(),
            ctx.io,
            abs_path,
            ctx.allocator,
            .unlimited,
            Alignment.of(u8),
            0,
        ) catch |err| {
            if (err == error.FileNotFound) {
                const name = Dir.path.basename(abs_path);
                if (mem.eql(u8, name, "root") or mem.eql(u8, name, "builtin") or mem.eql(u8, name, "compiler_rt")) return;
            }
            try ctx.terminal.writer.print("[ERROR] Failed to read source file '{s}': {s}\n", .{ abs_path, @errorName(err) });
            return;
        };

        const t = try ctx.allocator.create(Ast);
        t.* = try Ast.parse(ctx.allocator, source, .zig);
        try ctx.ast_cache.put(ctx.allocator, file_id, t, ctx.stack.items);
        break :blk t;
    };

    var symbols = StringHashMap(Ast.Node.Index).empty;
    defer symbols.deinit(ctx.allocator);
    const root_decls = tree.rootDecls();
    for (root_decls) |node| {
        if (tree.fullVarDecl(node)) |v| {
            const name = tree.tokenSlice(v.ast.mut_token + 1);
            try symbols.put(ctx.allocator, name, node);
        } else if (tree.nodeTag(node) == .fn_decl) {
            var buf: [1]Ast.Node.Index = undefined;
            if (tree.fullFnProto(&buf, tree.nodeData(node).node_and_node.@"0")) |proto| {
                if (proto.name_token) |nt| try symbols.put(ctx.allocator, tree.tokenSlice(nt), node);
            }
        }
    }

    try Walker.walkNodes(ctx, tree, root_decls, abs_path, prefix_parts, .{ .map = &symbols });
}

pub fn processFileWithMember(
    ctx: Context.AnalysisContext,
    file_path: []const u8,
    member_name: []const u8,
    prefix_parts: []const Types.StringId,
) anyerror!void {
    if (ctx.debug_mode) {
        try ctx.terminal.writer.print("DEBUG: [File] {s} | [Member] {s} | [FQN] ", .{ file_path, member_name });
        for (prefix_parts) |id| try ctx.terminal.writer.print("{s}.", .{ctx.pool.get(id)});
        try ctx.terminal.writer.writeAll("\n");
    }

    const file_id = if (ctx.path_cache.get(file_path)) |id| id else blk: {
        const resolved = try PathFinder.resolveAbsolutePath(ctx.allocator, ctx.io, file_path);
        defer ctx.allocator.free(resolved);
        const id = try ctx.pool.getOrPut(ctx.allocator, resolved);
        try ctx.path_cache.put(ctx.allocator, try ctx.allocator.dupe(u8, file_path), id);
        break :blk id;
    };
    const abs_path = ctx.pool.get(file_id);

    const tree = if (ctx.ast_cache.get(file_id)) |t| t else blk: {
        const source: [:0]u8 = Dir.readFileAllocOptions(
            Dir.cwd(),
            ctx.io,
            abs_path,
            ctx.allocator,
            .unlimited,
            Alignment.of(u8),
            0,
        ) catch |err| {
            if (err == error.FileNotFound) {
                const name = Dir.path.basename(abs_path);
                if (mem.eql(u8, name, "root") or mem.eql(u8, name, "builtin") or mem.eql(u8, name, "compiler_rt")) return;
            }
            try ctx.terminal.writer.print("[ERROR] Failed to read source file '{s}': {s}\n", .{ abs_path, @errorName(err) });
            return;
        };

        const t = try ctx.allocator.create(Ast);
        t.* = try Ast.parse(ctx.allocator, source, .zig);
        try ctx.ast_cache.put(ctx.allocator, file_id, t, ctx.stack.items);
        break :blk t;
    };

    const decls = tree.rootDecls();
    var symbols = StringHashMap(Ast.Node.Index).empty;
    defer symbols.deinit(ctx.allocator);
    var target: ?Ast.Node.Index = null;

    for (decls) |node| {
        if (tree.fullVarDecl(node)) |v| {
            const name = tree.tokenSlice(v.ast.mut_token + 1);
            try symbols.put(ctx.allocator, name, node);
            if (mem.eql(u8, name, member_name)) target = node;
        } else if (tree.nodeTag(node) == .fn_decl) {
            var buf: [1]Ast.Node.Index = undefined;
            if (tree.fullFnProto(
                &buf,
                tree.nodeData(node).node_and_node.@"0",
            )) |proto| if (proto.name_token) |nt| {
                const name = tree.tokenSlice(nt);
                try symbols.put(ctx.allocator, name, node);
                if (mem.eql(u8, name, member_name)) target = node;
            };
        }
    }

    if (target) |node| {
        const node_id = Types.NodeIdentity{ .path_id = file_id, .node = node };
        for (ctx.stack.items) |s| if (s.path_id == node_id.path_id and s.node == node_id.node) return;
        try ctx.stack.append(ctx.allocator, node_id);
        defer _ = ctx.stack.pop();

        var trace = try Resolver.resolveTrace(
            ctx.allocator,
            ctx.io,
            ctx.ast_cache,
            ctx.path_cache,
            tree,
            node,
            abs_path,
            &symbols,
            ctx.inherited_dep_id,
            0,
            ctx.root_path_id,
            ctx.pool,
            ctx.workspace_buf,
        );
        defer trace.deinit(ctx.allocator);

        var current_len: usize = 0;
        var count: usize = 0;
        for (trace.steps.items) |step| {
            if (step.dep_id) |d_id| {
                const d_str = ctx.pool.get(d_id);
                var d_it = mem.splitSequence(u8, d_str, " *** ");
                while (d_it.next()) |segment| {
                    const trimmed = mem.trim(u8, segment, " ");
                    if (trimmed.len == 0) continue;
                    if (mem.find(u8, ctx.workspace_buf[0..current_len], trimmed) != null) continue;

                    if (current_len > 0) {
                        if (current_len + 5 > ctx.workspace_buf.len) break;
                        @memcpy(ctx.workspace_buf[current_len..][0..5], " *** ");
                        current_len += 5;
                    }
                    if (current_len + trimmed.len > ctx.workspace_buf.len) break;
                    @memcpy(ctx.workspace_buf[current_len..][0..trimmed.len], trimmed);
                    current_len += trimmed.len;
                    count += 1;
                }
            }
        }

        const joined_dep_id = if (count > 0) try ctx.pool.getOrPut(ctx.allocator, ctx.workspace_buf[0..current_len]) else null;
        const final_dep_id = try Utils.mergeDepId(ctx.allocator, ctx.pool, ctx.inherited_dep_id, joined_dep_id, ctx.workspace_buf);

        const next_ctx = ctx.withDep(final_dep_id);
        const scope = Types.SymbolScope{ .map = &symbols };

        if (tree.fullVarDecl(node)) |v| {
            if (v.ast.init_node.unwrap()) |init| {
                try Expression.scanExpression(next_ctx, tree, init, abs_path, prefix_parts, scope);
            }
        } else if (tree.nodeTag(node) == .fn_decl) {
            if (AstUtils.isForwardingFactory(tree.*, node)) |target_expr| {
                try Expression.scanExpression(next_ctx, tree, target_expr, abs_path, prefix_parts, scope);
            } else if (AstUtils.isTypeFactory(tree.*, node)) |cont| {
                try Expression.scanExpression(next_ctx, tree, cont, abs_path, prefix_parts, scope);
            }
        }
    }
}
