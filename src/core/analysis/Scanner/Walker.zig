const std = @import("std");
const mem = std.mem;
const Ast = std.zig.Ast;

const Context = @import("../Context.zig");
const Expression = @import("../Expression.zig");
const Types = @import("../Types.zig");
const Processor = @import("Processor.zig");

pub fn walkNodes(
    ctx: Context.AnalysisContext,
    tree: *const Ast,
    nodes: []const Ast.Node.Index,
    file_path: []const u8,
    prefix_parts: []const Types.StringId,
    scope: Types.SymbolScope,
) anyerror!void {
    for (nodes) |node| {
        if (@intFromEnum(node) >= tree.nodes.len) continue;
        const tag = tree.nodeTag(node);

        if (tag == .container_field_init or tag == .container_field_align or tag == .container_field) {
            try Processor.processField(ctx, tree, node, file_path, prefix_parts);
            continue;
        }

        if (tree.fullVarDecl(node)) |var_decl| {
            try Processor.processVar(ctx, tree, node, var_decl, file_path, prefix_parts, scope);
            continue;
        }

        var fn_buffer: [1]Ast.Node.Index = undefined;
        if (tree.fullFnProto(&fn_buffer, node)) |fn_proto| {
            try Processor.processFn(ctx, tree, node, fn_proto, file_path, prefix_parts, scope);
            continue;
        }

        if (tag == .@"if" or tag == .if_simple or tag == .@"switch" or tag == .switch_comma or tag == .@"return") {
            try Expression.scanExpression(ctx, tree, node, file_path, prefix_parts, scope);
            continue;
        }

        if (mem.eql(u8, tree.tokenSlice(tree.nodeMainToken(node)), "usingnamespace")) {
            const expr = if (tag == .builtin_call or tag == .builtin_call_two) node else tree.nodeData(node).node;
            try Expression.scanExpression(ctx, tree, expr, file_path, prefix_parts, scope);
            continue;
        }

        try Processor.processUnhandled(ctx, tree, node, file_path);
    }
}
