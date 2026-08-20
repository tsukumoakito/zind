const std = @import("std");
const Io = std.Io;
const Atomic = std.atomic.Value;
const Tag = std.zig.Ast.Node.Tag;

pub const Summary = struct {
    files: u64,
    apis: u64,
    structs: u64,
    enums: u64,
    fns: u64,
    constants: u64,
    unhandled_total: u64,
};

pub const Metrics = struct {
    total_files: Atomic(u64) = Atomic(u64).init(0),
    total_apis: Atomic(u64) = Atomic(u64).init(0),
    total_structs: Atomic(u64) = Atomic(u64).init(0),
    total_enums: Atomic(u64) = Atomic(u64).init(0),
    total_fns: Atomic(u64) = Atomic(u64).init(0),
    total_constants: Atomic(u64) = Atomic(u64).init(0),
    unhandled_total: Atomic(u64) = Atomic(u64).init(0),

    pub fn recordFile(self: *Metrics) void {
        _ = self.total_files.fetchAdd(1, .monotonic);
    }

    pub fn recordStruct(self: *Metrics) void {
        _ = self.total_structs.fetchAdd(1, .monotonic);
        self.recordApi();
    }

    pub fn recordEnum(self: *Metrics) void {
        _ = self.total_enums.fetchAdd(1, .monotonic);
        self.recordApi();
    }

    pub fn recordFn(self: *Metrics) void {
        _ = self.total_fns.fetchAdd(1, .monotonic);
        self.recordApi();
    }

    pub fn recordConstant(self: *Metrics) void {
        _ = self.total_constants.fetchAdd(1, .monotonic);
        self.recordApi();
    }

    fn recordApi(self: *Metrics) void {
        _ = self.total_apis.fetchAdd(1, .monotonic);
    }

    pub fn recordUnhandled(self: *Metrics) void {
        _ = self.unhandled_total.fetchAdd(1, .monotonic);
    }

    pub fn getSummary(self: *const Metrics) Summary {
        return .{
            .files = self.total_files.load(.monotonic),
            .apis = self.total_apis.load(.monotonic),
            .structs = self.total_structs.load(.monotonic),
            .enums = self.total_enums.load(.monotonic),
            .fns = self.total_fns.load(.monotonic),
            .constants = self.total_constants.load(.monotonic),
            .unhandled_total = self.unhandled_total.load(.monotonic),
        };
    }

    pub fn printPerformanceReport(
        self: *const Metrics,
        stdout: *Io.Writer,
        report: struct {
            reg_count: usize,
            reg_cap: usize,
            pool_count: usize,
            pool_cap: usize,
            ast_count: usize,
            ast_limit: usize,
            visited_count: usize,
            visited_cap: usize,
            ws_len: usize,
            fqn_len: usize,
            fqn_cap: usize,
        },
    ) !void {
        const summary = self.getSummary();

        try stdout.writeAll("\n--- Zind Performance & Buffer Metrics (Debug) ---\n");

        try printLine(stdout, "Global Registry", report.reg_count, report.reg_cap, "entries");
        try printLine(stdout, "String Pool", report.pool_count, report.pool_cap, "strings");
        try printLine(stdout, "AST Cache", report.ast_count, report.ast_limit, "trees");
        try printLine(stdout, "Visited Map", report.visited_count, report.visited_cap, "entries");

        try stdout.print("  [Workspace Buffer] size: {d}B\n", .{report.ws_len});
        try stdout.print("  [FQN Writer] len: {d}B, capacity: {d}B ({d}%)\n", .{
            report.fqn_len,
            report.fqn_cap,
            if (report.fqn_cap > 0) (report.fqn_len * 100) / report.fqn_cap else 0,
        });

        try stdout.print("  [Logic Stats] apis: {d}, structs: {d}, enums: {d}, fns: {d}, consts: {d}, unhandled: {d}\n", .{
            summary.apis,
            summary.structs,
            summary.enums,
            summary.fns,
            summary.constants,
            summary.unhandled_total,
        });

        try stdout.writeAll("--------------------------------------------------\n");
    }

    fn printLine(stdout: *Io.Writer, label: []const u8, count: usize, cap: usize, unit: []const u8) !void {
        const usage = if (cap > 0) (count * 100) / cap else 0;
        try stdout.print("  [{s}] {s}: {d}, capacity: {d} ({d}%)\n", .{ label, unit, count, cap, usage });
    }
};
