//! C ABI surface. The only module that exports `wayplug_*` symbols.
//!
//! Defines every extern struct and validates ABI arguments before
//! delegating to `server.zig`. Internal modules should not import
//! anything from here except the extern struct definitions.

const std = @import("std");
const snapshot_mod = @import("data/snapshot.zig");
const server_mod = @import("server.zig");
const wlc = @import("wayland/client.zig");
const wlp = @import("wayland/protocols.zig");

pub const abi_version: u32 = 1;

/// Opaque to C callers; really `server_mod.Server` on the Zig side.
pub const wayplug_server = opaque {};

/// Opaque per-client handle the host receives via lifecycle callbacks
/// and passes back into `wayplug_embed_*` operations.
pub const wayplug_client = opaque {};

/// Opaque caller-owned snapshot handle.
pub const wayplug_snapshot = opaque {};

pub const WayplugSnapshotCounts = extern struct {
    size: u32,
    version: u32,
    clients: usize,
    resources: usize,
    surfaces: usize,
    buffers: usize,
    embeds: usize,
    outputs: usize,
};

const SnapshotHandle = struct {
    allocator: std.mem.Allocator,
    snapshot: snapshot_mod.Snapshot,

    fn destroy(self: *SnapshotHandle) void {
        const allocator = self.allocator;
        self.snapshot.deinit();
        allocator.destroy(self);
    }
};

pub const WayplugHostInterface = extern struct {
    size: u32,
    version: u32,
    userdata: ?*anyopaque,

    get_compositor: ?*const fn (?*anyopaque) callconv(.c) ?*wlp.wl_compositor,
    get_subcompositor: ?*const fn (?*anyopaque) callconv(.c) ?*wlp.wl_subcompositor,
    get_shm: ?*const fn (?*anyopaque) callconv(.c) ?*wlp.wl_shm,
    get_seat: ?*const fn (?*anyopaque) callconv(.c) ?*wlp.wl_seat,
    get_xdg_wm_base: ?*const fn (?*anyopaque) callconv(.c) ?*wlp.xdg_wm_base,
    get_dmabuf: ?*const fn (?*anyopaque) callconv(.c) ?*wlp.zwp_linux_dmabuf_v1,

    get_subsurface_offset: ?*const fn (
        ?*anyopaque,
        *i32,
        *i32,
        *wlc.wl_display,
        *wlp.wl_surface,
        *wlp.wl_surface,
    ) callconv(.c) bool,

    on_client_connected: ?*const fn (?*anyopaque, ?*wayplug_client) callconv(.c) void,
    on_surface_created: ?*const fn (?*anyopaque, ?*wayplug_client, ?*wlp.wl_surface) callconv(.c) void,
    on_client_closed: ?*const fn (?*anyopaque, ?*wayplug_client) callconv(.c) void,
    on_protocol_error: ?*const fn (?*anyopaque, ?*wayplug_client, u32) callconv(.c) void,
};

const minimum_host_interface_size = @offsetOf(WayplugHostInterface, "userdata") +
    @sizeOf(?*anyopaque);

pub fn normalizeHostInterface(host: *const WayplugHostInterface) ?WayplugHostInterface {
    if (host.size < minimum_host_interface_size) return null;
    if (host.version != abi_version) return null;

    var normalized = emptyHostInterface();
    normalized.size = @sizeOf(WayplugHostInterface);
    normalized.version = abi_version;
    copyHostField(&normalized, host, "userdata");
    copyHostField(&normalized, host, "get_compositor");
    copyHostField(&normalized, host, "get_subcompositor");
    copyHostField(&normalized, host, "get_shm");
    copyHostField(&normalized, host, "get_seat");
    copyHostField(&normalized, host, "get_xdg_wm_base");
    copyHostField(&normalized, host, "get_dmabuf");
    copyHostField(&normalized, host, "get_subsurface_offset");
    copyHostField(&normalized, host, "on_client_connected");
    copyHostField(&normalized, host, "on_surface_created");
    copyHostField(&normalized, host, "on_client_closed");
    copyHostField(&normalized, host, "on_protocol_error");
    return normalized;
}

fn emptyHostInterface() WayplugHostInterface {
    return .{
        .size = @sizeOf(WayplugHostInterface),
        .version = abi_version,
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
}

fn copyHostField(
    normalized: *WayplugHostInterface,
    host: *const WayplugHostInterface,
    comptime field_name: []const u8,
) void {
    const Field = @TypeOf(@field(normalized, field_name));
    const end = @offsetOf(WayplugHostInterface, field_name) + @sizeOf(Field);
    if (host.size >= end) {
        @field(normalized, field_name) = @field(host.*, field_name);
    }
}

// ===== Exports =====

export fn wayplug_abi_version() callconv(.c) u32 {
    return abi_version;
}

export fn wayplug_server_create(
    host: ?*const WayplugHostInterface,
    queue: ?*wlc.wl_event_queue,
) callconv(.c) ?*server_mod.Server {
    const iface = host orelse return null;
    const normalized = normalizeHostInterface(iface) orelse return null;
    return server_mod.Server.create(std.heap.c_allocator, &normalized, queue) catch null;
}

export fn wayplug_server_destroy(server: ?*server_mod.Server) callconv(.c) void {
    const s = server orelse return;
    s.destroy();
}

export fn wayplug_server_get_fd(server: ?*server_mod.Server) callconv(.c) c_int {
    const s = server orelse return -1;
    return s.getFd();
}

export fn wayplug_server_dispatch(server: ?*server_mod.Server) callconv(.c) void {
    const s = server orelse return;
    s.dispatch();
}

export fn wayplug_server_flush(server: ?*server_mod.Server) callconv(.c) void {
    const s = server orelse return;
    s.flush();
}

export fn wayplug_server_snapshot(server: ?*server_mod.Server) callconv(.c) ?*wayplug_snapshot {
    const s = server orelse return null;
    const allocator = s.allocator;
    const handle = allocator.create(SnapshotHandle) catch return null;
    const snap = s.snapshot() catch {
        allocator.destroy(handle);
        return null;
    };
    handle.* = .{
        .allocator = allocator,
        .snapshot = snap,
    };
    return @ptrCast(handle);
}

export fn wayplug_snapshot_get_counts(
    snapshot: ?*const wayplug_snapshot,
    counts: ?*WayplugSnapshotCounts,
) callconv(.c) bool {
    const handle = snapshotHandleConst(snapshot) orelse return false;
    const out = counts orelse return false;
    if (out.size < @sizeOf(WayplugSnapshotCounts)) return false;
    if (out.version != abi_version) return false;

    out.* = .{
        .size = @sizeOf(WayplugSnapshotCounts),
        .version = abi_version,
        .clients = handle.snapshot.counts.clients,
        .resources = handle.snapshot.counts.resources,
        .surfaces = handle.snapshot.counts.surfaces,
        .buffers = handle.snapshot.counts.buffers,
        .embeds = handle.snapshot.counts.embeds,
        .outputs = handle.snapshot.counts.outputs,
    };
    return true;
}

export fn wayplug_snapshot_free(snapshot: ?*wayplug_snapshot) callconv(.c) void {
    const handle = snapshotHandle(snapshot) orelse return;
    handle.destroy();
}

export fn wayplug_server_open_client_display(
    server: ?*server_mod.Server,
) callconv(.c) ?*wlc.wl_display {
    const s = server orelse return null;
    return s.openClientDisplay();
}

export fn wayplug_server_close_client_display(
    server: ?*server_mod.Server,
    display: ?*wlc.wl_display,
) callconv(.c) bool {
    const s = server orelse return false;
    const d = display orelse return false;
    return s.closeClientDisplay(d);
}

export fn wayplug_server_create_proxy(
    server: ?*server_mod.Server,
    client_display: ?*wlc.wl_display,
    host_object: ?*wlc.wl_proxy,
) callconv(.c) ?*wlc.wl_proxy {
    _ = server;
    _ = client_display;
    _ = host_object;
    return null;
}

export fn wayplug_server_destroy_proxy(
    server: ?*server_mod.Server,
    proxy: ?*wlc.wl_proxy,
) callconv(.c) void {
    _ = server;
    _ = proxy;
}

export fn wayplug_embed_attach(
    client: ?*wayplug_client,
    parent_surface: ?*wlp.wl_surface,
    child_surface: ?*wlp.wl_surface,
) callconv(.c) bool {
    const c = clientHandle(client) orelse return false;
    const parent = parent_surface orelse return false;
    const child = child_surface orelse return false;
    return c.server.embedAttach(c, parent, child);
}

export fn wayplug_embed_resize(
    client: ?*wayplug_client,
    width: i32,
    height: i32,
) callconv(.c) bool {
    const c = clientHandle(client) orelse return false;
    return c.server.embedResize(c, width, height);
}

fn clientHandle(client: ?*wayplug_client) ?*server_mod.ClientHandle {
    const c = client orelse return null;
    return @ptrCast(@alignCast(c));
}

fn snapshotHandle(snapshot: ?*wayplug_snapshot) ?*SnapshotHandle {
    const s = snapshot orelse return null;
    return @ptrCast(@alignCast(s));
}

fn snapshotHandleConst(snapshot: ?*const wayplug_snapshot) ?*const SnapshotHandle {
    const s = snapshot orelse return null;
    return @ptrCast(@alignCast(s));
}

// ===== production code above =====

test "ABI version is stable" {
    try std.testing.expectEqual(@as(u32, 1), wayplug_abi_version());
}

test "Server null-handle is tolerated" {
    wayplug_server_destroy(null);
    try std.testing.expect(wayplug_server_get_fd(null) == -1);
    try std.testing.expect(!wayplug_server_close_client_display(null, null));
    try std.testing.expect(wayplug_server_snapshot(null) == null);
    wayplug_snapshot_free(null);
    try std.testing.expect(!wayplug_snapshot_get_counts(null, null));
}

test "snapshot count output validates size and version" {
    const snapshot_handle: SnapshotHandle = .{
        .allocator = std.testing.allocator,
        .snapshot = .{
            .allocator = std.testing.allocator,
            .counts = .{
                .clients = 1,
                .resources = 2,
                .surfaces = 3,
                .buffers = 4,
                .embeds = 5,
                .outputs = 6,
            },
        },
    };
    const opaque_snapshot: *const wayplug_snapshot = @ptrCast(@constCast(&snapshot_handle));

    var counts: WayplugSnapshotCounts = .{
        .size = @sizeOf(WayplugSnapshotCounts),
        .version = abi_version,
        .clients = 0,
        .resources = 0,
        .surfaces = 0,
        .buffers = 0,
        .embeds = 0,
        .outputs = 0,
    };
    try std.testing.expect(wayplug_snapshot_get_counts(opaque_snapshot, &counts));
    try std.testing.expectEqual(@as(usize, 1), counts.clients);
    try std.testing.expectEqual(@as(usize, 6), counts.outputs);

    counts.size = @offsetOf(WayplugSnapshotCounts, "outputs");
    counts.version = abi_version;
    try std.testing.expect(!wayplug_snapshot_get_counts(opaque_snapshot, &counts));

    counts.size = @sizeOf(WayplugSnapshotCounts);
    counts.version = abi_version + 1;
    try std.testing.expect(!wayplug_snapshot_get_counts(opaque_snapshot, &counts));
}

test "host interface normalization accepts older append-only sizes" {
    var iface = emptyHostInterface();
    iface.size = @offsetOf(WayplugHostInterface, "on_protocol_error");
    const normalized = normalizeHostInterface(&iface).?;
    try std.testing.expectEqual(@sizeOf(WayplugHostInterface), normalized.size);
    try std.testing.expect(normalized.on_protocol_error == null);
}

test "host interface normalization rejects too-small structs" {
    var iface = emptyHostInterface();
    iface.size = minimum_host_interface_size - 1;
    try std.testing.expect(normalizeHostInterface(&iface) == null);
}
