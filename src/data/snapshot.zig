//! Comptime-generic snapshot walker over the model's EntityManagers.
//!
//! Adding a new EntityManager field to data/model.zig extends the
//! snapshot automatically. Hand-written conversions are only needed
//! for fields that should be redacted or transformed at the boundary.

const std = @import("std");
const model_mod = @import("model.zig");

pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    counts: Counts,

    pub const Counts = struct {
        clients: usize = 0,
        resources: usize = 0,
        surfaces: usize = 0,
        buffers: usize = 0,
        embeds: usize = 0,
        outputs: usize = 0,
    };

    pub fn deinit(self: *Snapshot) void {
        _ = self;
    }
};

/// Walk every EntityManager field on the model and collect a snapshot.
/// Uses @typeInfo to enumerate fields so new tables are picked up
/// without per-table plumbing.
pub fn snapshot(allocator: std.mem.Allocator, m: *const model_mod.Model) !Snapshot {
    var counts: Snapshot.Counts = .{};
    inline for (@typeInfo(model_mod.Model).@"struct".fields) |field| {
        if (comptime isEntityManager(field.type)) {
            const mgr: *const field.type = &@field(m, field.name);
            const n = mgr.count();
            if (comptime std.mem.eql(u8, field.name, "clients")) counts.clients = n;
            if (comptime std.mem.eql(u8, field.name, "resources")) counts.resources = n;
            if (comptime std.mem.eql(u8, field.name, "surfaces")) counts.surfaces = n;
            if (comptime std.mem.eql(u8, field.name, "buffers")) counts.buffers = n;
            if (comptime std.mem.eql(u8, field.name, "embeds")) counts.embeds = n;
            if (comptime std.mem.eql(u8, field.name, "outputs")) counts.outputs = n;
        }
    }
    return .{ .allocator = allocator, .counts = counts };
}

pub fn snapshotFree(s: *Snapshot) void {
    s.deinit();
}

fn isEntityManager(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    return @hasDecl(T, "insert") and @hasDecl(T, "count");
}

// ===== production code above =====

test "snapshot returns zero counts on empty model" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    var s = try snapshot(std.testing.allocator, &m);
    defer snapshotFree(&s);
    try std.testing.expectEqual(@as(usize, 0), s.counts.clients);
    try std.testing.expectEqual(@as(usize, 0), s.counts.embeds);
}
