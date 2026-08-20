const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const Io = std.Io;
const Writer = Io.Writer;
const Allocator = mem.Allocator;
const SemanticVersion = std.SemanticVersion;

pub const Parser = @import("CLI/Parser.zig");
pub const parse = Parser.parse;
pub const Printer = @import("CLI/Printer.zig");
pub const Translator = @import("CLI/Translator.zig");
pub const detectLanguage = Translator.detectLanguage;
pub const Types = @import("CLI/Types.zig");
pub const Mode = Types.Mode;
pub const ColorMode = Types.ColorMode;
pub const Lang = Types.Lang;
pub const FilterMode = Types.FilterMode;
pub const ScanSpec = Types.ScanSpec;
pub const Config = Types.Config;
pub const UNLIMITED_DEPTH = Types.UNLIMITED_DEPTH;
pub const layer1_modules = Types.layer1_modules;

pub fn printHelp(
    config: *const Config,
    writer: *Writer,
    target_version: []const u8,
    std_path: []const u8,
    environ_map: *const std.process.Environ.Map,
) !void {
    var lang = config.lang;
    if (lang == .auto) {
        lang = Translator.detectLanguage(environ_map);
    }

    switch (lang) {
        .ja => try Printer.printHelpja(writer, target_version, std_path),
        else => try Printer.printHelp(writer, target_version, std_path),
    }
}

pub fn normalizeConfig(config: *Config, version: SemanticVersion) !void {
    for (config.lib_specs.items) |*spec| {
        var has_selection_filter = false;
        for (spec.filter_modes.items) |fm| {
            if (fm == .exclude_layer1) {
                spec.exclude_layer1 = true;
                continue;
            }
            has_selection_filter = true;
            const modules = try Translator.getModuleList(fm, version, config.allocator);

            defer if (fm == .group_app_dev_core) config.allocator.free(modules);

            for (modules) |mod| {
                const fqn = try fmt.allocPrint(config.allocator, "std.{s}", .{mod});
                try spec.scopes.append(config.allocator, fqn);
            }
        }

        if (spec.flagged_deprecated) {
            spec.depth = UNLIMITED_DEPTH;
        } else if (!spec.is_depth_explicit) {
            if (config.global_depth) |gd| {
                spec.depth = gd;
            } else if (spec.is_search) {
                spec.depth = UNLIMITED_DEPTH;
            } else if (spec.is_probe) {
                spec.depth = 1;
            } else if (has_selection_filter or spec.exclude_layer1) {
                spec.depth = 1;
            }
        }
        spec.show_counts = config.lib_show_counts;
    }
}
