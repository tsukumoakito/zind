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

const AstUtils = @import("../analysis/AstUtils.zig");
const Formatter = @import("../analysis/Formatter.zig");
const Types = @import("../analysis/Types.zig");
const Utils = @import("../analysis/Utils.zig");
const PathFinder = @import("../env/PathFinder.zig");
const Context = @import("Context.zig");

pub fn resolveTrace(
    allocator: Allocator,
    io: Io,
    ast_cache: *Context.AstCacheManager,
    path_cache: *StringHashMap(Types.StringId),
    tree: *const Ast,
    node: Ast.Node.Index,
    current_file: []const u8,
    symbols: *const StringHashMap(Ast.Node.Index),
    inherited_dep_id: ?Types.StringId,
    depth: u8,
    root_path_id: ?Types.StringId,
    pool: *Types.StringPool,
    workspace: []u8,
) anyerror!Types.TraceResult {
    const current_file_id = try pool.getOrPut(allocator, current_file);

    var res = Types.TraceResult{
        .steps = ArrayList(Types.TraceStep).empty,
        .final_node = node,
        .final_path_id = current_file_id,
        .final_tree = tree,
        .final_symbols = .{ .map = symbols, .parent = null },
    };

    if (depth > 10) return res;

    var display_node = node;
    if (node != .root) {
        const tag = tree.nodeTag(node);
        if (tag != .fn_decl and !tree.isTokenPrecededByTags(tree.firstToken(node), &.{ .keyword_const, .keyword_var })) {
            var it = symbols.iterator();
            while (it.next()) |entry| {
                const decl_node = entry.value_ptr.*;
                if (tree.fullVarDecl(decl_node)) |v| {
                    if (v.ast.init_node.unwrap() == node) {
                        display_node = decl_node;
                        break;
                    }
                }
            }
        }
    }

    const formatted_str = if (display_node == .root) blk: {
        if (root_path_id) |rpid| {
            const root_path = pool.get(rpid);
            const base = Dir.path.dirname(root_path) orelse "";
            if (mem.startsWith(u8, current_file, base)) {
                var rel = current_file[base.len..];
                if (rel.len > 0 and (rel[0] == '/' or rel[0] == '\\')) rel = rel[1..];
                break :blk try fmt.bufPrint(workspace, "{s} (Full File)", .{rel});
            }
        }
        break :blk try fmt.bufPrint(workspace, "{s} (Full File)", .{Dir.path.basename(current_file)});
    } else blk: {
        const raw_src = tree.getNodeSource(display_node);
        const cleaned = try Formatter.formatApiLine(allocator, raw_src);
        defer allocator.free(cleaned);
        break :blk try fmt.bufPrint(workspace, "{s}", .{cleaned});
    };

    const formatted_id = try pool.getOrPut(allocator, formatted_str);

    const current_dep_raw = try Utils.getDeprecatedComment(allocator, tree, display_node);
    defer if (current_dep_raw) |cd| allocator.free(cd);

    const current_dep_id = if (current_dep_raw) |cd| try pool.getOrPut(allocator, cd) else null;
    const merged_dep_id = try Utils.mergeDepId(allocator, pool, inherited_dep_id, current_dep_id, workspace);

    try res.steps.append(allocator, .{
        .formatted_id = formatted_id,
        .dep_id = merged_dep_id,
        .node = display_node,
        .path_id = current_file_id,
    });

    if (tree.fullVarDecl(node)) |v| {
        if (v.ast.init_node.unwrap()) |init| {
            if (try resolveToImport(
                allocator,
                io,
                ast_cache,
                path_cache,
                tree.*,
                init,
                current_file,
                res.final_symbols,
                0,
                pool,
                root_path_id,
            )) |imp| {
                defer imp.deinit(allocator);
                if (imp.member_id == null) return res;

                const imp_path = pool.get(imp.path_id);
                const abs_id = if (path_cache.get(imp_path)) |id| id else blk: {
                    const resolved = try PathFinder.resolveAbsolutePath(allocator, io, imp_path);
                    defer allocator.free(resolved);
                    const id = try pool.getOrPut(allocator, resolved);
                    try path_cache.put(allocator, try allocator.dupe(u8, imp_path), id);
                    break :blk id;
                };
                const abs = pool.get(abs_id);

                const next_tree = if (ast_cache.get(abs_id)) |t| t else blk: {
                    const source: [:0]u8 = Dir.readFileAllocOptions(
                        Dir.cwd(),
                        io,
                        abs,
                        allocator,
                        .unlimited,
                        Alignment.of(u8),
                        0,
                    ) catch |err| {
                        std.log.err("Failed to read trace target file '{s}': {s}", .{ abs, @errorName(err) });
                        return res;
                    };
                    const t = try allocator.create(Ast);
                    t.* = try Ast.parse(allocator, source, .zig);
                    try ast_cache.put(allocator, abs_id, t, &.{});
                    break :blk t;
                };

                const imp_member = pool.get(imp.member_id.?);
                if (AstUtils.findMemberInTree(next_tree.*, imp_member)) |next_node| {
                    var n_sym = StringHashMap(Ast.Node.Index).empty;
                    defer n_sym.deinit(allocator);

                    for (next_tree.rootDecls()) |rd| {
                        if (next_tree.fullVarDecl(rd)) |rv| {
                            try n_sym.put(allocator, next_tree.tokenSlice(rv.ast.mut_token + 1), rd);
                        } else if (next_tree.nodeTag(rd) == .fn_decl) {
                            var b: [1]Ast.Node.Index = undefined;
                            if (next_tree.fullFnProto(&b, next_tree.nodeData(rd).node_and_node.@"0")) |p| {
                                if (p.name_token) |nt| try n_sym.put(allocator, next_tree.tokenSlice(nt), rd);
                            }
                        }
                    }

                    var next_res = try resolveTrace(
                        allocator,
                        io,
                        ast_cache,
                        path_cache,
                        next_tree,
                        next_node,
                        abs,
                        &n_sym,
                        merged_dep_id,
                        depth + 1,
                        root_path_id,
                        pool,
                        workspace,
                    );

                    for (next_res.steps.items) |s| try res.steps.append(allocator, s);
                    next_res.steps.deinit(allocator);

                    res.final_path_id = next_res.final_path_id;
                    res.final_node = next_res.final_node;
                    res.final_tree = next_res.final_tree;
                    res.final_symbols = next_res.final_symbols;
                }
            } else if (tree.nodeTag(init) == .identifier) {
                const name = tree.tokenSlice(tree.nodeMainToken(init));
                if (res.final_symbols.get(name)) |next_node| {
                    var next_res = try resolveTrace(
                        allocator,
                        io,
                        ast_cache,
                        path_cache,
                        tree,
                        next_node,
                        current_file,
                        symbols,
                        merged_dep_id,
                        depth + 1,
                        root_path_id,
                        pool,
                        workspace,
                    );
                    for (next_res.steps.items) |s| try res.steps.append(allocator, s);
                    next_res.steps.deinit(allocator);

                    res.final_path_id = next_res.final_path_id;
                    res.final_node = next_res.final_node;
                }
            }
        }
    } else if (tree.nodeTag(node) == .fn_decl) {
        const factory_target = AstUtils.isForwardingFactory(tree.*, node) orelse AstUtils.isTypeFactory(tree.*, node);

        if (factory_target) |target| {
            if (try resolveToImport(
                allocator,
                io,
                ast_cache,
                path_cache,
                tree.*,
                target,
                current_file,
                res.final_symbols,
                0,
                pool,
                root_path_id,
            )) |imp| {
                defer imp.deinit(allocator);
                if (imp.member_id == null) return res;

                const imp_path = pool.get(imp.path_id);
                const abs_id = if (path_cache.get(imp_path)) |id| id else blk: {
                    const resolved = try PathFinder.resolveAbsolutePath(allocator, io, imp_path);
                    defer allocator.free(resolved);
                    const id = try pool.getOrPut(allocator, resolved);
                    try path_cache.put(allocator, try allocator.dupe(u8, imp_path), id);
                    break :blk id;
                };
                const abs = pool.get(abs_id);

                const next_tree = if (ast_cache.get(abs_id)) |t| t else return res;
                const imp_member = pool.get(imp.member_id.?);
                if (AstUtils.findMemberInTree(next_tree.*, imp_member)) |next_node| {
                    var n_sym = StringHashMap(Ast.Node.Index).empty;
                    defer n_sym.deinit(allocator);

                    for (next_tree.rootDecls()) |rd| {
                        if (next_tree.fullVarDecl(rd)) |rv| {
                            try n_sym.put(allocator, next_tree.tokenSlice(rv.ast.mut_token + 1), rd);
                        } else if (next_tree.nodeTag(rd) == .fn_decl) {
                            var b: [1]Ast.Node.Index = undefined;
                            if (next_tree.fullFnProto(&b, next_tree.nodeData(rd).node_and_node.@"0")) |p| {
                                if (p.name_token) |nt| try n_sym.put(allocator, next_tree.tokenSlice(nt), rd);
                            }
                        }
                    }

                    var next_res = try resolveTrace(
                        allocator,
                        io,
                        ast_cache,
                        path_cache,
                        next_tree,
                        next_node,
                        abs,
                        &n_sym,
                        merged_dep_id,
                        depth + 1,
                        root_path_id,
                        pool,
                        workspace,
                    );
                    for (next_res.steps.items) |s| try res.steps.append(allocator, s);
                    next_res.steps.deinit(allocator);

                    res.final_path_id = next_res.final_path_id;
                    res.final_node = next_res.final_node;
                    res.final_tree = next_res.final_tree;
                    res.final_symbols = next_res.final_symbols;
                }
            }
        }
    }

    return res;
}

pub fn resolveToImport(
    allocator: Allocator,
    io: Io,
    ast_cache: *Context.AstCacheManager,
    path_cache: *StringHashMap(Types.StringId),
    tree: Ast,
    node: Ast.Node.Index,
    current_file: []const u8,
    scope: Types.SymbolScope,
    depth: u8,
    pool: *Types.StringPool,
    root_path_id: ?Types.StringId,
) anyerror!?Types.ImportRes {
    if (depth > 20 or @intFromEnum(node) >= tree.nodes.len or node == .root) return null;

    const tag = tree.nodeTag(node);

    if (tree.fullVarDecl(node)) |v| {
        if (v.ast.init_node.unwrap()) |init| {
            return try resolveToImport(
                allocator,
                io,
                ast_cache,
                path_cache,
                tree,
                init,
                current_file,
                scope,
                depth + 1,
                pool,
                root_path_id,
            );
        }
    }

    if (tag == .call or tag == .call_comma) {
        var buf: [1]Ast.Node.Index = undefined;
        if (tree.fullCall(&buf, node)) |c| {
            return try resolveToImport(
                allocator,
                io,
                ast_cache,
                path_cache,
                tree,
                c.ast.fn_expr,
                current_file,
                scope,
                depth + 1,
                pool,
                root_path_id,
            );
        }
    }

    if (tag == .field_access) {
        const data = tree.nodeData(node);
        const rhs = tree.tokenSlice(data.node_and_token.@"1");

        if (try resolveToImport(
            allocator,
            io,
            ast_cache,
            path_cache,
            tree,
            data.node_and_token.@"0",
            current_file,
            scope,
            depth + 1,
            pool,
            root_path_id,
        )) |res| {
            defer res.deinit(allocator);

            const res_path = pool.get(res.path_id);
            const abs_id = if (path_cache.get(res_path)) |id| id else blk: {
                const resolved = try Dir.path.resolve(
                    allocator,
                    &.{ Dir.path.dirname(res_path) orelse ".", Dir.path.basename(res_path) },
                );
                defer allocator.free(resolved);
                const id = try pool.getOrPut(allocator, resolved);
                try path_cache.put(allocator, try allocator.dupe(u8, res_path), id);
                break :blk id;
            };
            const abs = pool.get(abs_id);

            const next = if (ast_cache.get(abs_id)) |t| t else blk: {
                const src: [:0]u8 = Dir.readFileAllocOptions(
                    Dir.cwd(),
                    io,
                    abs,
                    allocator,
                    .unlimited,
                    Alignment.of(u8),
                    0,
                ) catch |err| {
                    std.log.err("Failed to read import target file '{s}': {s}", .{ abs, @errorName(err) });
                    return null;
                };
                const t = try allocator.create(Ast);
                t.* = try Ast.parse(allocator, src, .zig);
                try ast_cache.put(allocator, abs_id, t, &.{});
                break :blk t;
            };

            const lookup = if (res.member_id) |mid| pool.get(mid) else rhs;
            if (AstUtils.findMemberInTree(next.*, lookup)) |tn| {
                const ntag = next.nodeTag(tn);
                if (ntag == .container_field or ntag == .container_field_init or ntag == .container_field_align) {
                    const final_member = if (res.member_id) |mid| try fmt.allocPrint(
                        allocator,
                        "{s}.{s}",
                        .{ pool.get(mid), rhs },
                    ) else rhs;
                    defer if (res.member_id != null) allocator.free(final_member);

                    return .{
                        .path_id = abs_id,
                        .member_id = try pool.getOrPut(allocator, final_member),
                    };
                }
                const init = if (next.fullVarDecl(tn)) |v| v.ast.init_node.unwrap() else if (next.nodeTag(tn) == .fn_decl) tn else null;
                if (init) |in| {
                    if (next.nodeTag(tn) == .fn_decl) {
                        const final_member = if (res.member_id) |mid| try fmt.allocPrint(
                            allocator,
                            "{s}.{s}",
                            .{ pool.get(mid), rhs },
                        ) else rhs;
                        defer if (res.member_id != null) allocator.free(final_member);

                        return .{
                            .path_id = abs_id,
                            .member_id = try pool.getOrPut(allocator, final_member),
                        };
                    }
                    var nsym = StringHashMap(Ast.Node.Index).empty;
                    defer nsym.deinit(allocator);
                    for (next.rootDecls()) |dn| {
                        if (next.fullVarDecl(dn)) |v| {
                            try nsym.put(allocator, next.tokenSlice(v.ast.mut_token + 1), dn);
                        } else if (next.nodeTag(dn) == .fn_decl) {
                            var f_buf: [1]Ast.Node.Index = undefined;
                            if (next.fullFnProto(&f_buf, next.nodeData(dn).node_and_node.@"0")) |p| {
                                if (p.name_token) |nt| try nsym.put(allocator, next.tokenSlice(nt), dn);
                            }
                        }
                    }

                    const next_scope = Types.SymbolScope{ .map = &nsym, .parent = &scope };
                    if (try resolveToImport(
                        allocator,
                        io,
                        ast_cache,
                        path_cache,
                        next.*,
                        in,
                        abs,
                        next_scope,
                        depth + 1,
                        pool,
                        root_path_id,
                    )) |fr| {
                        return fr;
                    }
                }
            }

            const final_member = if (res.member_id) |mid| try fmt.allocPrint(
                allocator,
                "{s}.{s}",
                .{ pool.get(mid), rhs },
            ) else rhs;
            defer if (res.member_id != null) allocator.free(final_member);

            return .{
                .path_id = abs_id,
                .member_id = try pool.getOrPut(allocator, final_member),
            };
        }
    }

    if (AstUtils.getNakedImportPath(tree, node)) |rel| {
        if (mem.eql(u8, rel, "std.zig") and root_path_id != null) {
            return .{
                .path_id = root_path_id.?,
                .member_id = null,
            };
        }

        const resolved_path = try Dir.path.resolve(
            allocator,
            &.{ Dir.path.dirname(current_file) orelse ".", rel },
        );
        defer allocator.free(resolved_path);

        return .{
            .path_id = try pool.getOrPut(allocator, resolved_path),
            .member_id = null,
        };
    }

    if (tag == .identifier) {
        const name = tree.tokenSlice(tree.nodeMainToken(node));
        if (scope.get(name)) |target| {
            if (tree.nodeTag(target) == .fn_decl) return .{
                .path_id = try pool.getOrPut(allocator, current_file),
                .member_id = try pool.getOrPut(allocator, name),
            };
            if (tree.fullVarDecl(target)) |v| if (v.ast.init_node.unwrap()) |init| {
                return try resolveToImport(
                    allocator,
                    io,
                    ast_cache,
                    path_cache,
                    tree,
                    init,
                    current_file,
                    scope,
                    depth + 1,
                    pool,
                    root_path_id,
                );
            };
        }
    }

    return null;
}
