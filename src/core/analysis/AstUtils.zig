const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const fmt = std.fmt;
const Ast = std.zig.Ast;
const Io = std.Io;
const Dir = Io.Dir;
const StringHashMap = std.array_hash_map.String;
const Alignment = mem.Alignment;

pub fn getExtendedNodeRange(
    tree: *const Ast,
    node: Ast.Node.Index,
) struct { start: usize, end: usize } {
    if (node == .root) return .{ .start = 0, .end = tree.source.len };

    var start_tok = tree.firstToken(node);
    while (start_tok > 0) {
        const prev = start_tok - 1;
        const tag = tree.tokenTag(prev);
        if (tag != .doc_comment and tag != .container_doc_comment) break;
        start_tok = prev;
    }

    var start_offset = tree.tokens.items(.start)[start_tok];
    while (start_offset > 0) {
        const c = tree.source[start_offset - 1];
        if (c == '\n' or c == '\r') break;
        if (ascii.isWhitespace(c)) {
            start_offset -= 1;
        } else {
            break;
        }
    }

    const last_tok = tree.lastToken(node);
    const end_offset = tree.tokens.items(.start)[last_tok] + tree.tokenSlice(last_tok).len;

    return .{ .start = start_offset, .end = end_offset };
}

pub fn getLineAndCount(
    source: []const u8,
    start_offset: usize,
    end_offset: usize,
) struct { start_line: usize, end_line: usize, total: usize } {
    var start_line: usize = 1;
    const safe_start = @min(start_offset, source.len);
    for (source[0..safe_start]) |c| {
        if (c == '\n') start_line += 1;
    }

    var total: usize = 0;
    if (end_offset > start_offset) {
        total = 1;
        const safe_end = @min(end_offset, source.len);
        for (source[safe_start..safe_end]) |c| {
            if (c == '\n') total += 1;
        }
    }

    return .{
        .start_line = start_line,
        .end_line = if (total > 0) start_line + total - 1 else start_line,
        .total = total,
    };
}

pub fn resolveContainer(
    tree: Ast,
    node: Ast.Node.Index,
) Ast.Node.Index {
    if (node == .root) return .root;
    if (isTypeFactory(tree, node)) |body| return body;
    if (tree.fullVarDecl(node)) |v| {
        if (v.ast.init_node.unwrap()) |init| {
            const tag = tree.nodeTag(init);
            if (tag == .container_decl or tag == .tagged_union or tag == .struct_init) return init;
        }
    }
    return node;
}

pub fn findMemberInNode(
    tree: *const Ast,
    parent: Ast.Node.Index,
    name: []const u8,
) ?Ast.Node.Index {
    const container_node = resolveContainer(tree.*, parent);
    const tag = tree.nodeTag(container_node);

    if (container_node == .root) {
        for (tree.rootDecls()) |node| if (checkMatch(tree, node, name)) return node;
        return null;
    }

    var buf: [2]Ast.Node.Index = undefined;
    if (tree.fullContainerDecl(&buf, container_node)) |c| {
        for (c.ast.members) |node| if (checkMatch(tree, node, name)) return node;
        return null;
    }

    if (tag == .block or tag == .block_two or tag == .block_semicolon or tag == .block_two_semicolon) {
        var sbuf: [2]Ast.Node.Index = undefined;
        if (tree.blockStatements(&sbuf, container_node)) |stmts| {
            for (stmts) |stmt| {
                if (checkMatch(tree, stmt, name)) return stmt;

                if (tree.nodeTag(stmt) == .@"return") {
                    if (tree.nodeData(stmt).opt_node.unwrap()) |ret_val| {
                        if (findMemberInNode(tree, ret_val, name)) |found| return found;
                    }
                }
            }
        }
    }

    return null;
}

fn checkMatch(
    tree: *const Ast,
    node: Ast.Node.Index,
    name: []const u8,
) bool {
    const tag = tree.nodeTag(node);
    if (tree.fullVarDecl(node)) |v| {
        const decl_name = tree.tokenSlice(v.ast.mut_token + 1);
        if (mem.eql(u8, decl_name, name)) return true;
    } else if (tag == .fn_decl) {
        var buf: [1]Ast.Node.Index = undefined;
        if (tree.fullFnProto(&buf, node)) |p| {
            if (p.name_token) |nt| {
                if (mem.eql(u8, tree.tokenSlice(nt), name)) return true;
            }
        }
    } else if (tag == .container_field or tag == .container_field_init or tag == .container_field_align) {
        if (tree.fullContainerField(node)) |cf| {
            if (mem.eql(u8, tree.tokenSlice(cf.ast.main_token), name)) return true;
        }
    }
    return false;
}

pub fn findMemberInTree(
    tree: Ast,
    name: []const u8,
) ?Ast.Node.Index {
    const dot = mem.findScalar(u8, name, '.');
    const lookup = if (dot) |i| name[0..i] else name;
    for (tree.rootDecls()) |node| {
        if (checkMatch(&tree, node, lookup)) return node;
    }
    return null;
}

pub fn isForwardingFactory(
    tree: Ast,
    node: Ast.Node.Index,
) ?Ast.Node.Index {
    if (tree.nodeTag(node) != .fn_decl) return null;
    const body = tree.nodeData(node).node_and_node.@"1";
    var buf: [2]Ast.Node.Index = undefined;
    const stmts = tree.blockStatements(&buf, body) orelse return null;
    if (stmts.len != 1 or tree.nodeTag(stmts[0]) != .@"return") return null;
    const ret = tree.nodeData(stmts[0]).opt_node.unwrap() orelse return null;
    var cbuf: [1]Ast.Node.Index = undefined;
    return if (tree.fullCall(&cbuf, ret)) |c| c.ast.fn_expr else null;
}

pub fn isTypeFactory(
    tree: Ast,
    node: Ast.Node.Index,
) ?Ast.Node.Index {
    if (tree.nodeTag(node) != .fn_decl) return null;
    var buf: [1]Ast.Node.Index = undefined;
    const proto = tree.fullFnProto(&buf, node) orelse return null;
    const ret_expr = proto.ast.return_type.unwrap() orelse return null;
    if (tree.nodeTag(ret_expr) == .identifier) {
        if (mem.eql(u8, tree.tokenSlice(tree.nodeMainToken(ret_expr)), "type")) {
            return tree.nodeData(node).node_and_node.@"1";
        }
    }
    return null;
}

pub fn getNakedImportPath(
    tree: Ast,
    node: Ast.Node.Index,
) ?[]const u8 {
    const tag = tree.nodeTag(node);
    if (tag != .builtin_call and tag != .builtin_call_two) return null;
    if (!mem.eql(u8, tree.tokenSlice(tree.nodeMainToken(node)), "@import")) return null;
    var buf: [2]Ast.Node.Index = undefined;
    const p = tree.builtinCallParams(&buf, node) orelse return null;
    if (p.len == 0 or tree.nodeTag(p[0]) != .string_literal) return null;
    const r = tree.tokenSlice(tree.nodeMainToken(p[0]));
    if (r.len < 2) return null;
    const inner = r[1 .. r.len - 1];

    if (mem.eql(u8, inner, "std")) return "std.zig";
    if (mem.eql(u8, inner, "builtin") or
        mem.eql(u8, inner, "root") or
        mem.eql(u8, inner, "compiler_rt")) return null;

    return inner;
}

pub fn validateFqnPath(
    allocator: mem.Allocator,
    io: Io,
    ast_cache: *StringHashMap(*Ast),
    root_path: []const u8,
    fqn: []const u8,
) ![]const u8 {
    var it = mem.splitScalar(u8, fqn, '.');
    var current_path = root_path;
    const root_name = Dir.path.stem(root_path);

    const first = it.next() orelse return fqn[0..@min(fqn.len, root_name.len)];
    if (!mem.eql(u8, first, root_name)) return fqn[0..@min(fqn.len, root_name.len)];

    var last_valid_end: usize = root_name.len;
    var current_node: Ast.Node.Index = .root;

    while (it.next()) |segment| {
        const tree = ast_cache.get(current_path) orelse break;
        const found = findMemberInNode(tree, current_node, segment);

        if (found) |node| {
            last_valid_end = (@intFromPtr(segment.ptr) + segment.len) - @intFromPtr(fqn.ptr);

            var init_node: ?Ast.Node.Index = null;
            if (tree.fullVarDecl(node)) |v| {
                init_node = v.ast.init_node.unwrap();
            } else if (tree.nodeTag(node) == .fn_decl) {
                if (isForwardingFactory(tree.*, node)) |target| {
                    init_node = target;
                } else if (isTypeFactory(tree.*, node)) |body| {
                    current_node = body;
                    continue;
                }
            }

            if (init_node) |in| {
                if (getNakedImportPath(tree.*, in)) |rel| {
                    const next_abs = try Dir.path.resolve(
                        allocator,
                        &.{ Dir.path.dirname(current_path) orelse ".", rel },
                    );
                    defer allocator.free(next_abs);

                    if (ast_cache.getEntry(next_abs)) |entry| {
                        current_path = entry.key_ptr.*;
                    } else {
                        const source: [:0]u8 = Dir.readFileAllocOptions(
                            Dir.cwd(),
                            io,
                            next_abs,
                            allocator,
                            .unlimited,
                            Alignment.of(u8),
                            0,
                        ) catch |err| {
                            std.log.err("Failed to read file during FQN validation '{s}': {s}", .{ next_abs, @errorName(err) });
                            break;
                        };
                        const t = try allocator.create(Ast);
                        t.* = try Ast.parse(allocator, source, .zig);
                        const owned_key = try allocator.dupe(u8, next_abs);
                        try ast_cache.put(allocator, owned_key, t);
                        current_path = owned_key;
                    }
                    current_node = .root;
                } else {
                    current_node = node;
                }
            } else {
                current_node = node;
            }
        } else break;
    }
    return fqn[0..last_valid_end];
}
