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
pub const adapter_abi_version: u32 = 1;
pub const adapter_format_unknown: u32 = 0;
pub const adapter_format_clap: u32 = 1;
pub const adapter_format_lv2: u32 = 2;
const adapter_clap_token = "wayplug.experimental.clap.wayland";
const adapter_lv2_token = "https://wayplug.org/ns/ext/wayland-ui";

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

pub const WayplugOutputInfo = extern struct {
    size: u32,
    version: u32,
    x: i32,
    y: i32,
    physical_width: i32,
    physical_height: i32,
    subpixel: i32,
    make: ?[*:0]const u8,
    model: ?[*:0]const u8,
    transform: i32,
    mode_flags: u32,
    mode_width: i32,
    mode_height: i32,
    mode_refresh: i32,
    scale: i32,
    name: ?[*:0]const u8,
    description: ?[*:0]const u8,
};

pub const WayplugAdapterHandoff = extern struct {
    size: u32,
    version: u32,
    format: u32,
    server: ?*server_mod.Server,
    display: ?*wlc.wl_display,
    format_token: ?[*:0]const u8,
    format_userdata: ?*anyopaque,
};

pub const WayplugAdapterResize = extern struct {
    size: u32,
    version: u32,
    width: i32,
    height: i32,
    scale: f64,
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
    on_embed_mapped: ?*const fn (?*anyopaque, u32) callconv(.c) void,
    on_embed_resized: ?*const fn (?*anyopaque, u32, i32, i32) callconv(.c) void,
    on_embed_destroyed: ?*const fn (?*anyopaque, u32) callconv(.c) void,

    get_seat_capabilities: ?*const fn (?*anyopaque) callconv(.c) u32,
    get_seat_name: ?*const fn (?*anyopaque) callconv(.c) ?[*:0]const u8,
    get_output_info: ?*const fn (?*anyopaque, *WayplugOutputInfo) callconv(.c) bool,
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
    copyHostField(&normalized, host, "on_embed_mapped");
    copyHostField(&normalized, host, "on_embed_resized");
    copyHostField(&normalized, host, "on_embed_destroyed");
    copyHostField(&normalized, host, "get_seat_capabilities");
    copyHostField(&normalized, host, "get_seat_name");
    copyHostField(&normalized, host, "get_output_info");
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
        .on_embed_mapped = null,
        .on_embed_resized = null,
        .on_embed_destroyed = null,
        .get_seat_capabilities = null,
        .get_seat_name = null,
        .get_output_info = null,
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

export fn wayplug_adapter_abi_version() callconv(.c) u32 {
    return adapter_abi_version;
}

export fn wayplug_adapter_handoff_init(
    handoff: ?*WayplugAdapterHandoff,
    format: u32,
    server: ?*server_mod.Server,
    display: ?*wlc.wl_display,
) callconv(.c) bool {
    const out = handoff orelse return false;
    if (out.size < @sizeOf(WayplugAdapterHandoff)) return false;
    if (server == null or display == null) return false;
    const token = adapterToken(format) orelse return false;
    out.* = .{
        .size = @sizeOf(WayplugAdapterHandoff),
        .version = adapter_abi_version,
        .format = format,
        .server = server,
        .display = display,
        .format_token = token,
        .format_userdata = null,
    };
    return true;
}

export fn wayplug_adapter_handoff_validate(
    handoff: ?*const WayplugAdapterHandoff,
) callconv(.c) bool {
    const h = handoff orelse return false;
    if (h.size < @sizeOf(WayplugAdapterHandoff)) return false;
    if (h.version != adapter_abi_version) return false;
    if (h.server == null or h.display == null) return false;
    if (adapterToken(h.format) == null) return false;
    return h.format_token != null;
}

export fn wayplug_adapter_resize_validate(
    resize: ?*const WayplugAdapterResize,
) callconv(.c) bool {
    const r = resize orelse return false;
    if (r.size < @sizeOf(WayplugAdapterResize)) return false;
    if (r.version != adapter_abi_version) return false;
    if (r.width < 0 or r.height < 0) return false;
    return r.scale > 0;
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

fn adapterToken(format: u32) ?[*:0]const u8 {
    return switch (format) {
        adapter_format_clap => adapter_clap_token,
        adapter_format_lv2 => adapter_lv2_token,
        else => null,
    };
}

// ===== production code above =====

test "ABI version is stable" {
    try std.testing.expectEqual(@as(u32, 1), wayplug_abi_version());
    try std.testing.expectEqual(@as(u32, 1), wayplug_adapter_abi_version());
}

test "Server null-handle is tolerated" {
    wayplug_server_destroy(null);
    try std.testing.expect(wayplug_server_get_fd(null) == -1);
    try std.testing.expect(!wayplug_server_close_client_display(null, null));
    try std.testing.expect(wayplug_server_snapshot(null) == null);
    wayplug_snapshot_free(null);
    try std.testing.expect(!wayplug_snapshot_get_counts(null, null));
}

test "adapter handoff initialization validates inputs" {
    var handoff: WayplugAdapterHandoff = .{
        .size = @sizeOf(WayplugAdapterHandoff),
        .version = 0,
        .format = adapter_format_unknown,
        .server = null,
        .display = null,
        .format_token = null,
        .format_userdata = null,
    };

    try std.testing.expect(!wayplug_adapter_handoff_init(null, adapter_format_clap, null, null));
    try std.testing.expect(!wayplug_adapter_handoff_init(&handoff, adapter_format_unknown, null, null));
    try std.testing.expect(!wayplug_adapter_handoff_init(&handoff, adapter_format_clap, null, null));

    const server: *server_mod.Server = @ptrFromInt(@alignOf(server_mod.Server));
    const display: *wlc.wl_display = @ptrFromInt(1);
    try std.testing.expect(wayplug_adapter_handoff_init(&handoff, adapter_format_clap, server, display));
    try std.testing.expect(wayplug_adapter_handoff_validate(&handoff));
    try std.testing.expectEqual(adapter_abi_version, handoff.version);
    try std.testing.expectEqual(adapter_format_clap, handoff.format);

    handoff.version = adapter_abi_version + 1;
    try std.testing.expect(!wayplug_adapter_handoff_validate(&handoff));
}

test "adapter resize validation rejects invalid dimensions" {
    var resize: WayplugAdapterResize = .{
        .size = @sizeOf(WayplugAdapterResize),
        .version = adapter_abi_version,
        .width = 320,
        .height = 200,
        .scale = 1,
    };
    try std.testing.expect(wayplug_adapter_resize_validate(&resize));
    resize.width = -1;
    try std.testing.expect(!wayplug_adapter_resize_validate(&resize));
    resize.width = 320;
    resize.scale = 0;
    try std.testing.expect(!wayplug_adapter_resize_validate(&resize));
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
    try std.testing.expect(normalized.get_seat_capabilities == null);
    try std.testing.expect(normalized.get_seat_name == null);
    try std.testing.expect(normalized.get_output_info == null);
    try std.testing.expect(normalized.on_protocol_error == null);
    try std.testing.expect(normalized.on_embed_mapped == null);
    try std.testing.expect(normalized.on_embed_resized == null);
    try std.testing.expect(normalized.on_embed_destroyed == null);
}

test "host interface normalization accepts pre-embed-callback sizes" {
    var iface = emptyHostInterface();
    iface.size = @offsetOf(WayplugHostInterface, "on_embed_mapped");
    const normalized = normalizeHostInterface(&iface).?;
    try std.testing.expect(normalized.on_protocol_error == null);
    try std.testing.expect(normalized.on_embed_mapped == null);
    try std.testing.expect(normalized.on_embed_resized == null);
    try std.testing.expect(normalized.on_embed_destroyed == null);
    try std.testing.expect(normalized.get_output_info == null);
}

test "host interface normalization accepts pre-output-info sizes" {
    var iface = emptyHostInterface();
    iface.size = @offsetOf(WayplugHostInterface, "get_output_info");
    const normalized = normalizeHostInterface(&iface).?;
    try std.testing.expect(normalized.get_output_info == null);
}

test "host interface normalization rejects too-small structs" {
    var iface = emptyHostInterface();
    iface.size = minimum_host_interface_size - 1;
    try std.testing.expect(normalizeHostInterface(&iface) == null);
}
