//! Protocol-layer smoke tests. Every delegate's `create()` must return a
//! zero-init struct without crashing. Real behavior tests land here as
//! interfaces are implemented.

const builtin = @import("builtin");
const std = @import("std");
const wayplug = @import("wayplug");

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

const wlc = wayplug.wayland.client.c;
const wlp = wayplug.wayland.protocols;

test "every protocol delegate has a create() that compiles" {
    _ = wayplug.protocol.server_display.create();
    _ = wayplug.protocol.registry.create();
    _ = wayplug.protocol.compositor.create();
    _ = wayplug.protocol.surface.create();
    _ = wayplug.protocol.subcompositor.create();
    _ = wayplug.protocol.subsurface.create();
    _ = wayplug.protocol.shm.create();
    _ = wayplug.protocol.shm_pool.create();
    _ = wayplug.protocol.buffer.create();
    _ = wayplug.protocol.callback.create();
    _ = wayplug.protocol.region.create();
    _ = wayplug.protocol.seat.create();
    _ = wayplug.protocol.pointer.create();
    _ = wayplug.protocol.keyboard.create();
    _ = wayplug.protocol.output.create();
}

test "active protocol bindings instantiate against server runtime" {
    const Server = wayplug.server.Server;
    const ResourceData = wayplug.server.ResourceData;

    const Registry = wayplug.protocol.registry.Bindings(Server, ResourceData);
    _ = Registry.bindCompositor;
    _ = Registry.bindSubcompositor;
    _ = Registry.bindShm;
    _ = Registry.bindSeat;

    const Compositor = wayplug.protocol.compositor.Bindings(Server, ResourceData);
    _ = Compositor.impl;
    const Surface = wayplug.protocol.surface.Bindings(Server, ResourceData);
    _ = Surface.impl;
    const Subcompositor = wayplug.protocol.subcompositor.Bindings(Server, ResourceData);
    _ = Subcompositor.impl;
    const Subsurface = wayplug.protocol.subsurface.Bindings(Server, ResourceData);
    _ = Subsurface.impl;
    const Shm = wayplug.protocol.shm.Bindings(Server, ResourceData);
    _ = Shm.impl;
    const ShmPool = wayplug.protocol.shm_pool.Bindings(Server, ResourceData);
    _ = ShmPool.impl;
    const Buffer = wayplug.protocol.buffer.Bindings(Server, ResourceData);
    _ = Buffer.impl;
    _ = Buffer.listener;
    const Callback = wayplug.protocol.callback.Bindings(Server, ResourceData);
    _ = Callback.listener;
    const Region = wayplug.protocol.region.Bindings(Server, ResourceData);
    _ = Region.impl;
    const Seat = wayplug.protocol.seat.Bindings(Server, ResourceData);
    _ = Seat.impl;
    const Pointer = wayplug.protocol.pointer.Bindings(Server, ResourceData);
    _ = Pointer.impl;
    _ = Pointer.listener;
    const Keyboard = wayplug.protocol.keyboard.Bindings(Server, ResourceData);
    _ = Keyboard.impl;
    _ = Keyboard.listener;
}

const RegistryState = struct {
    compositor: ?*wlp.wl_compositor = null,
    subcompositor: ?*wlp.wl_subcompositor = null,
    shm: ?*wlp.wl_shm = null,
    seat: ?*wlp.wl_seat = null,
    seat_capabilities: u32 = 0,
};

const HostSmokeState = struct {
    compositor: ?*wlp.wl_compositor = null,
    subcompositor: ?*wlp.wl_subcompositor = null,
    shm: ?*wlp.wl_shm = null,
    seat: ?*wlp.wl_seat = null,
    seat_capabilities: u32 = 0,
    parent_surface: ?*wlp.wl_surface = null,
    surface_created_count: std.atomic.Value(u32) = .init(0),
    embed_attached: std.atomic.Value(bool) = .init(false),
    embed_mapped_count: std.atomic.Value(u32) = .init(0),
    embed_resized_count: std.atomic.Value(u32) = .init(0),
};

const ServerThreadContext = struct {
    server: *wayplug.server.Server,
    running: std.atomic.Value(bool) = .init(true),

    fn run(self: *@This()) void {
        while (self.running.load(.acquire)) {
            self.server.dispatch();
            self.server.flush();
            sleepMs(1);
        }
    }
};

const registry_listener = wlc.struct_wl_registry_listener{
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

const shm_listener = wlc.struct_wl_shm_listener{
    .format = shmFormat,
};

const seat_listener = wlc.struct_wl_seat_listener{
    .capabilities = seatCapabilities,
    .name = seatName,
};

fn registryGlobal(
    data: ?*anyopaque,
    registry: ?*wlc.struct_wl_registry,
    name: u32,
    interface: [*c]const u8,
    version: u32,
) callconv(.c) void {
    const state: *RegistryState = @ptrCast(@alignCast(data orelse return));
    const reg = registry orelse return;
    const raw_interface = interface orelse return;
    const interface_name = std.mem.span(@as([*:0]const u8, @ptrCast(raw_interface)));
    if (std.mem.eql(u8, interface_name, "wl_compositor")) {
        const bound = wlc.wl_registry_bind(reg, name, &wlc.wl_compositor_interface, @min(version, 4)) orelse return;
        state.compositor = @ptrCast(bound);
    } else if (std.mem.eql(u8, interface_name, "wl_subcompositor")) {
        const bound = wlc.wl_registry_bind(reg, name, &wlc.wl_subcompositor_interface, @min(version, 1)) orelse return;
        state.subcompositor = @ptrCast(bound);
    } else if (std.mem.eql(u8, interface_name, "wl_shm")) {
        const bound = wlc.wl_registry_bind(reg, name, &wlc.wl_shm_interface, @min(version, 1)) orelse return;
        const shm: *wlp.wl_shm = @ptrCast(bound);
        state.shm = shm;
        _ = wlc.wl_shm_add_listener(shm, &shm_listener, state);
    } else if (std.mem.eql(u8, interface_name, "wl_seat")) {
        const bound = wlc.wl_registry_bind(reg, name, &wlc.wl_seat_interface, @min(version, 4)) orelse return;
        const seat: *wlp.wl_seat = @ptrCast(bound);
        state.seat = seat;
        _ = wlc.wl_seat_add_listener(seat, &seat_listener, state);
    }
}

fn registryGlobalRemove(
    _: ?*anyopaque,
    _: ?*wlc.struct_wl_registry,
    _: u32,
) callconv(.c) void {}

fn shmFormat(_: ?*anyopaque, _: ?*wlp.wl_shm, _: u32) callconv(.c) void {}

fn seatCapabilities(data: ?*anyopaque, _: ?*wlp.wl_seat, capabilities: u32) callconv(.c) void {
    const state: *RegistryState = @ptrCast(@alignCast(data orelse return));
    state.seat_capabilities = capabilities;
}

fn seatName(_: ?*anyopaque, _: ?*wlp.wl_seat, _: [*c]const u8) callconv(.c) void {}

fn hostCompositor(userdata: ?*anyopaque) callconv(.c) ?*wlp.wl_compositor {
    const state: *HostSmokeState = @ptrCast(@alignCast(userdata orelse return null));
    return state.compositor;
}

fn hostSubcompositor(userdata: ?*anyopaque) callconv(.c) ?*wlp.wl_subcompositor {
    const state: *HostSmokeState = @ptrCast(@alignCast(userdata orelse return null));
    return state.subcompositor;
}

fn hostShm(userdata: ?*anyopaque) callconv(.c) ?*wlp.wl_shm {
    const state: *HostSmokeState = @ptrCast(@alignCast(userdata orelse return null));
    return state.shm;
}

fn hostSeat(userdata: ?*anyopaque) callconv(.c) ?*wlp.wl_seat {
    const state: *HostSmokeState = @ptrCast(@alignCast(userdata orelse return null));
    return state.seat;
}

fn hostSeatCapabilities(userdata: ?*anyopaque) callconv(.c) u32 {
    const state: *HostSmokeState = @ptrCast(@alignCast(userdata orelse return 0));
    return state.seat_capabilities;
}

fn hostSubsurfaceOffset(
    _: ?*anyopaque,
    x: *i32,
    y: *i32,
    _: *wayplug.wayland.client.wl_display,
    _: *wlp.wl_surface,
    _: *wlp.wl_surface,
) callconv(.c) bool {
    x.* = 0;
    y.* = 0;
    return true;
}

fn hostSurfaceCreated(
    userdata: ?*anyopaque,
    client: ?*wayplug.c_api.wayplug_client,
    child_surface: ?*wlp.wl_surface,
) callconv(.c) void {
    const state: *HostSmokeState = @ptrCast(@alignCast(userdata orelse return));
    const handle: *wayplug.server.ClientHandle = @ptrCast(@alignCast(client orelse return));
    const parent = state.parent_surface orelse return;
    const child = child_surface orelse return;
    const attached = handle.server.embedAttach(handle, parent, child);
    state.embed_attached.store(attached, .release);
    _ = state.surface_created_count.fetchAdd(1, .acq_rel);
}

fn hostEmbedMapped(userdata: ?*anyopaque, embed_id: u32) callconv(.c) void {
    if (embed_id == 0) return;
    const state: *HostSmokeState = @ptrCast(@alignCast(userdata orelse return));
    _ = state.embed_mapped_count.fetchAdd(1, .acq_rel);
}

fn hostEmbedResized(
    userdata: ?*anyopaque,
    embed_id: u32,
    width: i32,
    height: i32,
) callconv(.c) void {
    if (embed_id == 0 or width != 64 or height != 48) return;
    const state: *HostSmokeState = @ptrCast(@alignCast(userdata orelse return));
    _ = state.embed_resized_count.fetchAdd(1, .acq_rel);
}

test "weston headless smoke forwards create attach commit and embed" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const nonce = c.getpid();
    const runtime_dir = try std.fmt.allocPrintSentinel(allocator, "/tmp/wayplug-smoke-{d}", .{nonce}, 0);
    defer allocator.free(runtime_dir);
    const socket_name = try std.fmt.allocPrintSentinel(allocator, "wayplug-smoke-{d}", .{nonce}, 0);
    defer allocator.free(socket_name);
    const socket_arg = try std.fmt.allocPrint(allocator, "--socket={s}", .{socket_name});
    defer allocator.free(socket_arg);
    const log_path = try std.fmt.allocPrintSentinel(allocator, "{s}/weston.log", .{runtime_dir}, 0);
    defer allocator.free(log_path);
    const log_arg = try std.fmt.allocPrint(allocator, "--log={s}", .{log_path});
    defer allocator.free(log_arg);
    const socket_path = try std.fmt.allocPrintSentinel(allocator, "{s}/{s}", .{ runtime_dir, socket_name }, 0);
    defer allocator.free(socket_path);

    if (c.mkdir(runtime_dir.ptr, 0o700) != 0) return error.SkipZigTest;
    defer {
        _ = c.unlink(socket_path.ptr);
        _ = c.unlink(log_path.ptr);
        _ = c.rmdir(runtime_dir.ptr);
    }
    _ = c.chmod(runtime_dir.ptr, 0o700);
    if (c.setenv("XDG_RUNTIME_DIR", runtime_dir.ptr, 1) != 0) return error.EnvironmentSetupFailed;

    const weston_argv = [_][]const u8{
        "weston",
        "--backend=headless",
        "--renderer=pixman",
        "--shell=kiosk",
        "--no-config",
        "--idle-time=0",
        "--width=320",
        "--height=240",
        socket_arg,
        log_arg,
    };
    var weston = std.process.spawn(std.testing.io, .{
        .argv = weston_argv[0..],
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return error.SkipZigTest;
    var weston_running = true;
    defer if (weston_running) {
        weston.kill(std.testing.io);
    };

    if (!waitForSocket(socket_path)) return error.SkipZigTest;

    const host_display = wlc.wl_display_connect(socket_name.ptr) orelse return error.HostDisplayConnectFailed;
    defer wlc.wl_display_disconnect(host_display);
    const host_registry_state = try bindCoreGlobals(host_display);
    const parent_surface = wlc.wl_compositor_create_surface(host_registry_state.compositor.?) orelse return error.CreateParentSurfaceFailed;
    defer wlc.wl_surface_destroy(parent_surface);

    var host_state = HostSmokeState{
        .compositor = host_registry_state.compositor,
        .subcompositor = host_registry_state.subcompositor,
        .shm = host_registry_state.shm,
        .seat = host_registry_state.seat,
        .seat_capabilities = host_registry_state.seat_capabilities,
        .parent_surface = parent_surface,
    };
    const iface = wayplug.c_api.WayplugHostInterface{
        .size = @sizeOf(wayplug.c_api.WayplugHostInterface),
        .version = wayplug.c_api.abi_version,
        .userdata = &host_state,
        .get_compositor = hostCompositor,
        .get_subcompositor = hostSubcompositor,
        .get_shm = hostShm,
        .get_seat = hostSeat,
        .get_xdg_wm_base = null,
        .get_dmabuf = null,
        .get_seat_capabilities = hostSeatCapabilities,
        .get_seat_name = null,
        .get_subsurface_offset = hostSubsurfaceOffset,
        .on_client_connected = null,
        .on_surface_created = hostSurfaceCreated,
        .on_client_closed = null,
        .on_protocol_error = null,
        .on_embed_mapped = hostEmbedMapped,
        .on_embed_resized = hostEmbedResized,
        .on_embed_destroyed = null,
    };
    const server = try wayplug.server.Server.create(allocator, &iface, null);
    defer server.destroy();

    const plugin_display = server.openClientDisplay() orelse return error.PluginDisplayOpenFailed;
    var thread_context = ServerThreadContext{ .server = server };
    var server_thread: ?std.Thread = try std.Thread.spawn(.{}, ServerThreadContext.run, .{&thread_context});
    defer {
        thread_context.running.store(false, .release);
        if (server_thread) |thread| thread.join();
    }

    const plugin_registry_state = try bindCoreGlobals(plugin_display);
    if (host_registry_state.seat != null) {
        try std.testing.expect(plugin_registry_state.seat != null);
        try std.testing.expect((plugin_registry_state.seat_capabilities & wlc.WL_SEAT_CAPABILITY_POINTER) != 0);
    }
    const plugin_surface = wlc.wl_compositor_create_surface(plugin_registry_state.compositor.?) orelse return error.CreatePluginSurfaceFailed;
    defer wlc.wl_surface_destroy(plugin_surface);
    try flushDisplay(plugin_display);
    try waitForSurfaceCreated(&host_state);

    const buffer = try createPluginBuffer(plugin_registry_state.shm.?);
    defer wlc.wl_buffer_destroy(buffer);
    wlc.wl_surface_attach(plugin_surface, buffer, 0, 0);
    wlc.wl_surface_damage(plugin_surface, 0, 0, 16, 16);
    wlc.wl_surface_commit(plugin_surface);
    try flushDisplay(plugin_display);
    try std.testing.expect(server.embedResize(server.client_handles.items[0], 64, 48));
    try roundtripDisplay(plugin_display);
    try waitForEmbedCallbacks(&host_state);

    thread_context.running.store(false, .release);
    server_thread.?.join();
    server_thread = null;
    try roundtripDisplay(host_display);

    try std.testing.expectEqual(@as(u32, 1), host_state.surface_created_count.load(.acquire));
    try std.testing.expect(host_state.embed_attached.load(.acquire));
    try std.testing.expectEqual(@as(u32, 1), host_state.embed_mapped_count.load(.acquire));
    try std.testing.expectEqual(@as(u32, 1), host_state.embed_resized_count.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), server.engine.model.embeds.count());
    try std.testing.expectEqual(@as(usize, 2), server.engine.model.surfaces.count());
    try std.testing.expectEqual(@as(usize, 1), server.engine.model.buffers.count());
    const expected_resource_count: usize = if (plugin_registry_state.seat != null) 8 else 7;
    try std.testing.expectEqual(expected_resource_count, server.engine.model.resources.count());
    try std.testing.expectEqual(@as(c_int, 0), wlc.wl_display_get_error(plugin_display));
    try std.testing.expectEqual(@as(c_int, 0), wlc.wl_display_get_error(host_display));

    weston_running = false;
    weston.kill(std.testing.io);
}

fn bindCoreGlobals(display: *wlc.struct_wl_display) !RegistryState {
    var state = RegistryState{};
    const registry = wlc.wl_display_get_registry(display) orelse return error.GetRegistryFailed;
    defer wlc.wl_registry_destroy(registry);
    _ = wlc.wl_registry_add_listener(registry, &registry_listener, &state);
    try roundtripDisplay(display);
    if (state.compositor == null or state.subcompositor == null or state.shm == null) {
        return error.MissingCoreGlobals;
    }
    try roundtripDisplay(display);
    return state;
}

fn roundtripDisplay(display: *wlc.struct_wl_display) !void {
    try std.testing.expect(wlc.wl_display_roundtrip(display) >= 0);
}

fn flushDisplay(display: *wlc.struct_wl_display) !void {
    try std.testing.expect(wlc.wl_display_flush(display) >= 0);
}

fn waitForSocket(path: [:0]const u8) bool {
    for (0..200) |_| {
        if (c.access(path.ptr, c.F_OK) == 0) return true;
        sleepMs(10);
    }
    return false;
}

fn waitForSurfaceCreated(state: *const HostSmokeState) !void {
    for (0..200) |_| {
        if (state.surface_created_count.load(.acquire) > 0) {
            try std.testing.expect(state.embed_attached.load(.acquire));
            return;
        }
        sleepMs(10);
    }
    return error.SurfaceCreatedTimedOut;
}

fn waitForEmbedCallbacks(state: *const HostSmokeState) !void {
    for (0..200) |_| {
        if (state.embed_mapped_count.load(.acquire) > 0 and
            state.embed_resized_count.load(.acquire) > 0)
        {
            return;
        }
        sleepMs(10);
    }
    return error.EmbedCallbacksTimedOut;
}

fn sleepMs(ms: u32) void {
    _ = c.usleep(ms * 1000);
}

fn createPluginBuffer(shm: *wlp.wl_shm) !*wlp.wl_buffer {
    const width = 16;
    const height = 16;
    const stride = width * 4;
    const size = stride * height;
    const fd = try std.posix.memfd_create("wayplug-smoke-buffer", 0);
    defer _ = c.close(fd);
    if (c.ftruncate(fd, size) != 0) return error.TruncateBufferFailed;
    var pixels: [size]u8 = undefined;
    for (&pixels, 0..) |*byte, i| {
        byte.* = if (i % 4 == 3) 0xff else 0x40;
    }
    var written: usize = 0;
    while (written < pixels.len) {
        const rc = c.write(fd, pixels[written..].ptr, pixels.len - written);
        if (rc <= 0) return error.WriteBufferFailed;
        written += @intCast(rc);
    }
    const pool = wlc.wl_shm_create_pool(shm, fd, size) orelse return error.CreateShmPoolFailed;
    defer wlc.wl_shm_pool_destroy(pool);
    return wlc.wl_shm_pool_create_buffer(pool, 0, width, height, stride, wlc.WL_SHM_FORMAT_XRGB8888) orelse error.CreateBufferFailed;
}
