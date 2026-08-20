const std = @import("std");
const Io = std.Io;

const CLI = @import("../env/CLI.zig");

pub fn checkUnimplemented(terminal: *Io.Terminal, config: *const CLI.Config) bool {
    const writer = terminal.writer;
    var found = false;

    if (config.mode == .project) {
        writer.print("\n[WRN] Target Mode: '--mode project' is currently in roadmap (experimental).\n", .{}) catch {};
        found = true;
    }

    if (config.skeleton) {
        writer.print("[WRN] Roadmap Feature: '--skeleton' is currently implementation pending.\n", .{}) catch {};
        found = true;
    }

    if (config.users_target != null) {
        writer.print("[WRN] Extension: '--users' is currently implementation pending.\n", .{}) catch {};
        found = true;
    }

    if (config.trace_up != null) {
        writer.print("[WRN] Extension: '--trace-up' is currently implementation pending.\n", .{}) catch {};
        found = true;
    }

    if (config.target_files.items.len > 0) {
        writer.print("[WRN] Scope Filter: '--include' is currently implementation pending for project analysis.\n", .{}) catch {};
        found = true;
    }

    if (config.exclude_files.items.len > 0) {
        writer.print("[WRN] Scope Filter: '--exclude' is currently implementation pending for project analysis.\n", .{}) catch {};
        found = true;
    }

    if (found) {
        writer.writeAll("\nAnalysis aborted. These features are part of the Project Mode roadmap and not yet available in v1.0.0.\n") catch {};
    }

    return found;
}
