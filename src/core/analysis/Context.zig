const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const Dir = Io.Dir;
const Ast = std.zig.Ast;
const ArrayList = std.ArrayList;
const StringHashMap = std.array_hash_map.String;
const AutoHashMap = std.array_hash_map.Auto;
const HashMap = std.hash_map.HashMap;
const Allocator = mem.Allocator;

const Metrics = @import("../registry/Metrics.zig").Metrics;
const Types = @import("Types.zig");

pub const AstCacheManager = struct {
    map: AutoHashMap(Types.StringId, *Ast) = AutoHashMap(Types.StringId, *Ast).empty,
    lru_list: ArrayList(Types.StringId) = ArrayList(Types.StringId).empty,
    capacity: usize,

    pub fn deinit(self: *AstCacheManager, allocator: Allocator) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(allocator);
            allocator.destroy(entry.value_ptr.*);
        }
        self.map.deinit(allocator);
        self.lru_list.deinit(allocator);
    }

    pub fn get(self: *const AstCacheManager, id: Types.StringId) ?*Ast {
        return self.map.get(id);
    }

    pub fn put(self: *AstCacheManager, allocator: Allocator, id: Types.StringId, tree: *Ast, stack: []const Types.NodeIdentity) !void {
        if (self.map.count() >= self.capacity) {
            self.prune(allocator, stack);
        }

        try self.map.put(allocator, id, tree);
        try self.lru_list.append(allocator, id);
    }

    fn prune(self: *AstCacheManager, allocator: Allocator, stack: []const Types.NodeIdentity) void {
        var i: usize = 0;
        while (i < self.lru_list.items.len) : (i += 1) {
            const id = self.lru_list.items[i];
            var is_protected = false;

            for (stack) |node_id| {
                if (node_id.path_id == id) {
                    is_protected = true;
                    break;
                }
            }

            if (!is_protected) {
                _ = self.lru_list.orderedRemove(i);
                if (self.map.fetchSwapRemove(id)) |kv| {
                    kv.value.deinit(allocator);
                    allocator.destroy(kv.value);
                }
                return;
            }
        }
    }
};

pub const AnalysisContext = struct {
    allocator: Allocator,
    registry_allocator: Allocator,
    io: Io,
    root_path_id: Types.StringId,
    root_name_id: Types.StringId,
    registry: *ArrayList(Types.ApiEntry),
    pool: *Types.StringPool,
    path_cache: *StringHashMap(Types.StringId),
    visited: *HashMap(Types.VisitedKey, void, Types.VisitedContext, std.hash_map.default_max_load_percentage),
    ast_cache: *AstCacheManager,
    count_cache: *StringHashMap(usize),
    unhandled_list: *ArrayList(Types.UnhandledNode),
    dead_ends: *ArrayList(Types.DeadEnd),
    stack: *ArrayList(Types.NodeIdentity),
    pub_hidden_count: *usize,
    priv_hidden_count: *usize,
    fqn_writer: *Io.Writer.Allocating,
    terminal: *Io.Terminal,
    path_buf: *[Dir.max_path_bytes]u8,
    workspace_buf: []u8,
    filters: []const []const u8,
    search_terms: []const []const u8,
    depth_limit: ?usize,
    pub_only: bool,
    flagged_deprecated: bool,
    show_counts: bool,
    is_dry_run: bool,
    exclude_layer1: bool,
    current_cond_id: ?Types.StringId,
    inherited_dep_id: ?Types.StringId,
    debug_mode: bool,
    metrics: *Metrics,
    link_libc: ?bool,
    target_os: ?[]const u8,
    target_arch: ?[]const u8,
    show_private: bool,
    is_explicit_target: bool,

    pub fn derive(self: AnalysisContext) AnalysisContext {
        return self;
    }

    pub fn withCond(self: AnalysisContext, cond_id: ?Types.StringId) AnalysisContext {
        var next = self;
        next.current_cond_id = cond_id;
        return next;
    }

    pub fn withDep(self: AnalysisContext, dep_id: ?Types.StringId) AnalysisContext {
        var next = self;
        next.inherited_dep_id = dep_id;
        return next;
    }

    pub fn withDepth(self: AnalysisContext, depth: ?usize) AnalysisContext {
        var next = self;
        next.depth_limit = depth;
        return next;
    }

    pub fn withTarget(self: AnalysisContext, hit: bool) AnalysisContext {
        var next = self;
        next.is_explicit_target = hit;
        return next;
    }

    pub fn withCounters(self: AnalysisContext, pub_ptr: *usize, priv_ptr: *usize) AnalysisContext {
        var next = self;
        next.pub_hidden_count = pub_ptr;
        next.priv_hidden_count = priv_ptr;
        return next;
    }

    pub fn asDryRun(self: AnalysisContext) AnalysisContext {
        var next = self;
        next.is_dry_run = true;
        next.flagged_deprecated = false;
        next.search_terms = &.{};
        next.filters = &.{};
        next.depth_limit = null;
        next.is_explicit_target = false;
        return next;
    }
};
