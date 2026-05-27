//! Comptime-generic snapshot walker over the model's EntityManagers.
//!
//! Adding a new EntityManager field to data/model.zig extends the
//! snapshot automatically. Hand-written conversions are only needed
//! for fields that should be redacted or transformed at the boundary.

const std = @import("std");
const model_mod = @import("model.zig");
const types = @import("types.zig");

pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    counts: Counts,
    clients: []types.Client = &.{},
    resources: []types.Resource = &.{},
    surfaces: []types.Surface = &.{},
    buffers: []types.Buffer = &.{},
    embeds: []types.Embed = &.{},
    outputs: []types.Output = &.{},

    pub const Counts = struct {
        clients: usize = 0,
        resources: usize = 0,
        surfaces: usize = 0,
        buffers: usize = 0,
        embeds: usize = 0,
        outputs: usize = 0,
    };

    pub fn deinit(self: *Snapshot) void {
        const allocator = self.allocator;
        allocator.free(self.clients);
        allocator.free(self.resources);
        allocator.free(self.surfaces);
        allocator.free(self.buffers);
        allocator.free(self.embeds);
        allocator.free(self.outputs);
        self.* = .{ .allocator = allocator, .counts = .{} };
    }
};

/// Walk every EntityManager field on the model and collect a snapshot.
/// Uses @typeInfo to enumerate fields so new tables are picked up
/// without per-table plumbing.
pub fn snapshot(allocator: std.mem.Allocator, m: *const model_mod.Model) !Snapshot {
    var s: Snapshot = .{ .allocator = allocator, .counts = .{} };
    errdefer s.deinit();

    inline for (@typeInfo(model_mod.Model).@"struct".fields) |field| {
        if (comptime isEntityManager(field.type)) {
            const mgr: *const field.type = &@field(m, field.name);
            @field(s, field.name) = try allocator.dupe(field.type.Value, mgr.items());
        }
    }
    s.counts = .{
        .clients = s.clients.len,
        .resources = s.resources.len,
        .surfaces = s.surfaces.len,
        .buffers = s.buffers.len,
        .embeds = s.embeds.len,
        .outputs = s.outputs.len,
    };
    return s;
}

pub fn snapshotFree(s: *Snapshot) void {
    s.deinit();
}

fn isEntityManager(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    return @hasDecl(T, "insert") and @hasDecl(T, "count") and @hasDecl(T, "Value");
}

// ===== production code above =====

test "snapshot returns zero counts on empty model" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    var s = try snapshot(std.testing.allocator, &m);
    defer snapshotFree(&s);
    try std.testing.expectEqual(@as(usize, 0), s.counts.clients);
    try std.testing.expectEqual(@as(usize, 0), s.counts.embeds);
    try std.testing.expectEqual(@as(usize, 0), s.clients.len);
    try std.testing.expectEqual(@as(usize, 0), s.embeds.len);
}
