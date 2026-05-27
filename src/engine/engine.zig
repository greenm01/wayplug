//! Engine facade. The protocol layer and c_api.zig reach into the
//! engine only through this module. Domain-specific ops, queries, and
//! policy live in sibling files.

const std = @import("std");
const types = @import("../data/types.zig");
const model_mod = @import("../data/model.zig");

pub const client = @import("client.zig");
pub const resource = @import("resource.zig");
pub const surface = @import("surface.zig");
pub const buffer = @import("buffer.zig");
pub const embed = @import("embed.zig");
pub const output = @import("output.zig");
pub const effects = @import("effects.zig");

pub const Engine = struct {
    model: model_mod.Model,
    effects: effects.Queue,
    state: types.ServerState = .stopped,

    pub fn init(allocator: std.mem.Allocator) Engine {
        return .{
            .model = model_mod.Model.init(allocator),
            .effects = effects.Queue.init(allocator),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.effects.deinit();
        self.model.deinit();
    }

    pub fn clientCreate(self: *Engine, server_fd: i32, client_fd: i32) !types.ClientId {
        const id = try client.clientCreate(&self.model, server_fd, client_fd);
        errdefer client.clientDestroy(&self.model, id);
        try self.effects.push(.{ .client_connected = id });
        return id;
    }

    pub fn clientSetWaylandHandles(
        self: *Engine,
        id: types.ClientId,
        wl_client: *@import("../wayland/server.zig").wl_client,
        display: *@import("../wayland/client.zig").wl_display,
    ) !void {
        try client.clientSetWaylandHandles(&self.model, id, wl_client, display);
    }

    pub fn clientDestroy(self: *Engine, id: types.ClientId) !void {
        if (!self.model.clients.contains(id)) return;
        for (self.model.embeds.items()) |record| {
            if (record.client_id == id) try self.effects.push(.{ .embed_destroyed = record.id });
        }
        client.clientDestroy(&self.model, id);
        try self.effects.push(.{ .client_closed = id });
    }

    pub fn protocolError(self: *Engine, client_id: types.ClientId, code: u32) !void {
        if (!self.model.clients.contains(client_id)) return;
        try self.effects.push(.{ .protocol_error = .{ .client_id = client_id, .code = code } });
    }

    pub fn resourceCreate(
        self: *Engine,
        client_id: types.ClientId,
        kind: types.ResourceKind,
        wl_resource: ?*@import("../wayland/server.zig").wl_resource,
        upstream_proxy: ?*@import("../wayland/client.zig").wl_proxy,
    ) !types.ResourceId {
        return resource.resourceCreate(&self.model, client_id, kind, wl_resource, upstream_proxy);
    }

    pub fn resourceDestroy(self: *Engine, id: types.ResourceId) void {
        resource.resourceDestroy(&self.model, id);
    }

    pub fn surfaceCreate(self: *Engine, client_id: types.ClientId, resource_id: types.ResourceId) !types.SurfaceId {
        const id = try surface.surfaceCreate(&self.model, client_id, resource_id);
        errdefer surface.surfaceDestroy(&self.model, id);
        try self.effects.push(.{ .surface_created = .{ .client_id = client_id, .surface_id = id } });
        return id;
    }

    pub fn surfaceForResource(self: *const Engine, resource_id: types.ResourceId) ?types.SurfaceId {
        return surface.surfaceForResource(&self.model, resource_id);
    }

    pub fn bufferCreate(self: *Engine, client_id: types.ClientId, resource_id: types.ResourceId) !types.BufferId {
        return buffer.bufferCreate(&self.model, client_id, resource_id);
    }

    pub fn upstreamProxyForResource(self: *const Engine, resource_id: types.ResourceId) ?*@import("../wayland/client.zig").wl_proxy {
        return resource.upstreamProxyForResource(&self.model, resource_id);
    }

    pub fn resourceForUpstreamProxy(self: *const Engine, proxy: *@import("../wayland/client.zig").wl_proxy) ?types.ResourceId {
        return resource.resourceForUpstreamProxy(&self.model, proxy);
    }

    pub fn embedCreate(self: *Engine, client_id: types.ClientId, host_parent_surface: types.SurfaceId) !types.EmbedId {
        return embed.embedCreate(&self.model, client_id, host_parent_surface);
    }

    pub fn embedAttachChild(self: *Engine, id: types.EmbedId, child_surface: types.SurfaceId) !void {
        try embed.embedAttachChild(&self.model, id, child_surface);
    }

    pub fn embedSetSubsurfaceResource(self: *Engine, id: types.EmbedId, resource_id: types.ResourceId) !void {
        try embed.embedSetSubsurfaceResource(&self.model, id, resource_id);
    }

    pub fn embedMap(self: *Engine, id: types.EmbedId) !void {
        try embed.embedMap(&self.model, id);
        try self.effects.push(.{ .embed_mapped = id });
    }

    pub fn embedResize(self: *Engine, id: types.EmbedId, width: i32, height: i32) !void {
        try embed.embedResize(&self.model, id, width, height);
        try self.effects.push(.{ .embed_resized = .{ .embed_id = id, .width = width, .height = height } });
    }

    pub fn embedDestroy(self: *Engine, id: types.EmbedId) !void {
        if (!self.model.embeds.contains(id)) return;
        embed.embedDestroy(&self.model, id);
        try self.effects.push(.{ .embed_destroyed = id });
    }
};

// ===== production code above =====

test "Engine init/deinit round-trips" {
    var e = Engine.init(std.testing.allocator);
    defer e.deinit();
    try std.testing.expect(e.state == .stopped);
}
