const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const Ast = std.zig.Ast;
const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;

const CLI = @import("../../env/CLI.zig");
const AstUtils = @import("../AstUtils.zig");
const Context = @import("../Context.zig");
const Expression = @import("../Expression.zig");
const Resolver = @import("../Resolver.zig");
const Types = @import("../Types.zig");
const Utils = @import("../Utils.zig");

pub fn processField(
    ctx: Context.AnalysisContext,
    tree: *const Ast,
    node: Ast.Node.Index,
    file_path: []const u8,
    prefix_parts: []const Types.StringId,
) anyerror!void {
    if (tree.fullContainerField(node)) |cf| {
        const name = tree.tokenSlice(cf.ast.main_token);
        if (mem.eql(u8, name, ctx.pool.get(ctx.root_name_id))) return;

        const name_id = try ctx.pool.getOrPut(ctx.allocator, name);

        var fqn_len: usize = 0;
        for (prefix_parts) |id| {
            const s = ctx.pool.get(id);
            if (fqn_len + s.len + 1 > ctx.workspace_buf.len) break;
            @memcpy(ctx.workspace_buf[fqn_len..][0..s.len], s);
            fqn_len += s.len;
            ctx.workspace_buf[fqn_len] = '.';
            fqn_len += 1;
        }
        if (fqn_len + name.len <= ctx.workspace_buf.len) {
            @memcpy(ctx.workspace_buf[fqn_len..][0..name.len], name);
            fqn_len += name.len;
        }
        const full_fqn = ctx.workspace_buf[0..fqn_len];
        const full_fqn_id = try ctx.pool.getOrPut(ctx.allocator, full_fqn);

        const current_dep_raw = try Utils.getDeprecatedComment(ctx.allocator, tree, node);
        defer if (current_dep_raw) |d| ctx.allocator.free(d);

        const current_dep_id = if (current_dep_raw) |d| try ctx.pool.getOrPut(ctx.allocator, d) else null;
        const raw_src = tree.getNodeSource(node);
        const rhs_id = try ctx.pool.getOrPut(ctx.allocator, raw_src);

        const is_searching = ctx.search_terms.len > 0;
        const search_hit = if (is_searching) Utils.containsAllKeywordsDirect(
            full_fqn,
            current_dep_raw,
            raw_src,
            ctx.search_terms,
        ) else false;

        const is_exact_match = Utils.isExactMatchId(prefix_parts, name_id, ctx.pool, ctx.filters);
        const filter_match = Utils.findMatchId(prefix_parts, name_id, ctx.pool, ctx.filters, ctx.depth_limit);
        const should_print = if (is_searching) search_hit else (filter_match != null);

        if (should_print) {
            const is_unlimited = if (ctx.depth_limit) |dl| dl == CLI.UNLIMITED_DEPTH else true;
            const suppress_private = is_unlimited and !ctx.show_private;
            const is_allowed_to_show = ctx.show_private or ctx.is_explicit_target or is_exact_match or !suppress_private;

            var proceed_to_output = true;
            if (ctx.flagged_deprecated) proceed_to_output = Utils.containsDeprecated(current_dep_raw);

            if (proceed_to_output) {
                if (ctx.is_dry_run or !is_allowed_to_show) {
                    ctx.priv_hidden_count.* += 1;
                } else {
                    ctx.metrics.recordConstant();
                    const is_node_dep = Utils.containsDeprecated(current_dep_raw);
                    const merged_dep_id = try Utils.mergeDepId(ctx.allocator, ctx.pool, ctx.inherited_dep_id, current_dep_id, ctx.workspace_buf);

                    const new_fqn = try ctx.registry_allocator.alloc(Types.StringId, prefix_parts.len + 1);
                    @memcpy(new_fqn[0..prefix_parts.len], prefix_parts);
                    new_fqn[prefix_parts.len] = name_id;

                    const file_id = try ctx.pool.getOrPut(ctx.allocator, file_path);

                    try ctx.registry.append(ctx.allocator, .{
                        .fqn_parts = new_fqn,
                        .full_fqn_id = full_fqn_id,
                        .cond_id = ctx.current_cond_id,
                        .dep_id = merged_dep_id,
                        .rhs_id = rhs_id,
                        .trace_chain = &.{},
                        .coord = .{
                            .file_id = file_id,
                            .node = node,
                        },
                        .is_explicit_dep = is_node_dep,
                        .is_private = true,
                        .is_target_hit = ctx.is_explicit_target or is_exact_match,
                        .child_count = 0,
                        .priv_child_count = 0,
                    });
                }
            }
        }
    }
}

pub fn processVar(
    ctx: Context.AnalysisContext,
    tree: *const Ast,
    node: Ast.Node.Index,
    var_decl: Ast.full.VarDecl,
    file_path: []const u8,
    prefix_parts: []const Types.StringId,
    scope: Types.SymbolScope,
) anyerror!void {
    const is_private = var_decl.visib_token == null;

    if (ctx.is_dry_run) {
        if (is_private) {
            ctx.priv_hidden_count.* += 1;
            if (ctx.pub_only) return;
        } else {
            ctx.pub_hidden_count.* += 1;
        }

        if (var_decl.ast.init_node.unwrap()) |init| {
            try Expression.scanExpression(ctx, tree, init, file_path, prefix_parts, scope);
        }
        return;
    }

    if (ctx.pub_only and is_private) return;

    const name = tree.tokenSlice(var_decl.ast.mut_token + 1);
    if (mem.eql(u8, name, ctx.pool.get(ctx.root_name_id))) return;

    const init_node = var_decl.ast.init_node.unwrap() orelse return;
    const name_id = try ctx.pool.getOrPut(ctx.allocator, name);

    var fqn_len: usize = 0;
    for (prefix_parts) |id| {
        const s = ctx.pool.get(id);
        if (fqn_len + s.len + 1 > ctx.workspace_buf.len) break;
        @memcpy(ctx.workspace_buf[fqn_len..][0..s.len], s);
        fqn_len += s.len;
        ctx.workspace_buf[fqn_len] = '.';
        fqn_len += 1;
    }
    if (fqn_len + name.len <= ctx.workspace_buf.len) {
        @memcpy(ctx.workspace_buf[fqn_len..][0..name.len], name);
        fqn_len += name.len;
    }
    const full_fqn = ctx.workspace_buf[0..fqn_len];
    const full_fqn_id = try ctx.pool.getOrPut(ctx.allocator, full_fqn);

    const current_dep_raw = try Utils.getDeprecatedComment(ctx.allocator, tree, node);
    defer if (current_dep_raw) |d| ctx.allocator.free(d);

    const current_dep_id = if (current_dep_raw) |d| try ctx.pool.getOrPut(ctx.allocator, d) else null;
    const raw_src = tree.getNodeSource(init_node);
    const rhs_id = try ctx.pool.getOrPut(ctx.allocator, raw_src);

    const is_searching = ctx.search_terms.len > 0;
    const search_hit = if (is_searching) Utils.containsAllKeywordsDirect(
        full_fqn,
        current_dep_raw,
        raw_src,
        ctx.search_terms,
    ) else false;

    const match_hit = Utils.findMatchId(prefix_parts, name_id, ctx.pool, ctx.filters, ctx.depth_limit);
    const scope_parent_hit = Utils.isScopeParentId(prefix_parts, name_id, ctx.pool, ctx.filters);

    if (is_searching or match_hit != null or scope_parent_hit) {
        var trace = try Resolver.resolveTrace(
            ctx.allocator,
            ctx.io,
            ctx.ast_cache,
            ctx.path_cache,
            tree,
            node,
            file_path,
            scope.map,
            ctx.inherited_dep_id,
            0,
            ctx.root_path_id,
            ctx.pool,
            ctx.workspace_buf,
        );
        defer trace.deinit(ctx.allocator);

        const trace_merged_dep_id = try extractTraceDep(ctx.allocator, ctx.pool, trace, ctx.workspace_buf);
        const intermediate_dep_id = try Utils.mergeDepId(ctx.allocator, ctx.pool, ctx.inherited_dep_id, current_dep_id, ctx.workspace_buf);
        const final_merged_dep_id = try Utils.mergeDepId(ctx.allocator, ctx.pool, intermediate_dep_id, trace_merged_dep_id, ctx.workspace_buf);

        const new_fqn = try ctx.registry_allocator.alloc(Types.StringId, prefix_parts.len + 1);
        @memcpy(new_fqn[0..prefix_parts.len], prefix_parts);
        new_fqn[prefix_parts.len] = name_id;

        const is_this_exact_target = Utils.isExactMatchId(prefix_parts, name_id, ctx.pool, ctx.filters);

        var can_rec = is_searching;
        if (!can_rec) {
            if (scope_parent_hit) {
                can_rec = true;
            } else if (match_hit) |filter| {
                can_rec = Utils.canRecurseId(new_fqn, ctx.pool, filter, ctx.depth_limit);
            }
        }

        const is_unlimited = if (ctx.depth_limit) |dl| dl == CLI.UNLIMITED_DEPTH else true;
        const suppress_private = is_unlimited and !ctx.show_private;
        const can_output_entry = !is_private or !suppress_private or ctx.is_explicit_target or is_this_exact_target;

        const should_print = if (is_searching) search_hit else (match_hit != null);
        if (should_print) {
            var proceed_to_output = true;
            if (ctx.flagged_deprecated) proceed_to_output = Utils.containsDeprecated(current_dep_raw);

            if (proceed_to_output) {
                if (!can_output_entry) {
                    if (is_private) ctx.priv_hidden_count.* += 1 else ctx.pub_hidden_count.* += 1;
                    var sub_pub: usize = 0;
                    var sub_priv: usize = 0;
                    if (can_rec) {
                        const next_ctx = ctx.withDep(final_merged_dep_id).withTarget(ctx.is_explicit_target or is_this_exact_target).withCounters(&sub_pub, &sub_priv).asDryRun();
                        try Expression.scanExpression(next_ctx, tree, init_node, file_path, new_fqn, scope);
                    }
                    ctx.pub_hidden_count.* += sub_pub;
                    ctx.priv_hidden_count.* += sub_priv;
                } else {
                    var buf: [2]Ast.Node.Index = undefined;
                    if (tree.fullContainerDecl(&buf, init_node)) |cd| {
                        if (cd.ast.enum_token != null) ctx.metrics.recordEnum() else ctx.metrics.recordStruct();
                    } else ctx.metrics.recordConstant();

                    const chain = try ctx.registry_allocator.dupe(Types.TraceStep, trace.steps.items);
                    const file_id = try ctx.pool.getOrPut(ctx.allocator, file_path);

                    try ctx.registry.append(ctx.allocator, .{
                        .fqn_parts = new_fqn,
                        .full_fqn_id = full_fqn_id,
                        .cond_id = ctx.current_cond_id,
                        .dep_id = final_merged_dep_id,
                        .rhs_id = rhs_id,
                        .trace_chain = chain,
                        .coord = .{
                            .file_id = file_id,
                            .node = node,
                        },
                        .is_explicit_dep = Utils.containsDeprecated(current_dep_raw),
                        .is_private = is_private,
                        .is_target_hit = ctx.is_explicit_target or is_this_exact_target,
                        .child_count = 0,
                        .priv_child_count = 0,
                    });

                    const entry_idx = ctx.registry.items.len - 1;
                    var sub_pub: usize = 0;
                    var sub_priv: usize = 0;
                    var next_ctx = ctx.withDep(final_merged_dep_id).withTarget(ctx.is_explicit_target or is_this_exact_target).withCounters(&sub_pub, &sub_priv);

                    if (!can_rec) next_ctx = next_ctx.asDryRun();
                    try Expression.scanExpression(next_ctx, tree, init_node, file_path, new_fqn, scope);

                    ctx.registry.items[entry_idx].child_count = sub_pub;
                    ctx.registry.items[entry_idx].priv_child_count = sub_priv;

                    ctx.pub_hidden_count.* += sub_pub;
                    ctx.priv_hidden_count.* += sub_priv;
                }
            }
        } else if (can_rec) {
            const next_ctx = ctx.withDep(final_merged_dep_id).withTarget(ctx.is_explicit_target or is_this_exact_target);
            try Expression.scanExpression(next_ctx, tree, init_node, file_path, new_fqn, scope);
        }
    }
}

pub fn processFn(
    ctx: Context.AnalysisContext,
    tree: *const Ast,
    node: Ast.Node.Index,
    fn_proto: Ast.full.FnProto,
    file_path: []const u8,
    prefix_parts: []const Types.StringId,
    scope: Types.SymbolScope,
) anyerror!void {
    const is_private = fn_proto.visib_token == null;

    if (ctx.is_dry_run) {
        if (is_private) {
            ctx.priv_hidden_count.* += 1;
            if (ctx.pub_only) return;
        } else {
            ctx.pub_hidden_count.* += 1;
        }

        if (AstUtils.isForwardingFactory(tree.*, node)) |target| {
            try Expression.scanExpression(ctx, tree, target, file_path, prefix_parts, scope);
        } else if (AstUtils.isTypeFactory(tree.*, node)) |cont| {
            try Expression.scanExpression(ctx, tree, cont, file_path, prefix_parts, scope);
        }
        return;
    }

    if (ctx.pub_only and is_private) return;

    const name = if (fn_proto.name_token) |t| tree.tokenSlice(t) else "anonymous";
    if (mem.eql(u8, name, ctx.pool.get(ctx.root_name_id))) return;

    const name_id = try ctx.pool.getOrPut(ctx.allocator, name);

    var fqn_len: usize = 0;
    for (prefix_parts) |id| {
        const s = ctx.pool.get(id);
        if (fqn_len + s.len + 1 > ctx.workspace_buf.len) break;
        @memcpy(ctx.workspace_buf[fqn_len..][0..s.len], s);
        fqn_len += s.len;
        ctx.workspace_buf[fqn_len] = '.';
        fqn_len += 1;
    }
    if (fqn_len + name.len <= ctx.workspace_buf.len) {
        @memcpy(ctx.workspace_buf[fqn_len..][0..name.len], name);
        fqn_len += name.len;
    }
    const full_fqn = ctx.workspace_buf[0..fqn_len];
    const full_fqn_id = try ctx.pool.getOrPut(ctx.allocator, full_fqn);

    const current_dep_raw = try Utils.getDeprecatedComment(ctx.allocator, tree, node);
    defer if (current_dep_raw) |d| ctx.allocator.free(d);

    const current_dep_id = if (current_dep_raw) |d| try ctx.pool.getOrPut(ctx.allocator, d) else null;
    const raw_src = tree.getNodeSource(node);
    const rhs_id = try ctx.pool.getOrPut(ctx.allocator, raw_src);

    const is_searching = ctx.search_terms.len > 0;
    const search_hit = if (is_searching) Utils.containsAllKeywordsDirect(
        full_fqn,
        current_dep_raw,
        raw_src,
        ctx.search_terms,
    ) else false;

    const match_hit = Utils.findMatchId(prefix_parts, name_id, ctx.pool, ctx.filters, ctx.depth_limit);
    const scope_parent_hit = Utils.isScopeParentId(prefix_parts, name_id, ctx.pool, ctx.filters);

    if (is_searching or match_hit != null or scope_parent_hit) {
        var trace = try Resolver.resolveTrace(
            ctx.allocator,
            ctx.io,
            ctx.ast_cache,
            ctx.path_cache,
            tree,
            node,
            file_path,
            scope.map,
            ctx.inherited_dep_id,
            0,
            ctx.root_path_id,
            ctx.pool,
            ctx.workspace_buf,
        );
        defer trace.deinit(ctx.allocator);

        const trace_merged_dep_id = try extractTraceDep(ctx.allocator, ctx.pool, trace, ctx.workspace_buf);
        const intermediate_dep_id = try Utils.mergeDepId(ctx.allocator, ctx.pool, ctx.inherited_dep_id, current_dep_id, ctx.workspace_buf);
        const final_merged_dep_id = try Utils.mergeDepId(ctx.allocator, ctx.pool, intermediate_dep_id, trace_merged_dep_id, ctx.workspace_buf);

        const new_fqn = try ctx.registry_allocator.alloc(Types.StringId, prefix_parts.len + 1);
        @memcpy(new_fqn[0..prefix_parts.len], prefix_parts);
        new_fqn[prefix_parts.len] = name_id;

        const is_this_exact_target = Utils.isExactMatchId(prefix_parts, name_id, ctx.pool, ctx.filters);

        var can_rec = is_searching;
        if (!can_rec) {
            if (scope_parent_hit) {
                can_rec = true;
            } else if (match_hit) |filter| {
                can_rec = Utils.canRecurseId(new_fqn, ctx.pool, filter, ctx.depth_limit);
            }
        }

        const is_unlimited = if (ctx.depth_limit) |dl| dl == CLI.UNLIMITED_DEPTH else true;
        const suppress_private = is_unlimited and !ctx.show_private;
        const can_output_entry = !is_private or !suppress_private or ctx.is_explicit_target or is_this_exact_target;

        const should_print = if (is_searching) search_hit else (match_hit != null);
        if (should_print) {
            var proceed_to_output = true;
            if (ctx.flagged_deprecated) proceed_to_output = Utils.containsDeprecated(current_dep_raw);

            if (proceed_to_output) {
                if (!can_output_entry) {
                    if (is_private) ctx.priv_hidden_count.* += 1 else ctx.pub_hidden_count.* += 1;
                    var sub_pub: usize = 0;
                    var sub_priv: usize = 0;
                    if (can_rec) {
                        const next_ctx = ctx.withDep(final_merged_dep_id).withTarget(ctx.is_explicit_target or is_this_exact_target).withCounters(&sub_pub, &sub_priv).asDryRun();
                        if (AstUtils.isForwardingFactory(tree.*, node)) |target_expr| {
                            try Expression.scanExpression(next_ctx, tree, target_expr, file_path, new_fqn, scope);
                        } else if (AstUtils.isTypeFactory(tree.*, node)) |cont_node| {
                            try Expression.scanExpression(next_ctx, tree, cont_node, file_path, new_fqn, scope);
                        }
                    }
                    ctx.pub_hidden_count.* += sub_pub;
                    ctx.priv_hidden_count.* += sub_priv;
                } else {
                    ctx.metrics.recordFn();
                    const chain = try ctx.registry_allocator.dupe(Types.TraceStep, trace.steps.items);
                    const file_id = try ctx.pool.getOrPut(ctx.allocator, file_path);

                    try ctx.registry.append(ctx.allocator, .{
                        .fqn_parts = new_fqn,
                        .full_fqn_id = full_fqn_id,
                        .cond_id = ctx.current_cond_id,
                        .dep_id = final_merged_dep_id,
                        .rhs_id = rhs_id,
                        .trace_chain = chain,
                        .coord = .{
                            .file_id = file_id,
                            .node = node,
                        },
                        .is_explicit_dep = Utils.containsDeprecated(current_dep_raw),
                        .is_private = is_private,
                        .is_target_hit = ctx.is_explicit_target or is_this_exact_target,
                        .child_count = 0,
                        .priv_child_count = 0,
                    });

                    const entry_idx = ctx.registry.items.len - 1;
                    var sub_pub: usize = 0;
                    var sub_priv: usize = 0;
                    var next_ctx = ctx.withDep(final_merged_dep_id).withTarget(ctx.is_explicit_target or is_this_exact_target).withCounters(&sub_pub, &sub_priv);

                    if (!can_rec) next_ctx = next_ctx.asDryRun();
                    if (AstUtils.isForwardingFactory(tree.*, node)) |target_expr| {
                        try Expression.scanExpression(next_ctx, tree, target_expr, file_path, new_fqn, scope);
                    } else if (AstUtils.isTypeFactory(tree.*, node)) |cont_node| {
                        try Expression.scanExpression(next_ctx, tree, cont_node, file_path, new_fqn, scope);
                    }

                    ctx.registry.items[entry_idx].child_count = sub_pub;
                    ctx.registry.items[entry_idx].priv_child_count = sub_priv;

                    ctx.pub_hidden_count.* += sub_pub;
                    ctx.priv_hidden_count.* += sub_priv;
                }
            }
        } else if (can_rec) {
            const next_ctx = ctx.withDep(final_merged_dep_id).withTarget(ctx.is_explicit_target or is_this_exact_target);
            if (AstUtils.isForwardingFactory(tree.*, node)) |target_expr| {
                try Expression.scanExpression(next_ctx, tree, target_expr, file_path, new_fqn, scope);
            } else if (AstUtils.isTypeFactory(tree.*, node)) |cont_node| {
                try Expression.scanExpression(next_ctx, tree, cont_node, file_path, new_fqn, scope);
            }
        }
    }
}

pub fn processUnhandled(
    ctx: Context.AnalysisContext,
    tree: *const Ast,
    node: Ast.Node.Index,
    file_path: []const u8,
) anyerror!void {
    const tag = tree.nodeTag(node);
    if (tag == .test_decl) return;

    var is_pub = false;
    const first_tok = tree.firstToken(node);
    if (first_tok < tree.tokens.len) {
        if (mem.eql(u8, tree.tokenSlice(first_tok), "pub")) {
            is_pub = true;
        } else if (first_tok > 0 and mem.eql(u8, tree.tokenSlice(first_tok - 1), "pub")) {
            is_pub = true;
        }
    }

    if (!ctx.pub_only or is_pub) {
        ctx.metrics.recordUnhandled();
        const tag_id = try ctx.pool.getOrPut(ctx.allocator, @tagName(tag));
        const loc_assembled = try fmt.bufPrint(ctx.workspace_buf, "{s}:{d}", .{ file_path, node });
        const loc_id = try ctx.pool.getOrPut(ctx.allocator, loc_assembled);

        try ctx.unhandled_list.append(ctx.allocator, .{
            .tag_id = tag_id,
            .loc_id = loc_id,
        });
    }
}

fn extractTraceDep(allocator: Allocator, pool: *Types.StringPool, trace: Types.TraceResult, workspace: []u8) !?Types.StringId {
    var current_len: usize = 0;
    var count: usize = 0;

    for (trace.steps.items) |step| {
        if (step.dep_id) |d_id| {
            const dep_str = pool.get(d_id);
            var d_it = mem.splitSequence(u8, dep_str, " *** ");

            while (d_it.next()) |segment| {
                const trimmed = mem.trim(u8, segment, " ");
                if (trimmed.len == 0) continue;

                if (mem.find(u8, workspace[0..current_len], trimmed) != null) continue;

                if (current_len > 0) {
                    if (current_len + 5 > workspace.len) break;
                    @memcpy(workspace[current_len..][0..5], " *** ");
                    current_len += 5;
                }

                if (current_len + trimmed.len > workspace.len) break;
                @memcpy(workspace[current_len..][0..trimmed.len], trimmed);
                current_len += trimmed.len;
                count += 1;
            }
        }
    }

    if (count == 0) return null;
    return try pool.getOrPut(allocator, workspace[0..current_len]);
}
