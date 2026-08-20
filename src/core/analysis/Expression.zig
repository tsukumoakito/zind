const std = @import("std");
const mem = std.mem;
const Ast = std.zig.Ast;
const StringHashMap = std.array_hash_map.String;

const Context = @import("Context.zig");
const Handlers = @import("Expression/Handlers.zig");
const Resolver = @import("Resolver.zig");
const Scanner = @import("Scanner.zig");
const Walker = @import("Scanner/Walker.zig");
const Types = @import("Types.zig");

pub fn scanExpression(
    ctx: Context.AnalysisContext,
    tree: *const Ast,
    node: Ast.Node.Index,
    file_path: []const u8,
    prefix_parts: []const Types.StringId,
    scope: Types.SymbolScope,
) anyerror!void {
    if (prefix_parts.len > 128 or @intFromEnum(node) >= tree.nodes.len or node == .root) return;

    var container_buffer: [2]Ast.Node.Index = undefined;

    if (try Resolver.resolveToImport(
        ctx.allocator,
        ctx.io,
        ctx.ast_cache,
        ctx.path_cache,
        tree.*,
        node,
        file_path,
        scope,
        0,
        ctx.pool,
        ctx.root_path_id,
    )) |res| {
        if (ctx.is_dry_run and ctx.pub_only) {
            const current_file_id = ctx.path_cache.get(file_path) orelse ctx.root_path_id;
            if (res.path_id == ctx.root_path_id and current_file_id != ctx.root_path_id) {
                res.deinit(ctx.allocator);
                return;
            }
        }

        const imp_path = ctx.pool.get(res.path_id);
        if (res.member_id) |mid| {
            try Scanner.processFileWithMember(ctx, imp_path, ctx.pool.get(mid), prefix_parts);
        } else {
            try Scanner.processFile(ctx, imp_path, prefix_parts);
        }
        return;
    }

    const tag = tree.nodeTag(node);

    if (tree.fullContainerDecl(&container_buffer, node)) |cont| {
        const file_id = try ctx.pool.getOrPut(ctx.allocator, file_path);
        const node_id = Types.NodeIdentity{ .path_id = file_id, .node = node };
        for (ctx.stack.items) |s| if (s.path_id == node_id.path_id and s.node == node_id.node) return;
        try ctx.stack.append(ctx.allocator, node_id);
        defer _ = ctx.stack.pop();
        try Walker.walkNodes(ctx, tree, cont.ast.members, file_path, prefix_parts, scope);
    } else if (tag == .block or tag == .block_semicolon or tag == .block_two or tag == .block_two_semicolon) {
        try Handlers.handleBlock(ctx, tree, node, file_path, prefix_parts, scope);
    } else if (tag == .@"if" or tag == .if_simple) {
        try Handlers.handleIf(ctx, tree, node, file_path, prefix_parts, scope);
    } else if (tag == .@"switch" or tag == .switch_comma) {
        try Handlers.handleSwitch(ctx, tree, node, file_path, prefix_parts, scope);
    } else if (tag == .@"return") {
        try Handlers.handleReturn(ctx, tree, node, file_path, prefix_parts, scope);
    } else if (tag == .call or tag == .call_comma) {
        if (try Resolver.resolveToImport(
            ctx.allocator,
            ctx.io,
            ctx.ast_cache,
            ctx.path_cache,
            tree.*,
            node,
            file_path,
            scope,
            0,
            ctx.pool,
            ctx.root_path_id,
        )) |res| {
            if (ctx.is_dry_run and ctx.pub_only) {
                const current_file_id = ctx.path_cache.get(file_path) orelse ctx.root_path_id;
                if (res.path_id == ctx.root_path_id and current_file_id != ctx.root_path_id) {
                    res.deinit(ctx.allocator);
                    return;
                }
            }

            const imp_path = ctx.pool.get(res.path_id);
            if (res.member_id) |mid| {
                try Scanner.processFileWithMember(ctx, imp_path, ctx.pool.get(mid), prefix_parts);
            } else {
                try Scanner.processFile(ctx, imp_path, prefix_parts);
            }
        }
    }
}
