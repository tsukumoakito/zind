const std = @import("std");

pub const core = struct {
    pub const env = struct {
        pub const CLI = @import("core/env/CLI.zig");
        pub const Discovery = @import("core/env/Discovery.zig");
        pub const PathFinder = @import("core/env/PathFinder.zig");
    };

    pub const system = struct {
        pub const BinaryParser = @import("core/system/BinaryParser.zig");
    };

    pub const registry = struct {
        pub const Metrics = @import("core/registry/Metrics.zig");
    };

    pub const analysis = struct {
        pub const Context = @import("core/analysis/Context.zig");
        pub const Types = @import("core/analysis/Types.zig");

        pub const AstUtils = @import("core/analysis/AstUtils.zig");
        pub const Resolver = @import("core/analysis/Resolver.zig");
        pub const Formatter = @import("core/analysis/Formatter.zig");
        pub const Utils = @import("core/analysis/Utils.zig");

        pub const Scanner = struct {
            pub const Facade = @import("core/analysis/Scanner.zig");
            pub const Files = @import("core/analysis/Scanner/Files.zig");
            pub const Walker = @import("core/analysis/Scanner/Walker.zig");
            pub const Processor = @import("core/analysis/Scanner/Processor.zig");
        };

        pub const Expression = struct {
            pub const Main = @import("core/analysis/Expression.zig");
            pub const Handlers = @import("core/analysis/Expression/Handlers.zig");
        };

        pub const Library = @import("core/analysis/Library.zig");
        pub const Project = @import("core/analysis/Project.zig");
    };
};
