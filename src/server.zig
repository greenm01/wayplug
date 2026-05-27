//! Internal server runtime behind the opaque `wayplug_server` handle.
//! Owns the engine, the host wrapper, and the upstream event queue.

const std = @import("std");
const c_api = @import("c_api.zig");
const types = @import("data/types.zig");
const engine_mod = @import("engine/engine.zig");
const host_mod = @import("host.zig");
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

const ResourceData = struct {
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
        if (handle.display) |display| {
            wlc.c.wl_display_disconnect(display);
            handle.display = null;
        }
        if (handle.wl_client) |wl_client| {
            wls.c.wl_client_destroy(wl_client);
            handle.wl_client = null;
        }
        if (emit_effect) {
            self.engine.clientDestroy(handle.client_id) catch {};
            handle.close_pending = true;
        } else {
            @import("engine/client.zig").clientDestroy(&self.engine.model, handle.client_id);
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
            try self.registerGlobal(&wls.c.wl_compositor_interface, 4, bindCompositor);
        }
        if (self.host.getSubcompositor() != null) {
            try self.registerGlobal(&wls.c.wl_subcompositor_interface, 1, bindSubcompositor);
        }
        if (self.host.getShm() != null) {
            try self.registerGlobal(&wls.c.wl_shm_interface, 1, bindShm);
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

    fn createResource(
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
        wls.c.wl_resource_set_implementation(resource, implementation, data, resourceDestroyCallback);
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

fn serverFromData(data: ?*anyopaque) ?*Server {
    const ptr = data orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn dataForResource(resource: ?*wls.wl_resource) ?*ResourceData {
    const r = resource orelse return null;
    const ptr = wls.c.wl_resource_get_user_data(r) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn proxyAs(comptime T: type, proxy: ?*wlc.wl_proxy) ?*T {
    return if (proxy) |p| @ptrCast(p) else null;
}

fn resourceProxyAs(comptime T: type, resource: ?*wls.wl_resource) ?*T {
    const data = dataForResource(resource) orelse return null;
    return proxyAs(T, data.upstream_proxy);
}

fn resourceDestroyCallback(resource: ?*wls.wl_resource) callconv(.c) void {
    const data = dataForResource(resource) orelse return;
    data.server.engine.resourceDestroy(data.resource_id);
    data.server.allocator.destroy(data);
}

fn resourceRelease(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
    if (resource) |r| wls.c.wl_resource_destroy(r);
}

fn bindCompositor(client: ?*wls.wl_client, data: ?*anyopaque, version: u32, id: u32) callconv(.c) void {
    const server = serverFromData(data) orelse return;
    const wl_client = client orelse return;
    const compositor = server.host.getCompositor() orelse return;
    _ = server.createResource(
        wl_client,
        .compositor,
        &wls.c.wl_compositor_interface,
        @min(version, 4),
        id,
        @ptrCast(&compositor_impl),
        @ptrCast(compositor),
    );
}

fn bindSubcompositor(client: ?*wls.wl_client, data: ?*anyopaque, version: u32, id: u32) callconv(.c) void {
    const server = serverFromData(data) orelse return;
    const wl_client = client orelse return;
    const subcompositor = server.host.getSubcompositor() orelse return;
    _ = server.createResource(
        wl_client,
        .subcompositor,
        &wls.c.wl_subcompositor_interface,
        @min(version, 1),
        id,
        @ptrCast(&subcompositor_impl),
        @ptrCast(subcompositor),
    );
}

fn bindShm(client: ?*wls.wl_client, data: ?*anyopaque, version: u32, id: u32) callconv(.c) void {
    const server = serverFromData(data) orelse return;
    const wl_client = client orelse return;
    const shm = server.host.getShm() orelse return;
    const resource = server.createResource(
        wl_client,
        .shm,
        &wls.c.wl_shm_interface,
        @min(version, 1),
        id,
        @ptrCast(&shm_impl),
        @ptrCast(shm),
    ) orelse return;
    wls.c.wl_shm_send_format(resource, wls.c.WL_SHM_FORMAT_ARGB8888);
    wls.c.wl_shm_send_format(resource, wls.c.WL_SHM_FORMAT_XRGB8888);
}

const compositor_impl = wls.c.struct_wl_compositor_interface{
    .create_surface = compositorCreateSurface,
    .create_region = compositorCreateRegion,
    .release = resourceRelease,
};

fn compositorCreateSurface(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32) callconv(.c) void {
    const data = dataForResource(resource) orelse return;
    const compositor = resourceProxyAs(wlp.wl_compositor, resource) orelse return;
    const surface = wlc.c.wl_compositor_create_surface(compositor) orelse return;
    const wl_client = client orelse return;
    const surface_resource = data.server.createResource(
        wl_client,
        .surface,
        &wls.c.wl_surface_interface,
        4,
        id,
        @ptrCast(&surface_impl),
        @ptrCast(surface),
    ) orelse return;
    const surface_data = dataForResource(surface_resource) orelse return;
    _ = data.server.engine.surfaceCreate(data.client_id, surface_data.resource_id) catch {
        wls.c.wl_resource_destroy(surface_resource);
        return;
    };
}

fn compositorCreateRegion(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32) callconv(.c) void {
    const server_data = dataForResource(resource) orelse return;
    const compositor = resourceProxyAs(wlp.wl_compositor, resource) orelse return;
    const region = wlc.c.wl_compositor_create_region(compositor) orelse return;
    const wl_client = client orelse return;
    _ = server_data.server.createResource(
        wl_client,
        .region,
        &wls.c.wl_region_interface,
        1,
        id,
        @ptrCast(&region_impl),
        @ptrCast(region),
    );
}

const surface_impl = wls.c.struct_wl_surface_interface{
    .destroy = surfaceDestroy,
    .attach = surfaceAttach,
    .damage = surfaceDamage,
    .frame = surfaceFrame,
    .set_opaque_region = surfaceSetOpaqueRegion,
    .set_input_region = surfaceSetInputRegion,
    .commit = surfaceCommit,
    .set_buffer_transform = surfaceSetBufferTransform,
    .set_buffer_scale = surfaceSetBufferScale,
    .damage_buffer = surfaceDamageBuffer,
    .offset = null,
    .get_release = null,
};

fn surfaceDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
    if (dataForResource(resource)) |data| {
        if (proxyAs(wlp.wl_surface, data.upstream_proxy)) |surface| {
            wlc.c.wl_surface_destroy(surface);
            data.upstream_proxy = null;
        }
    }
    resourceRelease(null, resource);
}

fn surfaceAttach(_: ?*wls.wl_client, resource: ?*wls.wl_resource, buffer: ?*wls.wl_resource, x: i32, y: i32) callconv(.c) void {
    const surface = resourceProxyAs(wlp.wl_surface, resource) orelse return;
    const upstream_buffer = resourceProxyAs(wlp.wl_buffer, buffer);
    wlc.c.wl_surface_attach(surface, upstream_buffer, x, y);
}

fn surfaceDamage(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
    const surface = resourceProxyAs(wlp.wl_surface, resource) orelse return;
    wlc.c.wl_surface_damage(surface, x, y, width, height);
}

fn surfaceFrame(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32) callconv(.c) void {
    const data = dataForResource(resource) orelse return;
    const surface = resourceProxyAs(wlp.wl_surface, resource) orelse return;
    const callback = wlc.c.wl_surface_frame(surface) orelse return;
    const wl_client = client orelse return;
    const callback_resource = data.server.createResource(
        wl_client,
        .callback,
        &wls.c.wl_callback_interface,
        1,
        id,
        null,
        @ptrCast(callback),
    ) orelse return;
    const callback_data = dataForResource(callback_resource) orelse return;
    _ = wlc.c.wl_callback_add_listener(callback, &callback_listener, callback_data);
}

fn surfaceSetOpaqueRegion(_: ?*wls.wl_client, resource: ?*wls.wl_resource, region: ?*wls.wl_resource) callconv(.c) void {
    const surface = resourceProxyAs(wlp.wl_surface, resource) orelse return;
    wlc.c.wl_surface_set_opaque_region(surface, resourceProxyAs(wlp.wl_region, region));
}

fn surfaceSetInputRegion(_: ?*wls.wl_client, resource: ?*wls.wl_resource, region: ?*wls.wl_resource) callconv(.c) void {
    const surface = resourceProxyAs(wlp.wl_surface, resource) orelse return;
    wlc.c.wl_surface_set_input_region(surface, resourceProxyAs(wlp.wl_region, region));
}

fn surfaceCommit(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
    const surface = resourceProxyAs(wlp.wl_surface, resource) orelse return;
    wlc.c.wl_surface_commit(surface);
}

fn surfaceSetBufferTransform(_: ?*wls.wl_client, resource: ?*wls.wl_resource, transform: i32) callconv(.c) void {
    const surface = resourceProxyAs(wlp.wl_surface, resource) orelse return;
    wlc.c.wl_surface_set_buffer_transform(surface, transform);
}

fn surfaceSetBufferScale(_: ?*wls.wl_client, resource: ?*wls.wl_resource, scale: i32) callconv(.c) void {
    const surface = resourceProxyAs(wlp.wl_surface, resource) orelse return;
    wlc.c.wl_surface_set_buffer_scale(surface, scale);
}

fn surfaceDamageBuffer(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
    const surface = resourceProxyAs(wlp.wl_surface, resource) orelse return;
    wlc.c.wl_surface_damage_buffer(surface, x, y, width, height);
}

const region_impl = wls.c.struct_wl_region_interface{
    .destroy = regionDestroy,
    .add = regionAdd,
    .subtract = regionSubtract,
};

fn regionDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
    if (dataForResource(resource)) |data| {
        if (proxyAs(wlp.wl_region, data.upstream_proxy)) |region| {
            wlc.c.wl_region_destroy(region);
            data.upstream_proxy = null;
        }
    }
    resourceRelease(null, resource);
}

fn regionAdd(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
    const region = resourceProxyAs(wlp.wl_region, resource) orelse return;
    wlc.c.wl_region_add(region, x, y, width, height);
}

fn regionSubtract(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
    const region = resourceProxyAs(wlp.wl_region, resource) orelse return;
    wlc.c.wl_region_subtract(region, x, y, width, height);
}

const shm_impl = wls.c.struct_wl_shm_interface{
    .create_pool = shmCreatePool,
    .release = resourceRelease,
};

fn shmCreatePool(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32, fd: i32, size: i32) callconv(.c) void {
    const data = dataForResource(resource) orelse {
        _ = sys.close(fd);
        return;
    };
    const shm = resourceProxyAs(wlp.wl_shm, resource) orelse {
        _ = sys.close(fd);
        return;
    };
    const pool = wlc.c.wl_shm_create_pool(shm, fd, size) orelse {
        _ = sys.close(fd);
        return;
    };
    _ = sys.close(fd);
    const wl_client = client orelse return;
    _ = data.server.createResource(
        wl_client,
        .shm_pool,
        &wls.c.wl_shm_pool_interface,
        1,
        id,
        @ptrCast(&shm_pool_impl),
        @ptrCast(pool),
    );
}

const shm_pool_impl = wls.c.struct_wl_shm_pool_interface{
    .create_buffer = shmPoolCreateBuffer,
    .destroy = shmPoolDestroy,
    .resize = shmPoolResize,
};

fn shmPoolCreateBuffer(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32, offset: i32, width: i32, height: i32, stride: i32, format: u32) callconv(.c) void {
    const data = dataForResource(resource) orelse return;
    const pool = resourceProxyAs(wlp.wl_shm_pool, resource) orelse return;
    const buffer = wlc.c.wl_shm_pool_create_buffer(pool, offset, width, height, stride, format) orelse return;
    const wl_client = client orelse return;
    const buffer_resource = data.server.createResource(
        wl_client,
        .buffer,
        &wls.c.wl_buffer_interface,
        1,
        id,
        @ptrCast(&buffer_impl),
        @ptrCast(buffer),
    ) orelse return;
    const buffer_data = dataForResource(buffer_resource) orelse return;
    _ = wlc.c.wl_buffer_add_listener(buffer, &buffer_listener, buffer_data);
}

fn shmPoolDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
    if (dataForResource(resource)) |data| {
        if (proxyAs(wlp.wl_shm_pool, data.upstream_proxy)) |pool| {
            wlc.c.wl_shm_pool_destroy(pool);
            data.upstream_proxy = null;
        }
    }
    resourceRelease(null, resource);
}

fn shmPoolResize(_: ?*wls.wl_client, resource: ?*wls.wl_resource, size: i32) callconv(.c) void {
    const pool = resourceProxyAs(wlp.wl_shm_pool, resource) orelse return;
    wlc.c.wl_shm_pool_resize(pool, size);
}

const buffer_impl = wls.c.struct_wl_buffer_interface{ .destroy = bufferDestroy };

fn bufferDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
    if (dataForResource(resource)) |data| {
        if (proxyAs(wlp.wl_buffer, data.upstream_proxy)) |buffer| {
            wlc.c.wl_buffer_destroy(buffer);
            data.upstream_proxy = null;
        }
    }
    resourceRelease(null, resource);
}

const callback_listener = wlc.c.struct_wl_callback_listener{ .done = callbackDone };

fn callbackDone(data: ?*anyopaque, _: ?*wlp.wl_callback, callback_data: u32) callconv(.c) void {
    const resource_data: *ResourceData = @ptrCast(@alignCast(data orelse return));
    wls.c.wl_callback_send_done(resource_data.wl_resource, callback_data);
    wls.c.wl_resource_destroy(resource_data.wl_resource);
}

const buffer_listener = wlc.c.struct_wl_buffer_listener{ .release = bufferRelease };

fn bufferRelease(data: ?*anyopaque, _: ?*wlp.wl_buffer) callconv(.c) void {
    const resource_data: *ResourceData = @ptrCast(@alignCast(data orelse return));
    wls.c.wl_buffer_send_release(resource_data.wl_resource);
}

const subcompositor_impl = wls.c.struct_wl_subcompositor_interface{
    .destroy = resourceRelease,
    .get_subsurface = subcompositorGetSubsurface,
};

fn subcompositorGetSubsurface(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32, surface_resource: ?*wls.wl_resource, parent_resource: ?*wls.wl_resource) callconv(.c) void {
    const data = dataForResource(resource) orelse return;
    const subcompositor = resourceProxyAs(wlp.wl_subcompositor, resource) orelse return;
    const surface = resourceProxyAs(wlp.wl_surface, surface_resource) orelse return;
    const parent = resourceProxyAs(wlp.wl_surface, parent_resource) orelse return;
    const subsurface = wlc.c.wl_subcompositor_get_subsurface(subcompositor, surface, parent) orelse return;
    const wl_client = client orelse return;
    _ = data.server.createResource(
        wl_client,
        .subsurface,
        &wls.c.wl_subsurface_interface,
        1,
        id,
        @ptrCast(&subsurface_impl),
        @ptrCast(subsurface),
    );
}

const subsurface_impl = wls.c.struct_wl_subsurface_interface{
    .destroy = subsurfaceDestroy,
    .set_position = subsurfaceSetPosition,
    .place_above = subsurfacePlaceAbove,
    .place_below = subsurfacePlaceBelow,
    .set_sync = subsurfaceSetSync,
    .set_desync = subsurfaceSetDesync,
};

fn subsurfaceDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
    if (dataForResource(resource)) |data| {
        if (proxyAs(wlp.wl_subsurface, data.upstream_proxy)) |subsurface| {
            wlc.c.wl_subsurface_destroy(subsurface);
            data.upstream_proxy = null;
        }
    }
    resourceRelease(null, resource);
}

fn subsurfaceSetPosition(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32) callconv(.c) void {
    const subsurface = resourceProxyAs(wlp.wl_subsurface, resource) orelse return;
    wlc.c.wl_subsurface_set_position(subsurface, x, y);
}

fn subsurfacePlaceAbove(_: ?*wls.wl_client, resource: ?*wls.wl_resource, sibling_resource: ?*wls.wl_resource) callconv(.c) void {
    const subsurface = resourceProxyAs(wlp.wl_subsurface, resource) orelse return;
    const sibling = resourceProxyAs(wlp.wl_surface, sibling_resource) orelse return;
    wlc.c.wl_subsurface_place_above(subsurface, sibling);
}

fn subsurfacePlaceBelow(_: ?*wls.wl_client, resource: ?*wls.wl_resource, sibling_resource: ?*wls.wl_resource) callconv(.c) void {
    const subsurface = resourceProxyAs(wlp.wl_subsurface, resource) orelse return;
    const sibling = resourceProxyAs(wlp.wl_surface, sibling_resource) orelse return;
    wlc.c.wl_subsurface_place_below(subsurface, sibling);
}

fn subsurfaceSetSync(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
    const subsurface = resourceProxyAs(wlp.wl_subsurface, resource) orelse return;
    wlc.c.wl_subsurface_set_sync(subsurface);
}

fn subsurfaceSetDesync(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
    const subsurface = resourceProxyAs(wlp.wl_subsurface, resource) orelse return;
    wlc.c.wl_subsurface_set_desync(subsurface);
}

// ===== production code above =====

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
    };
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();
    try std.testing.expect(s.getFd() >= 0);
}
