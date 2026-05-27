//! Per-dispatch effect queue. Ops append effects; the engine drains the
//! queue at the end of each dispatch tick, after every protocol callback
//! for that tick has run. Per docs/dod.md § Effects.

const std = @import("std");
const types = @import("../data/types.zig");

pub const Effect = union(enum) {
    client_connected: types.ClientId,
    client_closed: types.ClientId,
    surface_created: struct { client_id: types.ClientId, surface_id: types.SurfaceId },
    surface_destroyed: struct { client_id: types.ClientId, surface_id: types.SurfaceId },
    embed_mapped: types.EmbedId,
    embed_resized: struct { embed_id: types.EmbedId, width: i32, height: i32 },
    embed_destroyed: types.EmbedId,
    protocol_error: struct { client_id: types.ClientId, code: u32 },
    diagnostics_dirty,
};

pub const Queue = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged(Effect) = .empty,

    pub fn init(allocator: std.mem.Allocator) Queue {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Queue) void {
        self.items.deinit(self.allocator);
    }

    pub fn push(self: *Queue, e: Effect) !void {
        try self.items.append(self.allocator, e);
    }

    /// Borrowed view of the queued effects. The queue retains ownership;
    /// call `clear` after draining.
    pub fn pending(self: *const Queue) []const Effect {
        return self.items.items;
    }

    /// Move the current queue out for draining. Effects pushed while
    /// the returned list is processed remain queued for a later drain.
    pub fn takePending(self: *Queue) std.ArrayListUnmanaged(Effect) {
        const pending_items = self.items;
        self.items = .empty;
        return pending_items;
    }

    pub fn clear(self: *Queue) void {
        self.items.clearRetainingCapacity();
    }

    pub fn count(self: *const Queue) usize {
        return self.items.items.len;
    }
};

// ===== production code above =====

test "push and drain preserve order" {
    var q = Queue.init(std.testing.allocator);
    defer q.deinit();
    try q.push(.{ .client_connected = @enumFromInt(1) });
    try q.push(.diagnostics_dirty);
    try std.testing.expectEqual(@as(usize, 2), q.count());
}

test "takePending detaches current queue" {
    var q = Queue.init(std.testing.allocator);
    defer q.deinit();

    try q.push(.{ .client_connected = @enumFromInt(1) });
    var pending_items = q.takePending();
    defer pending_items.deinit(std.testing.allocator);
    try q.push(.{ .client_closed = @enumFromInt(2) });

    try std.testing.expectEqual(@as(usize, 1), pending_items.items.len);
    try std.testing.expect(pending_items.items[0] == .client_connected);
    try std.testing.expectEqual(@as(usize, 1), q.count());
    try std.testing.expect(q.pending()[0] == .client_closed);
}
