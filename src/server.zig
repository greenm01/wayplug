//! Internal server runtime behind the opaque `wayplug_server` handle.
//! Owns the engine, the host wrapper, and the upstream event queue.

const std = @import("std");
const c_api = @import("c_api.zig");
const snapshot_mod = @import("data/snapshot.zig");
const types = @import("data/types.zig");
const engine_mod = @import("engine/engine.zig");
const host_mod = @import("host.zig");
const protocol_registry = @import("protocol/registry.zig");
const protocol_runtime = @import("protocol/runtime.zig");
const wlc = @import("wayland/client.zig");
const wlp = @import("wayland/protocols.zig");
const wls = @import("wayland/server.zig");

const sys = @cImport({
    @cInclude("fcntl.h");
    @cInclude("sys/socket.h");
    @cInclude("unistd.h");
});

pub const ClientHandle = struct {
    server: *Server,
    client_id: types.ClientId,
    wl_client: ?*wls.wl_client,
    display: ?*wlc.wl_display,
    close_pending: bool = false,
};

pub const ResourceData = struct {
    server: *Server,
    client_id: types.ClientId,
    resource_id: types.ResourceId,
    wl_resource: *wls.wl_resource,
    kind: types.ResourceKind,
    upstream_proxy: ?*wlc.wl_proxy,
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    engine: engine_mod.Engine,
    host_iface: c_api.WayplugHostInterface,
    host: host_mod.Host,
    display: *wls.wl_display,
    event_loop: *wls.wl_event_loop,
    queue: ?*wlc.wl_event_queue,
    client_handles: std.ArrayListUnmanaged(*ClientHandle) = .empty,
    globals: std.ArrayListUnmanaged(*wls.wl_global) = .empty,

    pub fn create(
        allocator: std.mem.Allocator,
        iface: *const c_api.WayplugHostInterface,
        queue: ?*wlc.wl_event_queue,
    ) !*Server {
        const display = wls.c.wl_display_create() orelse return error.OutOfMemory;
        errdefer wls.c.wl_display_destroy(display);

        const event_loop = wls.c.wl_display_get_event_loop(display) orelse return error.InvalidArgument;

        const s = try allocator.create(Server);
        s.* = .{
            .allocator = allocator,
            .engine = engine_mod.Engine.init(allocator),
            .host_iface = iface.*,
            .host = undefined,
            .display = display,
            .event_loop = event_loop,
            .queue = queue,
        };
        s.host = host_mod.Host.init(&s.host_iface);
        s.engine.state = .running;
        try s.registerGlobals();
        return s;
    }

    pub fn destroy(self: *Server) void {
        self.engine.state = .shutting_down;
        while (self.globals.pop()) |global| {
            wls.c.wl_global_destroy(global);
        }
        self.globals.deinit(self.allocator);
        while (self.client_handles.pop()) |handle| {
            self.closeClientHandle(handle, false);
            self.allocator.destroy(handle);
        }
        self.client_handles.deinit(self.allocator);
        wls.c.wl_display_destroy_clients(self.display);
        wls.c.wl_display_destroy(self.display);
        self.engine.deinit();
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    pub fn getFd(self: *Server) c_int {
        return wls.c.wl_event_loop_get_fd(self.event_loop);
    }

    pub fn dispatch(self: *Server) void {
        _ = wls.c.wl_event_loop_dispatch(self.event_loop, 0);
        self.drainEffects();
    }

    pub fn flush(self: *Server) void {
        wls.c.wl_display_flush_clients(self.display);
    }

    pub fn snapshot(self: *Server) !snapshot_mod.Snapshot {
        return snapshot_mod.snapshot(self.allocator, &self.engine.model);
    }

    pub fn openClientDisplay(self: *Server) ?*wlc.wl_display {
        var fds: [2]c_int = undefined;
        if (sys.socketpair(sys.AF_UNIX, sys.SOCK_STREAM, 0, &fds) != 0) return null;
        var server_fd_owned = true;
        var client_fd_owned = true;
        defer {
            if (server_fd_owned) _ = sys.close(fds[0]);
        }
        defer {
            if (client_fd_owned) _ = sys.close(fds[1]);
        }

        _ = sys.fcntl(fds[0], sys.F_SETFD, sys.FD_CLOEXEC);
        _ = sys.fcntl(fds[1], sys.F_SETFD, sys.FD_CLOEXEC);

        const wl_client = wls.c.wl_client_create(self.display, fds[0]) orelse return null;
        server_fd_owned = false;
        var wl_client_cleanup: ?*wls.wl_client = wl_client;
        defer if (wl_client_cleanup) |client| wls.c.wl_client_destroy(client);

        const client_display = wlc.c.wl_display_connect_to_fd(fds[1]) orelse return null;
        client_fd_owned = false;
        var client_display_cleanup: ?*wlc.wl_display = client_display;
        defer if (client_display_cleanup) |display| wlc.c.wl_display_disconnect(display);

        const client_id = self.engine.clientCreate(fds[0], fds[1]) catch return null;
        var client_id_cleanup: ?types.ClientId = client_id;
        defer if (client_id_cleanup) |id| self.engine.clientDestroy(id) catch {};
        self.engine.clientSetWaylandHandles(client_id, wl_client, client_display) catch return null;

        const handle = self.allocator.create(ClientHandle) catch return null;
        var handle_cleanup: ?*ClientHandle = handle;
        defer if (handle_cleanup) |h| self.allocator.destroy(h);
        handle.* = .{
            .server = self,
            .client_id = client_id,
            .wl_client = wl_client,
            .display = client_display,
        };
        self.client_handles.append(self.allocator, handle) catch return null;
        wl_client_cleanup = null;
        client_display_cleanup = null;
        client_id_cleanup = null;
        handle_cleanup = null;

        self.flush();
        return client_display;
    }

    pub fn closeClientDisplay(self: *Server, display: *wlc.wl_display) bool {
        const handle = self.findClientHandleByDisplay(display) orelse return false;
        self.closeClientHandle(handle, true);
        return true;
    }

    fn findClientHandleByDisplay(self: *Server, display: *wlc.wl_display) ?*ClientHandle {
        for (self.client_handles.items) |handle| {
            if (handle.display == display) return handle;
        }
        return null;
    }

    fn findClientHandleById(self: *Server, client_id: types.ClientId) ?*ClientHandle {
        for (self.client_handles.items) |handle| {
            if (handle.client_id == client_id) return handle;
        }
        return null;
    }

    fn closeClientHandle(self: *Server, handle: *ClientHandle, emit_effect: bool) void {
        if (emit_effect) {
            self.engine.clientDestroy(handle.client_id) catch {};
            handle.close_pending = true;
        } else {
            @import("engine/client.zig").clientDestroy(&self.engine.model, handle.client_id);
        }
        if (handle.display) |display| {
            wlc.c.wl_display_disconnect(display);
            handle.display = null;
        }
        if (handle.wl_client) |wl_client| {
            wls.c.wl_client_destroy(wl_client);
            handle.wl_client = null;
        }
    }

    fn drainEffects(self: *Server) void {
        const pending = self.engine.effects.pending();
        for (pending) |effect| {
            switch (effect) {
                .client_connected => |client_id| {
                    self.host.onClientConnected(opaqueClient(self.findClientHandleById(client_id)));
                },
                .client_closed => |client_id| {
                    const handle = self.findClientHandleById(client_id);
                    self.host.onClientClosed(opaqueClient(handle));
                    if (handle) |h| self.freeClientHandle(h);
                },
                .surface_created => |created| {
                    const handle = self.findClientHandleById(created.client_id);
                    const surface = self.upstreamSurfaceForId(created.surface_id);
                    self.host.onSurfaceCreated(opaqueClient(handle), surface);
                },
                .protocol_error => |err| {
                    const handle = self.findClientHandleById(err.client_id);
                    self.host.onProtocolError(opaqueClient(handle), err.code);
                },
                else => {},
            }
        }
        self.engine.effects.clear();
    }

    fn freeClientHandle(self: *Server, handle: *ClientHandle) void {
        for (self.client_handles.items, 0..) |candidate, i| {
            if (candidate == handle) {
                _ = self.client_handles.swapRemove(i);
                self.allocator.destroy(handle);
                return;
            }
        }
    }

    fn upstreamSurfaceForId(self: *Server, surface_id: types.SurfaceId) ?*wlp.wl_surface {
        const surface = self.engine.model.surfaces.get(surface_id) orelse return null;
        const proxy = self.engine.upstreamProxyForResource(surface.resource_id) orelse return null;
        return @ptrCast(proxy);
    }

    fn registerGlobals(self: *Server) !void {
        if (self.host.getCompositor() != null) {
            try self.registerGlobal(&wls.c.wl_compositor_interface, 4, registry_bindings.bindCompositor);
        }
        if (self.host.getSubcompositor() != null) {
            try self.registerGlobal(&wls.c.wl_subcompositor_interface, 1, registry_bindings.bindSubcompositor);
        }
        if (self.host.getShm() != null) {
            try self.registerGlobal(&wls.c.wl_shm_interface, 1, registry_bindings.bindShm);
        }
    }

    fn registerGlobal(
        self: *Server,
        interface: *const wls.wl_interface,
        version: c_int,
        bind: wls.c.wl_global_bind_func_t,
    ) !void {
        const global = wls.c.wl_global_create(self.display, interface, version, self, bind) orelse return error.OutOfMemory;
        errdefer wls.c.wl_global_destroy(global);
        try self.globals.append(self.allocator, global);
    }

    fn clientIdForWlClient(self: *Server, client: *wls.wl_client) ?types.ClientId {
        return engine_mod.client.clientForWlClient(&self.engine.model, client);
    }

    pub fn protocolErrorForClient(self: *Server, client: *wls.wl_client, code: u32) void {
        const client_id = self.clientIdForWlClient(client) orelse return;
        self.engine.protocolError(client_id, code) catch {};
    }

    pub fn createResource(
        self: *Server,
        client: *wls.wl_client,
        kind: types.ResourceKind,
        interface: *const wls.wl_interface,
        version: u32,
        id: u32,
        implementation: ?*const anyopaque,
        upstream_proxy: ?*wlc.wl_proxy,
    ) ?*wls.wl_resource {
        const client_id = self.clientIdForWlClient(client) orelse {
            wls.c.wl_client_post_no_memory(client);
            return null;
        };
        const resource = wls.c.wl_resource_create(client, interface, @intCast(version), id) orelse {
            wls.c.wl_client_post_no_memory(client);
            return null;
        };
        const resource_id = self.engine.resourceCreate(client_id, kind, resource, upstream_proxy) catch {
            wls.c.wl_client_post_no_memory(client);
            wls.c.wl_resource_destroy(resource);
            return null;
        };
        const data = self.allocator.create(ResourceData) catch {
            self.engine.resourceDestroy(resource_id);
            wls.c.wl_client_post_no_memory(client);
            wls.c.wl_resource_destroy(resource);
            return null;
        };
        data.* = .{
            .server = self,
            .client_id = client_id,
            .resource_id = resource_id,
            .wl_resource = resource,
            .kind = kind,
            .upstream_proxy = upstream_proxy,
        };
        wls.c.wl_resource_set_implementation(resource, implementation, data, runtime_helpers.resourceDestroyCallback);
        return resource;
    }

    pub fn embedAttach(
        self: *Server,
        handle: *ClientHandle,
        parent_surface: *wlp.wl_surface,
        child_surface: *wlp.wl_surface,
    ) bool {
        if (handle.server != self) return false;
        if (self.activeEmbedForClient(handle.client_id) != null) return false;
        const subcompositor = self.host.getSubcompositor() orelse return false;

        const child_resource_id = self.engine.resourceForUpstreamProxy(@ptrCast(child_surface)) orelse return false;
        const child_surface_id = self.engine.surfaceForResource(child_resource_id) orelse return false;

        const parent_resource_id = self.engine.resourceCreate(
            handle.client_id,
            .surface,
            null,
            @ptrCast(parent_surface),
        ) catch return false;
        const parent_surface_id = @import("engine/surface.zig").surfaceCreate(
            &self.engine.model,
            handle.client_id,
            parent_resource_id,
        ) catch return false;

        const subsurface = wlc.c.wl_subcompositor_get_subsurface(subcompositor, child_surface, parent_surface) orelse return false;
        const subsurface_resource_id = self.engine.resourceCreate(
            handle.client_id,
            .subsurface,
            null,
            @ptrCast(subsurface),
        ) catch return false;

        const embed_id = self.engine.embedCreate(handle.client_id, parent_surface_id) catch return false;
        self.engine.embedAttachChild(embed_id, child_surface_id) catch return false;
        self.engine.embedSetSubsurfaceResource(embed_id, subsurface_resource_id) catch return false;
        self.applyEmbedOffset(handle, embed_id);
        return true;
    }

    pub fn embedResize(self: *Server, handle: *ClientHandle, width: i32, height: i32) bool {
        if (handle.server != self) return false;
        const embed_id = self.activeEmbedForClient(handle.client_id) orelse return false;
        self.engine.embedResize(embed_id, width, height) catch return false;
        self.applyEmbedOffset(handle, embed_id);
        return true;
    }

    fn activeEmbedForClient(self: *Server, client_id: types.ClientId) ?types.EmbedId {
        for (self.engine.model.embeds.items()) |embed| {
            if (embed.client_id == client_id and embed.state != .destroyed) return embed.id;
        }
        return null;
    }

    fn applyEmbedOffset(self: *Server, handle: *ClientHandle, embed_id: types.EmbedId) void {
        const embed = self.engine.model.embeds.get(embed_id) orelse return;
        const subsurface_proxy = self.engine.upstreamProxyForResource(embed.subsurface_resource_id) orelse return;
        const child = self.surfaceForModelId(embed.plugin_child_surface_id) orelse return;
        const parent = self.surfaceForModelId(embed.host_parent_surface_id) orelse return;
        var x: i32 = 0;
        var y: i32 = 0;
        if (handle.display) |display| {
            _ = self.host.getSubsurfaceOffset(&x, &y, display, parent, child);
        }
        wlc.c.wl_subsurface_set_position(@ptrCast(subsurface_proxy), x, y);
    }

    fn surfaceForModelId(self: *Server, surface_id: types.SurfaceId) ?*wlp.wl_surface {
        const surface = self.engine.model.surfaces.get(surface_id) orelse return null;
        const proxy = self.engine.upstreamProxyForResource(surface.resource_id) orelse return null;
        return @ptrCast(proxy);
    }
};

fn opaqueClient(handle: ?*ClientHandle) ?*c_api.wayplug_client {
    return if (handle) |h| @ptrCast(h) else null;
}

const runtime_helpers = protocol_runtime.Helpers(Server, ResourceData);
const registry_bindings = protocol_registry.Bindings(Server, ResourceData);

// ===== production code above =====

const ProtocolErrorTestState = struct {
    client: ?*c_api.wayplug_client = null,
    code: u32 = 0,
    calls: u32 = 0,
};

const RegistryTestState = struct {
    compositor_enabled: bool = false,
    subcompositor_enabled: bool = false,
    shm_enabled: bool = false,
};

fn fakeCompositor(userdata: ?*anyopaque) callconv(.c) ?*wlp.wl_compositor {
    const state: *RegistryTestState = @ptrCast(@alignCast(userdata.?));
    if (!state.compositor_enabled) return null;
    return @ptrFromInt(0x1000);
}

fn fakeSubcompositor(userdata: ?*anyopaque) callconv(.c) ?*wlp.wl_subcompositor {
    const state: *RegistryTestState = @ptrCast(@alignCast(userdata.?));
    if (!state.subcompositor_enabled) return null;
    return @ptrFromInt(0x2000);
}

fn fakeShm(userdata: ?*anyopaque) callconv(.c) ?*wlp.wl_shm {
    const state: *RegistryTestState = @ptrCast(@alignCast(userdata.?));
    if (!state.shm_enabled) return null;
    return @ptrFromInt(0x3000);
}

fn testHostInterface(userdata: ?*anyopaque) c_api.WayplugHostInterface {
    return .{
        .size = @sizeOf(c_api.WayplugHostInterface),
        .version = c_api.abi_version,
        .userdata = userdata,
        .get_compositor = fakeCompositor,
        .get_subcompositor = fakeSubcompositor,
        .get_shm = fakeShm,
        .get_seat = null,
        .get_xdg_wm_base = null,
        .get_dmabuf = null,
        .get_subsurface_offset = null,
        .on_client_connected = null,
        .on_surface_created = null,
        .on_client_closed = null,
        .on_protocol_error = null,
    };
}

fn recordProtocolError(
    userdata: ?*anyopaque,
    client: ?*c_api.wayplug_client,
    code: u32,
) callconv(.c) void {
    const state: *ProtocolErrorTestState = @ptrCast(@alignCast(userdata.?));
    state.client = client;
    state.code = code;
    state.calls += 1;
}

test "Server create and destroy is balanced" {
    const iface = c_api.WayplugHostInterface{
        .size = @sizeOf(c_api.WayplugHostInterface),
        .version = c_api.abi_version,
        .userdata = null,
        .get_compositor = null,
        .get_subcompositor = null,
        .get_shm = null,
        .get_seat = null,
        .get_xdg_wm_base = null,
        .get_dmabuf = null,
        .get_subsurface_offset = null,
        .on_client_connected = null,
        .on_surface_created = null,
        .on_client_closed = null,
        .on_protocol_error = null,
    };
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();
    try std.testing.expect(s.getFd() >= 0);
}

test "protocol_error effect drains to host callback" {
    var state = ProtocolErrorTestState{};
    const iface = c_api.WayplugHostInterface{
        .size = @sizeOf(c_api.WayplugHostInterface),
        .version = c_api.abi_version,
        .userdata = &state,
        .get_compositor = null,
        .get_subcompositor = null,
        .get_shm = null,
        .get_seat = null,
        .get_xdg_wm_base = null,
        .get_dmabuf = null,
        .get_subsurface_offset = null,
        .on_client_connected = null,
        .on_surface_created = null,
        .on_client_closed = null,
        .on_protocol_error = recordProtocolError,
    };
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();

    _ = s.openClientDisplay() orelse return error.OpenClientDisplayFailed;
    const handle = s.client_handles.items[0];
    s.engine.effects.clear();
    try s.engine.effects.push(.{
        .protocol_error = .{
            .client_id = handle.client_id,
            .code = 77,
        },
    });

    s.dispatch();
    try std.testing.expectEqual(@as(u32, 1), state.calls);
    try std.testing.expectEqual(@as(u32, 77), state.code);
    try std.testing.expect(state.client == opaqueClient(handle));
}

test "server registers only host-supplied globals" {
    var state = RegistryTestState{ .compositor_enabled = true, .shm_enabled = true };
    const iface = testHostInterface(&state);
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();

    try std.testing.expectEqual(@as(usize, 2), s.globals.items.len);
    try std.testing.expectEqual(@as(u32, 4), wls.c.wl_global_get_version(s.globals.items[0]));
    try std.testing.expectEqual(@as(u32, 1), wls.c.wl_global_get_version(s.globals.items[1]));
}

test "invalid registry bind queues protocol error without resource" {
    var state = RegistryTestState{ .compositor_enabled = true };
    var iface = testHostInterface(&state);
    iface.userdata = &state;
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();

    _ = s.openClientDisplay() orelse return error.OpenClientDisplayFailed;
    const handle = s.client_handles.items[0];
    s.engine.effects.clear();

    registry_bindings.bindCompositor(handle.wl_client, s, 5, 2);

    try std.testing.expectEqual(@as(usize, 0), s.engine.model.resources.count());
    try std.testing.expectEqual(@as(usize, 1), s.engine.effects.count());
    const effect = s.engine.effects.pending()[0];
    try std.testing.expectEqual(@as(u32, @intCast(wls.c.WL_DISPLAY_ERROR_INVALID_METHOD)), effect.protocol_error.code);
    try std.testing.expectEqual(handle.client_id, effect.protocol_error.client_id);
}

test "missing host object at registry bind queues implementation error" {
    var state = RegistryTestState{ .compositor_enabled = true };
    var iface = testHostInterface(&state);
    iface.userdata = &state;
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();

    _ = s.openClientDisplay() orelse return error.OpenClientDisplayFailed;
    const handle = s.client_handles.items[0];
    s.engine.effects.clear();
    state.compositor_enabled = false;

    registry_bindings.bindCompositor(handle.wl_client, s, 1, 2);

    try std.testing.expectEqual(@as(usize, 0), s.engine.model.resources.count());
    try std.testing.expectEqual(@as(usize, 1), s.engine.effects.count());
    const effect = s.engine.effects.pending()[0];
    try std.testing.expectEqual(@as(u32, @intCast(wls.c.WL_DISPLAY_ERROR_IMPLEMENTATION)), effect.protocol_error.code);
    try std.testing.expectEqual(handle.client_id, effect.protocol_error.client_id);
}
