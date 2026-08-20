const std = @import("std");
const mem = std.mem;
const Ast = std.zig.Ast;
const ArrayList = std.ArrayList;
const StringHashMap = std.array_hash_map.String;
const Allocator = mem.Allocator;
const Wyhash = std.hash.Wyhash;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const StringId = u32;

pub const StringPool = struct {
    map: StringHashMap(void) = StringHashMap(void).empty,
    arena: ArenaAllocator,

    pub fn init(allocator: Allocator) StringPool {
        return .{
            .arena = ArenaAllocator.init(allocator),
        };
    }

    pub fn getOrPut(self: *StringPool, allocator: Allocator, s: []const u8) !StringId {
        const res = try self.map.getOrPut(allocator, s);
        if (!res.found_existing) {
            res.key_ptr.* = try self.arena.allocator().dupe(u8, s);
        }
        return @intCast(res.index);
    }

    pub fn get(self: *const StringPool, id: StringId) []const u8 {
        return self.map.keys()[id];
    }

    pub fn deinit(self: *StringPool, allocator: Allocator) void {
        self.arena.deinit();
        self.map.deinit(allocator);
    }
};

pub const VisitedKey = struct {
    file_id: StringId,
    fqn_parts: []const StringId,
    cond_id: ?StringId,
};

pub const VisitedContext = struct {
    pub fn hash(_: VisitedContext, key: VisitedKey) u64 {
        var h = Wyhash.init(0);
        h.update(mem.asBytes(&key.file_id));
        h.update(mem.sliceAsBytes(key.fqn_parts));
        if (key.cond_id) |c| h.update(mem.asBytes(&c));
        return h.final();
    }

    pub fn eql(_: VisitedContext, a: VisitedKey, b: VisitedKey) bool {
        return a.file_id == b.file_id and
            a.cond_id == b.cond_id and
            mem.eql(StringId, a.fqn_parts, b.fqn_parts);
    }
};

pub const SourceCoordinate = struct {
    file_id: StringId,
    node: Ast.Node.Index,
};

pub const TraceStep = struct {
    formatted_id: StringId,
    dep_id: ?StringId,
    node: Ast.Node.Index,
    path_id: StringId,
};

pub const ApiEntry = struct {
    fqn_parts: []const StringId,
    full_fqn_id: StringId,
    cond_id: ?StringId,
    dep_id: ?StringId,
    rhs_id: ?StringId,
    trace_chain: []const TraceStep,
    coord: SourceCoordinate,
    is_explicit_dep: bool,
    is_private: bool,
    is_target_hit: bool,
    child_count: usize,
    priv_child_count: usize,

    pub fn deinit(self: ApiEntry, allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const ImportRes = struct {
    path_id: StringId,
    member_id: ?StringId,

    pub fn deinit(self: ImportRes, allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const NodeIdentity = struct {
    path_id: StringId,
    node: Ast.Node.Index,
};

pub const UnhandledNode = struct {
    tag_id: StringId,
    loc_id: StringId,

    pub fn deinit(self: UnhandledNode, allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const SymbolScope = struct {
    map: *const StringHashMap(Ast.Node.Index),
    parent: ?*const SymbolScope = null,

    pub fn get(self: SymbolScope, name: []const u8) ?Ast.Node.Index {
        var current: ?*const SymbolScope = &self;
        while (current) |s| {
            if (s.map.get(name)) |node| return node;
            current = s.parent;
        }
        return null;
    }
};

pub const TraceResult = struct {
    steps: ArrayList(TraceStep) = ArrayList(TraceStep).empty,
    final_node: ?Ast.Node.Index = null,
    final_path_id: StringId,
    final_tree: *const Ast,
    final_symbols: SymbolScope,

    pub fn deinit(self: *TraceResult, allocator: Allocator) void {
        self.steps.deinit(allocator);
    }
};

pub const DeadEnd = struct {
    requested_id: StringId,
    last_valid_id: StringId,

    pub fn deinit(self: DeadEnd, allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub inline fn eqlStringIdSlice(a: []const StringId, b: []const StringId) bool {
    return mem.eql(StringId, a, b);
}

pub inline fn hashStringIdSlice(slice: []const StringId) u64 {
    var h = Wyhash.init(0);
    h.update(mem.sliceAsBytes(slice));
    return h.final();
}
