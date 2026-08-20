const std = @import("std");

const Context = @import("Context.zig");
const Files = @import("Scanner/Files.zig");
const Types = @import("Types.zig");

pub fn processFile(
    ctx: Context.AnalysisContext,
    file_path: []const u8,
    prefix_parts: []const Types.StringId,
) anyerror!void {
    try Files.processFile(ctx, file_path, prefix_parts);
}

pub fn processFileWithMember(
    ctx: Context.AnalysisContext,
    file_path: []const u8,
    member_name: []const u8,
    prefix_parts: []const Types.StringId,
) anyerror!void {
    try Files.processFileWithMember(ctx, file_path, member_name, prefix_parts);
}
