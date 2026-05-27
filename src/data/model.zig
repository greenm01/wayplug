//! Runtime model: EntityManagers for each record type plus the
//! relationship indexes that pin Wayland handles to logical ids.
//!
//! Per docs/dod.md § Model. The model owns the server allocator;
//! engine code reads it from here rather than taking it as a parameter.

const std = @import("std");
const types = @import("types.zig");
const wlc = @import("../wayland/client.zig");
const wls = @import("../wayland/server.zig");

/// Dense-ish entity manager. Backed by an array hash map keyed on the
/// logical id. Provides the low-level CRUD documented in
/// docs/dod.md § Entity Manager. Real dense storage with swap-and-pop
/// can replace this without changing callers.
pub fn EntityManager(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Map = std.AutoArrayHashMapUnmanaged(K, V);

        records: Map = .empty,

        pub const empty: Self = .{};

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.records.deinit(allocator);
        }

        pub fn insert(self: *Self, allocator: std.mem.Allocator, key: K, value: V) !void {
            try self.records.put(allocator, key, value);
        }

        pub fn delete(self: *Self, key: K) bool {
            return self.records.swapRemove(key);
        }

        pub fn contains(self: *const Self, key: K) bool {
            return self.records.contains(key);
        }

        pub fn get(self: *const Self, key: K) ?V {
            return self.records.get(key);
        }

        pub fn getMutable(self: *Self, key: K) ?*V {
            return self.records.getPtr(key);
        }

        pub fn items(self: *const Self) []V {
            return self.records.values();
        }

        pub fn count(self: *const Self) usize {
            return self.records.count();
        }
    };
}

pub const Model = struct {
    allocator: std.mem.Allocator,
    counters: types.IdCounters = .{},

    clients: EntityManager(types.ClientId, types.Client) = .empty,
    resources: EntityManager(types.ResourceId, types.Resource) = .empty,
    surfaces: EntityManager(types.SurfaceId, types.Surface) = .empty,
    buffers: EntityManager(types.BufferId, types.Buffer) = .empty,
    embeds: EntityManager(types.EmbedId, types.Embed) = .empty,
    outputs: EntityManager(types.OutputId, types.Output) = .empty,

    client_by_wl_client: std.AutoArrayHashMapUnmanaged(*wls.wl_client, types.ClientId) = .empty,
    client_by_display: std.AutoArrayHashMapUnmanaged(*wlc.wl_display, types.ClientId) = .empty,
    resource_by_wl_resource: std.AutoArrayHashMapUnmanaged(*wls.wl_resource, types.ResourceId) = .empty,
    resource_by_upstream_proxy: std.AutoArrayHashMapUnmanaged(*wlc.wl_proxy, types.ResourceId) = .empty,
    surface_by_resource: std.AutoArrayHashMapUnmanaged(types.ResourceId, types.SurfaceId) = .empty,
    buffer_by_resource: std.AutoArrayHashMapUnmanaged(types.ResourceId, types.BufferId) = .empty,
    embed_by_child_surface: std.AutoArrayHashMapUnmanaged(types.SurfaceId, types.EmbedId) = .empty,
    embed_by_parent_surface: std.AutoArrayHashMapUnmanaged(types.SurfaceId, types.EmbedId) = .empty,

    pub fn init(allocator: std.mem.Allocator) Model {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Model) void {
        self.clients.deinit(self.allocator);
        self.resources.deinit(self.allocator);
        self.surfaces.deinit(self.allocator);
        self.buffers.deinit(self.allocator);
        self.embeds.deinit(self.allocator);
        self.outputs.deinit(self.allocator);

        self.client_by_wl_client.deinit(self.allocator);
        self.client_by_display.deinit(self.allocator);
        self.resource_by_wl_resource.deinit(self.allocator);
        self.resource_by_upstream_proxy.deinit(self.allocator);
        self.surface_by_resource.deinit(self.allocator);
        self.buffer_by_resource.deinit(self.allocator);
        self.embed_by_child_surface.deinit(self.allocator);
        self.embed_by_parent_surface.deinit(self.allocator);
    }

    pub fn nextClientId(self: *Model) !types.ClientId {
        self.counters.client += 1;
        if (self.counters.client == 0) return error.IdSpaceExhausted;
        return @enumFromInt(self.counters.client);
    }

    pub fn nextResourceId(self: *Model) !types.ResourceId {
        self.counters.resource += 1;
        if (self.counters.resource == 0) return error.IdSpaceExhausted;
        return @enumFromInt(self.counters.resource);
    }

    pub fn nextSurfaceId(self: *Model) !types.SurfaceId {
        self.counters.surface += 1;
        if (self.counters.surface == 0) return error.IdSpaceExhausted;
        return @enumFromInt(self.counters.surface);
    }

    pub fn nextBufferId(self: *Model) !types.BufferId {
        self.counters.buffer += 1;
        if (self.counters.buffer == 0) return error.IdSpaceExhausted;
        return @enumFromInt(self.counters.buffer);
    }

    pub fn nextEmbedId(self: *Model) !types.EmbedId {
        self.counters.embed += 1;
        if (self.counters.embed == 0) return error.IdSpaceExhausted;
        return @enumFromInt(self.counters.embed);
    }

    pub fn nextOutputId(self: *Model) !types.OutputId {
        self.counters.output += 1;
        if (self.counters.output == 0) return error.IdSpaceExhausted;
        return @enumFromInt(self.counters.output);
    }
};

// ===== production code above =====

test "Model init/deinit round-trips" {
    var model = Model.init(std.testing.allocator);
    defer model.deinit();
    try std.testing.expectEqual(@as(usize, 0), model.clients.count());
}

test "Id counters increment before issue" {
    var model = Model.init(std.testing.allocator);
    defer model.deinit();
    const id1 = try model.nextClientId();
    const id2 = try model.nextClientId();
    try std.testing.expect(@intFromEnum(id1) == 1);
    try std.testing.expect(@intFromEnum(id2) == 2);
}

test "EntityManager insert/get/delete round-trip" {
    var model = Model.init(std.testing.allocator);
    defer model.deinit();

    const id = try model.nextClientId();
    try model.clients.insert(model.allocator, id, .{
        .id = id,
        .state = .connected,
        .server_fd = -1,
        .client_fd = -1,
        .wl_client = null,
        .wl_display = null,
    });
    try std.testing.expect(model.clients.contains(id));
    try std.testing.expectEqual(@as(usize, 1), model.clients.count());

    const got = model.clients.get(id).?;
    try std.testing.expect(got.state == .connected);

    try std.testing.expect(model.clients.delete(id));
    try std.testing.expect(!model.clients.contains(id));
}
