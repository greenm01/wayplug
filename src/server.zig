//! Internal server runtime behind the opaque `wayembed_server` handle.
//! Owns the engine, the host wrapper, and the upstream event queue.

const std = @import("std");
const c_api = @import("c_api.zig");
const snapshot_mod = @import("data/snapshot.zig");
const types = @import("data/types.zig");
const engine_embed = @import("engine/embed.zig");
const engine_mod = @import("engine/engine.zig");
const engine_surface = @import("engine/surface.zig");
const host_mod = @import("host.zig");
const protocol_registry = @import("protocol/registry.zig");
const protocol_runtime = @import("protocol/runtime.zig");
const wlc = @import("wayland/client.zig");
const wlp = @import("wayland/protocols.zig");
const wls = @import("wayland/server.zig");
const xdgc = @import("wayland/xdg_client.zig");
const xdgs = @import("wayland/xdg_server.zig");

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
    pointer_focus_surface: ?*wls.wl_resource = null,
    pointer_focus_upstream_surface: ?*wlp.wl_surface = null,
    touch_points: std.AutoArrayHashMapUnmanaged(i32, *wlp.wl_surface) = .empty,
    xdg_wm_base_resource: ?*wls.wl_resource = null,
    xdg_surface_id: ?types.SurfaceId = null,

    pub fn deinit(self: *ResourceData, allocator: std.mem.Allocator) void {
        self.touch_points.deinit(allocator);
    }
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    engine: engine_mod.Engine,
    host_iface: c_api.WayembedHostInterface,
    host: host_mod.Host,
    display: *wls.wl_display,
    event_loop: *wls.wl_event_loop,
    queue: ?*wlc.wl_event_queue,
    client_handles: std.ArrayListUnmanaged(*ClientHandle) = .empty,
    globals: std.ArrayListUnmanaged(*wls.wl_global) = .empty,

    pub fn create(
        allocator: std.mem.Allocator,
        iface: *const c_api.WayembedHostInterface,
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
        self.releaseClientOwnedUpstreams(handle.client_id);
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
        var pending = self.engine.effects.takePending();
        defer pending.deinit(self.engine.effects.allocator);

        for (pending.items) |effect| {
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
                .embed_mapped => |embed_id| {
                    self.host.onEmbedMapped(embedIdInt(embed_id));
                },
                .embed_resized => |resized| {
                    self.host.onEmbedResized(embedIdInt(resized.embed_id), resized.width, resized.height);
                },
                .embed_destroyed => |embed_id| {
                    self.host.onEmbedDestroyed(embedIdInt(embed_id));
                },
                else => {},
            }
        }
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
        if (self.host.getSeat() != null) {
            try self.registerGlobal(&wls.c.wl_seat_interface, 4, registry_bindings.bindSeat);
        }
        if (self.host.getOutputInfo() != null) {
            try self.registerGlobal(&wls.c.wl_output_interface, 4, registry_bindings.bindOutput);
        }
        if (self.host.getXdgWmBase() != null) {
            try self.registerGlobal(&xdgs.c.xdg_wm_base_interface, 7, registry_bindings.bindXdgWmBase);
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
        if (handle.close_pending) return false;
        if (self.activeEmbedForClient(handle.client_id) != null) return false;
        const subcompositor = self.host.getSubcompositor() orelse return false;

        const child_resource_id = self.engine.resourceForUpstreamProxy(@ptrCast(child_surface)) orelse return false;
        const child_surface_id = self.engine.surfaceForResource(child_resource_id) orelse return false;
        const child_role = self.engine.surfaceRole(child_surface_id) orelse return false;
        if (child_role != .none) return false;

        var parent_resource_id: ?types.ResourceId = null;
        var parent_surface_id: ?types.SurfaceId = null;
        var subsurface: ?*wlp.wl_subsurface = null;
        var subsurface_resource_id: ?types.ResourceId = null;
        var embed_id: ?types.EmbedId = null;
        var success = false;
        defer if (!success) {
            self.rollbackEmbedAttach(
                parent_resource_id,
                parent_surface_id,
                subsurface,
                subsurface_resource_id,
                embed_id,
            );
        };

        parent_resource_id = self.engine.resourceCreate(
            handle.client_id,
            .surface,
            null,
            @ptrCast(parent_surface),
        ) catch return false;
        parent_surface_id = engine_surface.surfaceCreate(
            &self.engine.model,
            handle.client_id,
            parent_resource_id.?,
        ) catch return false;

        subsurface = wlc.c.wl_subcompositor_get_subsurface(subcompositor, child_surface, parent_surface) orelse return false;
        subsurface_resource_id = self.engine.resourceCreate(
            handle.client_id,
            .subsurface,
            null,
            @ptrCast(subsurface.?),
        ) catch return false;

        embed_id = self.engine.embedCreate(handle.client_id, parent_surface_id.?) catch return false;
        self.engine.embedAttachChild(embed_id.?, child_surface_id) catch return false;
        self.engine.embedSetSubsurfaceResource(embed_id.?, subsurface_resource_id.?) catch return false;
        self.engine.surfaceAssignRole(child_surface_id, .subsurface) catch return false;
        self.applyEmbedOffset(handle, embed_id.?);
        self.engine.embedMap(embed_id.?) catch return false;
        success = true;
        return true;
    }

    pub fn embedResize(self: *Server, handle: *ClientHandle, width: i32, height: i32) bool {
        if (handle.server != self) return false;
        if (handle.close_pending) return false;
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

    fn rollbackEmbedAttach(
        self: *Server,
        parent_resource_id: ?types.ResourceId,
        parent_surface_id: ?types.SurfaceId,
        subsurface: ?*wlp.wl_subsurface,
        subsurface_resource_id: ?types.ResourceId,
        embed_id: ?types.EmbedId,
    ) void {
        if (embed_id) |id| engine_embed.embedDestroy(&self.engine.model, id);
        if (subsurface_resource_id) |resource_id| {
            if (self.engine.upstreamProxyForResource(resource_id)) |proxy| {
                wlc.c.wl_subsurface_destroy(@ptrCast(proxy));
            }
            self.engine.resourceDestroy(resource_id);
        } else if (subsurface) |proxy| {
            wlc.c.wl_subsurface_destroy(proxy);
        }
        if (parent_surface_id) |surface_id| engine_surface.surfaceDestroy(&self.engine.model, surface_id);
        if (parent_resource_id) |resource_id| self.engine.resourceDestroy(resource_id);
    }

    fn releaseClientOwnedUpstreams(self: *Server, client_id: types.ClientId) void {
        // Release role/helper objects before their parent surfaces so queued
        // upstream events cannot target freed ResourceData during teardown.
        const release_order = [_]types.ResourceKind{
            .subsurface,
            .xdg_popup,
            .xdg_toplevel,
            .xdg_surface,
            .xdg_positioner,
            .pointer,
            .keyboard,
            .touch,
            .buffer,
            .shm_pool,
            .callback,
            .region,
            .surface,
        };
        for (release_order) |kind| {
            for (self.engine.model.resources.items()) |resource| {
                if (resource.client_id == client_id and resource.kind == kind) {
                    self.releaseOwnedUpstreamProxy(resource);
                }
            }
        }
    }

    fn releaseOwnedUpstreamProxy(self: *Server, resource: types.Resource) void {
        _ = self;
        const proxy = resource.upstream_proxy orelse return;
        switch (resource.kind) {
            .compositor,
            .subcompositor,
            .shm,
            .seat,
            .output,
            .xdg_wm_base,
            .registry,
            .other,
            => {},

            .surface => {
                if (resource.wl_resource != null) wlc.c.wl_surface_destroy(@ptrCast(proxy));
            },
            .subsurface => wlc.c.wl_subsurface_destroy(@ptrCast(proxy)),
            .region => wlc.c.wl_region_destroy(@ptrCast(proxy)),
            .shm_pool => wlc.c.wl_shm_pool_destroy(@ptrCast(proxy)),
            .buffer => wlc.c.wl_buffer_destroy(@ptrCast(proxy)),
            .callback => wlc.c.wl_callback_destroy(@ptrCast(proxy)),
            .pointer => wlc.c.wl_pointer_destroy(@ptrCast(proxy)),
            .keyboard => wlc.c.wl_keyboard_destroy(@ptrCast(proxy)),
            .touch => wlc.c.wl_touch_destroy(@ptrCast(proxy)),
            .xdg_positioner => xdgc.c.xdg_positioner_destroy(@ptrCast(proxy)),
            .xdg_surface => xdgc.c.xdg_surface_destroy(@ptrCast(proxy)),
            .xdg_toplevel => xdgc.c.xdg_toplevel_destroy(@ptrCast(proxy)),
            .xdg_popup => xdgc.c.xdg_popup_destroy(@ptrCast(proxy)),
        }
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

    pub fn surfaceResourceForUpstreamSurface(self: *Server, surface: *wlp.wl_surface) ?*wls.wl_resource {
        const resource_id = self.engine.resourceForUpstreamProxy(@ptrCast(surface)) orelse return null;
        const resource = self.engine.model.resources.get(resource_id) orelse return null;
        return resource.wl_resource;
    }

    pub const PointerCoords = struct {
        x: wls.c.wl_fixed_t,
        y: wls.c.wl_fixed_t,
    };

    pub fn translatePointerCoords(
        self: *Server,
        client_id: types.ClientId,
        upstream_surface: *wlp.wl_surface,
        x: wls.c.wl_fixed_t,
        y: wls.c.wl_fixed_t,
    ) PointerCoords {
        var translated: PointerCoords = .{ .x = x, .y = y };
        const child_resource_id = self.engine.resourceForUpstreamProxy(@ptrCast(upstream_surface)) orelse return translated;
        const child_surface_id = self.engine.surfaceForResource(child_resource_id) orelse return translated;
        const embed_id = self.engine.model.embed_by_child_surface.get(child_surface_id) orelse return translated;
        const embed = self.engine.model.embeds.get(embed_id) orelse return translated;
        const handle = self.findClientHandleById(client_id) orelse return translated;
        const display = handle.display orelse return translated;
        const parent = self.surfaceForModelId(embed.host_parent_surface_id) orelse return translated;
        const child = self.surfaceForModelId(embed.plugin_child_surface_id) orelse return translated;

        var offset_x: i32 = 0;
        var offset_y: i32 = 0;
        if (!self.host.getSubsurfaceOffset(&offset_x, &offset_y, display, parent, child)) return translated;
        translated.x -= wlc.c.wl_fixed_from_int(offset_x);
        translated.y -= wlc.c.wl_fixed_from_int(offset_y);
        return translated;
    }
};

fn opaqueClient(handle: ?*ClientHandle) ?*c_api.wayembed_client {
    return if (handle) |h| @ptrCast(h) else null;
}

fn embedIdInt(embed_id: types.EmbedId) u32 {
    return @intFromEnum(embed_id);
}

const runtime_helpers = protocol_runtime.Helpers(Server, ResourceData);
const registry_bindings = protocol_registry.Bindings(Server, ResourceData);

// ===== production code above =====

const ProtocolErrorTestState = struct {
    client: ?*c_api.wayembed_client = null,
    code: u32 = 0,
    calls: u32 = 0,
};

const EmbedCallbackTestState = struct {
    mapped_id: u32 = 0,
    resized_id: u32 = 0,
    destroyed_id: u32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    mapped_calls: u32 = 0,
    resized_calls: u32 = 0,
    destroyed_calls: u32 = 0,
};

const RegistryTestState = struct {
    compositor_enabled: bool = false,
    subcompositor_enabled: bool = false,
    shm_enabled: bool = false,
    seat_enabled: bool = false,
    xdg_wm_base_enabled: bool = false,
    output_enabled: bool = false,
    seat_capabilities: u32 = host_mod.default_seat_capabilities,
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

fn fakeSeat(userdata: ?*anyopaque) callconv(.c) ?*wlp.wl_seat {
    const state: *RegistryTestState = @ptrCast(@alignCast(userdata.?));
    if (!state.seat_enabled) return null;
    return @ptrFromInt(0x4000);
}

fn fakeSeatCapabilities(userdata: ?*anyopaque) callconv(.c) u32 {
    const state: *RegistryTestState = @ptrCast(@alignCast(userdata.?));
    return state.seat_capabilities;
}

fn fakeXdgWmBase(userdata: ?*anyopaque) callconv(.c) ?*wlp.xdg_wm_base {
    const state: *RegistryTestState = @ptrCast(@alignCast(userdata.?));
    if (!state.xdg_wm_base_enabled) return null;
    return @ptrFromInt(0x5000);
}

fn fakeOutputInfo(userdata: ?*anyopaque, info: *c_api.WayembedOutputInfo) callconv(.c) bool {
    const state: *RegistryTestState = @ptrCast(@alignCast(userdata.?));
    if (!state.output_enabled) return false;
    info.mode_width = 800;
    info.mode_height = 600;
    info.scale = 2;
    return true;
}

fn fakeSubsurfaceOffset(
    _: ?*anyopaque,
    x: *i32,
    y: *i32,
    _: *wlc.wl_display,
    _: *wlp.wl_surface,
    _: *wlp.wl_surface,
) callconv(.c) bool {
    x.* = 3;
    y.* = 4;
    return true;
}

fn testHostInterface(userdata: ?*anyopaque) c_api.WayembedHostInterface {
    return .{
        .size = @sizeOf(c_api.WayembedHostInterface),
        .version = c_api.abi_version,
        .userdata = userdata,
        .get_compositor = fakeCompositor,
        .get_subcompositor = fakeSubcompositor,
        .get_shm = fakeShm,
        .get_seat = fakeSeat,
        .get_xdg_wm_base = fakeXdgWmBase,
        .get_dmabuf = null,
        .get_seat_capabilities = fakeSeatCapabilities,
        .get_seat_name = null,
        .get_output_info = fakeOutputInfo,
        .get_subsurface_offset = null,
        .on_client_connected = null,
        .on_surface_created = null,
        .on_client_closed = null,
        .on_protocol_error = null,
        .on_embed_mapped = null,
        .on_embed_resized = null,
        .on_embed_destroyed = null,
    };
}

fn recordProtocolError(
    userdata: ?*anyopaque,
    client: ?*c_api.wayembed_client,
    code: u32,
) callconv(.c) void {
    const state: *ProtocolErrorTestState = @ptrCast(@alignCast(userdata.?));
    state.client = client;
    state.code = code;
    state.calls += 1;
}

fn recordEmbedMapped(userdata: ?*anyopaque, embed_id: u32) callconv(.c) void {
    const state: *EmbedCallbackTestState = @ptrCast(@alignCast(userdata.?));
    state.mapped_id = embed_id;
    state.mapped_calls += 1;
}

fn recordEmbedResized(
    userdata: ?*anyopaque,
    embed_id: u32,
    width: i32,
    height: i32,
) callconv(.c) void {
    const state: *EmbedCallbackTestState = @ptrCast(@alignCast(userdata.?));
    state.resized_id = embed_id;
    state.width = width;
    state.height = height;
    state.resized_calls += 1;
}

fn recordEmbedDestroyed(userdata: ?*anyopaque, embed_id: u32) callconv(.c) void {
    const state: *EmbedCallbackTestState = @ptrCast(@alignCast(userdata.?));
    state.destroyed_id = embed_id;
    state.destroyed_calls += 1;
}

fn fakeClientDisplay(comptime address: usize) *wlc.wl_display {
    return @ptrFromInt(address);
}

fn fakeSurface(comptime address: usize) *wlp.wl_surface {
    return @ptrFromInt(address);
}

test "Server create and destroy is balanced" {
    const iface = c_api.WayembedHostInterface{
        .size = @sizeOf(c_api.WayembedHostInterface),
        .version = c_api.abi_version,
        .userdata = null,
        .get_compositor = null,
        .get_subcompositor = null,
        .get_shm = null,
        .get_seat = null,
        .get_xdg_wm_base = null,
        .get_dmabuf = null,
        .get_seat_capabilities = null,
        .get_seat_name = null,
        .get_output_info = null,
        .get_subsurface_offset = null,
        .on_client_connected = null,
        .on_surface_created = null,
        .on_client_closed = null,
        .on_protocol_error = null,
        .on_embed_mapped = null,
        .on_embed_resized = null,
        .on_embed_destroyed = null,
    };
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();
    try std.testing.expect(s.getFd() >= 0);
}

test "protocol_error effect drains to host callback" {
    var state = ProtocolErrorTestState{};
    const iface = c_api.WayembedHostInterface{
        .size = @sizeOf(c_api.WayembedHostInterface),
        .version = c_api.abi_version,
        .userdata = &state,
        .get_compositor = null,
        .get_subcompositor = null,
        .get_shm = null,
        .get_seat = null,
        .get_xdg_wm_base = null,
        .get_dmabuf = null,
        .get_seat_capabilities = null,
        .get_seat_name = null,
        .get_output_info = null,
        .get_subsurface_offset = null,
        .on_client_connected = null,
        .on_surface_created = null,
        .on_client_closed = null,
        .on_protocol_error = recordProtocolError,
        .on_embed_mapped = null,
        .on_embed_resized = null,
        .on_embed_destroyed = null,
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

test "embedded coordinate translation subtracts host subsurface offset" {
    const iface = c_api.WayembedHostInterface{
        .size = @sizeOf(c_api.WayembedHostInterface),
        .version = c_api.abi_version,
        .userdata = null,
        .get_compositor = null,
        .get_subcompositor = null,
        .get_shm = null,
        .get_seat = null,
        .get_xdg_wm_base = null,
        .get_dmabuf = null,
        .get_seat_capabilities = null,
        .get_seat_name = null,
        .get_output_info = null,
        .get_subsurface_offset = fakeSubsurfaceOffset,
        .on_client_connected = null,
        .on_surface_created = null,
        .on_client_closed = null,
        .on_protocol_error = null,
        .on_embed_mapped = null,
        .on_embed_resized = null,
        .on_embed_destroyed = null,
    };

    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();

    const client_id = try s.engine.clientCreate(-1, -1);
    const handle = try s.allocator.create(ClientHandle);
    handle.* = .{
        .server = s,
        .client_id = client_id,
        .wl_client = null,
        .display = fakeClientDisplay(0x1000),
    };
    try s.client_handles.append(s.allocator, handle);
    defer {
        for (s.client_handles.items, 0..) |candidate, i| {
            if (candidate == handle) {
                _ = s.client_handles.swapRemove(i);
                break;
            }
        }
        s.allocator.destroy(handle);
    }

    const parent_surface = fakeSurface(0x2000);
    const child_surface = fakeSurface(0x3000);
    const parent_resource_id = try s.engine.resourceCreate(client_id, .surface, null, @ptrCast(parent_surface));
    const child_resource_id = try s.engine.resourceCreate(client_id, .surface, null, @ptrCast(child_surface));
    const parent_surface_id = try s.engine.surfaceCreate(client_id, parent_resource_id);
    const child_surface_id = try s.engine.surfaceCreate(client_id, child_resource_id);
    const embed_id = try s.engine.embedCreate(client_id, parent_surface_id);
    try s.engine.embedAttachChild(embed_id, child_surface_id);

    const translated = s.translatePointerCoords(
        client_id,
        child_surface,
        wlc.c.wl_fixed_from_int(12),
        wlc.c.wl_fixed_from_int(20),
    );

    try std.testing.expectEqual(wlc.c.wl_fixed_from_int(9), translated.x);
    try std.testing.expectEqual(wlc.c.wl_fixed_from_int(16), translated.y);
}

test "embed lifecycle effects drain to host callbacks" {
    var state = EmbedCallbackTestState{};
    const iface = c_api.WayembedHostInterface{
        .size = @sizeOf(c_api.WayembedHostInterface),
        .version = c_api.abi_version,
        .userdata = &state,
        .get_compositor = null,
        .get_subcompositor = null,
        .get_shm = null,
        .get_seat = null,
        .get_xdg_wm_base = null,
        .get_dmabuf = null,
        .get_seat_capabilities = null,
        .get_seat_name = null,
        .get_output_info = null,
        .get_subsurface_offset = null,
        .on_client_connected = null,
        .on_surface_created = null,
        .on_client_closed = null,
        .on_protocol_error = null,
        .on_embed_mapped = recordEmbedMapped,
        .on_embed_resized = recordEmbedResized,
        .on_embed_destroyed = recordEmbedDestroyed,
    };
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();

    try s.engine.effects.push(.{ .embed_mapped = @enumFromInt(9) });
    try s.engine.effects.push(.{
        .embed_resized = .{
            .embed_id = @enumFromInt(9),
            .width = 640,
            .height = 480,
        },
    });
    try s.engine.effects.push(.{ .embed_destroyed = @enumFromInt(9) });

    s.dispatch();
    try std.testing.expectEqual(@as(u32, 1), state.mapped_calls);
    try std.testing.expectEqual(@as(u32, 1), state.resized_calls);
    try std.testing.expectEqual(@as(u32, 1), state.destroyed_calls);
    try std.testing.expectEqual(@as(u32, 9), state.mapped_id);
    try std.testing.expectEqual(@as(u32, 9), state.resized_id);
    try std.testing.expectEqual(@as(u32, 9), state.destroyed_id);
    try std.testing.expectEqual(@as(i32, 640), state.width);
    try std.testing.expectEqual(@as(i32, 480), state.height);
}

test "server embed resize rejects negative sizes and closed handles" {
    var state = RegistryTestState{};
    const iface = testHostInterface(&state);
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();

    const client_id = try s.engine.clientCreate(-1, -1);
    var handle = ClientHandle{
        .server = s,
        .client_id = client_id,
        .wl_client = null,
        .display = null,
    };
    const parent_resource_id = try s.engine.resourceCreate(client_id, .surface, null, null);
    const parent_surface_id = try s.engine.surfaceCreate(client_id, parent_resource_id);
    const embed_id = try s.engine.embedCreate(client_id, parent_surface_id);
    try s.engine.embedMap(embed_id);
    s.engine.effects.clear();

    try std.testing.expect(!s.embedResize(&handle, -1, 10));
    try std.testing.expect(!s.embedResize(&handle, 10, -1));
    try std.testing.expectEqual(@as(usize, 0), s.engine.effects.count());

    try std.testing.expect(s.embedResize(&handle, 0, 0));
    const embed = s.engine.model.embeds.get(embed_id).?;
    try std.testing.expectEqual(@as(i32, 0), embed.width);
    try std.testing.expectEqual(@as(i32, 0), embed.height);

    handle.close_pending = true;
    try std.testing.expect(!s.embedResize(&handle, 1, 1));
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

test "server registers host-supplied seat global" {
    var state = RegistryTestState{ .seat_enabled = true };
    const iface = testHostInterface(&state);
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();

    try std.testing.expectEqual(@as(usize, 1), s.globals.items.len);
    try std.testing.expectEqual(@as(u32, 4), wls.c.wl_global_get_version(s.globals.items[0]));
}

test "server registers host-supplied xdg_wm_base global" {
    var state = RegistryTestState{ .xdg_wm_base_enabled = true };
    const iface = testHostInterface(&state);
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();

    try std.testing.expectEqual(@as(usize, 1), s.globals.items.len);
    try std.testing.expectEqual(@as(u32, 7), wls.c.wl_global_get_version(s.globals.items[0]));
}

test "server registers host-supplied output global" {
    var state = RegistryTestState{ .output_enabled = true };
    const iface = testHostInterface(&state);
    const s = try Server.create(std.testing.allocator, &iface, null);
    defer s.destroy();

    try std.testing.expectEqual(@as(usize, 1), s.globals.items.len);
    try std.testing.expectEqual(@as(u32, 4), wls.c.wl_global_get_version(s.globals.items[0]));
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
