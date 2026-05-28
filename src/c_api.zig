//! C ABI surface. The only module that exports `wayembed_*` symbols.
//!
//! Defines every extern struct and validates ABI arguments before
//! delegating to `server.zig`. Internal modules should not import
//! anything from here except the extern struct definitions.

const std = @import("std");
const snapshot_mod = @import("data/snapshot.zig");
const server_mod = @import("server.zig");
const wlc = @import("wayland/client.zig");
const wlp = @import("wayland/protocols.zig");

pub const abi_version: u32 = 2;
pub const adapter_abi_version: u32 = 1;
pub const adapter_format_unknown: u32 = 0;
pub const adapter_format_clap: u32 = 1;
pub const adapter_format_lv2: u32 = 2;
pub const adapter_format_vst3: u32 = 3;
const adapter_clap_token = "wayembed.experimental.clap.wayland";
const adapter_lv2_token = "https://wayembed.org/ns/ext/wayland-ui";
const adapter_vst3_token = "WaylandSurfaceID";
pub const feature_compositor: u64 = 1 << 0;
pub const feature_subcompositor: u64 = 1 << 1;
pub const feature_surface: u64 = 1 << 2;
pub const feature_shm_buffer: u64 = 1 << 3;
pub const feature_embed_session: u64 = 1 << 4;
pub const feature_seat: u64 = 1 << 5;
pub const feature_pointer: u64 = 1 << 6;
pub const feature_keyboard: u64 = 1 << 7;
pub const feature_touch: u64 = 1 << 8;
pub const feature_output: u64 = 1 << 9;
pub const feature_xdg_shell: u64 = 1 << 10;
pub const feature_client_fd: u64 = 1 << 11;
pub const feature_linux_dmabuf: u64 = 1 << 12;
const compiled_features: u64 =
    feature_compositor |
    feature_subcompositor |
    feature_surface |
    feature_shm_buffer |
    feature_embed_session |
    feature_seat |
    feature_pointer |
    feature_keyboard |
    feature_touch |
    feature_output |
    feature_xdg_shell |
    feature_client_fd |
    feature_linux_dmabuf;
pub const embed_status_ok: u32 = 0;
pub const embed_status_invalid_argument: u32 = 1;
pub const embed_status_client_closing: u32 = 2;
pub const embed_status_already_embedded: u32 = 3;
pub const embed_status_unknown_surface: u32 = 4;
pub const embed_status_surface_has_role: u32 = 5;
pub const embed_status_unsupported: u32 = 6;
pub const embed_status_upstream_failed: u32 = 7;
pub const embed_status_unknown_embed: u32 = 8;

/// Opaque to C callers; really `server_mod.Server` on the Zig side.
pub const wayembed_server = opaque {};

/// Opaque per-client handle the host receives via lifecycle callbacks
/// and passes back into `wayembed_embed_*` operations.
pub const wayembed_client = opaque {};

/// Opaque server-owned embedded session handle.
pub const wayembed_embed = opaque {};

/// Opaque caller-owned snapshot handle.
pub const wayembed_snapshot = opaque {};

pub const WayembedSnapshotCounts = extern struct {
    size: u32,
    version: u32,
    clients: usize,
    resources: usize,
    surfaces: usize,
    buffers: usize,
    embeds: usize,
    outputs: usize,
};

pub const WayembedOutputInfo = extern struct {
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

pub const WayembedFeatures = extern struct {
    size: u32,
    version: u32,
    flags: u64,
};

pub const WayembedEmbedAttachInfo = extern struct {
    size: u32,
    version: u32,
    client: ?*wayembed_client,
    parent_surface: ?*wlp.wl_surface,
    child_surface: ?*wlp.wl_surface,
};

pub const WayembedAdapterHandoff = extern struct {
    size: u32,
    version: u32,
    format: u32,
    server: ?*server_mod.Server,
    display: ?*wlc.wl_display,
    format_token: ?[*:0]const u8,
    format_userdata: ?*anyopaque,
};

pub const WayembedAdapterFdHandoff = extern struct {
    size: u32,
    version: u32,
    format: u32,
    server: ?*server_mod.Server,
    client: ?*wayembed_client,
    client_fd: i32,
    format_token: ?[*:0]const u8,
    format_userdata: ?*anyopaque,
};

pub const WayembedAdapterResize = extern struct {
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

pub const WayembedHostInterface = extern struct {
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
        ?*wlc.wl_display,
        *wlp.wl_surface,
        *wlp.wl_surface,
    ) callconv(.c) bool,

    on_client_connected: ?*const fn (?*anyopaque, ?*wayembed_client) callconv(.c) void,
    on_surface_created: ?*const fn (?*anyopaque, ?*wayembed_client, ?*wlp.wl_surface) callconv(.c) void,
    on_client_closed: ?*const fn (?*anyopaque, ?*wayembed_client) callconv(.c) void,
    on_protocol_error: ?*const fn (?*anyopaque, ?*wayembed_client, u32) callconv(.c) void,
    on_embed_mapped: ?*const fn (?*anyopaque, ?*wayembed_embed) callconv(.c) void,
    on_embed_resized: ?*const fn (?*anyopaque, ?*wayembed_embed, i32, i32) callconv(.c) void,
    on_embed_destroyed: ?*const fn (?*anyopaque, ?*wayembed_embed) callconv(.c) void,

    get_seat_capabilities: ?*const fn (?*anyopaque) callconv(.c) u32,
    get_seat_name: ?*const fn (?*anyopaque) callconv(.c) ?[*:0]const u8,
    get_output_info: ?*const fn (?*anyopaque, *WayembedOutputInfo) callconv(.c) bool,
};

const minimum_host_interface_size = @offsetOf(WayembedHostInterface, "userdata") +
    @sizeOf(?*anyopaque);

pub fn normalizeHostInterface(host: *const WayembedHostInterface) ?WayembedHostInterface {
    if (host.size < minimum_host_interface_size) return null;
    if (host.version != abi_version) return null;

    var normalized = emptyHostInterface();
    normalized.size = @sizeOf(WayembedHostInterface);
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

fn emptyHostInterface() WayembedHostInterface {
    return .{
        .size = @sizeOf(WayembedHostInterface),
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
    normalized: *WayembedHostInterface,
    host: *const WayembedHostInterface,
    comptime field_name: []const u8,
) void {
    const Field = @TypeOf(@field(normalized, field_name));
    const end = @offsetOf(WayembedHostInterface, field_name) + @sizeOf(Field);
    if (host.size >= end) {
        @field(normalized, field_name) = @field(host.*, field_name);
    }
}

// ===== Exports =====

export fn wayembed_abi_version() callconv(.c) u32 {
    return abi_version;
}

export fn wayembed_get_features(features: ?*WayembedFeatures) callconv(.c) bool {
    const out = features orelse return false;
    if (out.size < @sizeOf(WayembedFeatures)) return false;
    if (out.version != abi_version) return false;
    out.* = .{
        .size = @sizeOf(WayembedFeatures),
        .version = abi_version,
        .flags = compiled_features,
    };
    return true;
}

export fn wayembed_adapter_abi_version() callconv(.c) u32 {
    return adapter_abi_version;
}

export fn wayembed_adapter_handoff_init(
    handoff: ?*WayembedAdapterHandoff,
    format: u32,
    server: ?*server_mod.Server,
    display: ?*wlc.wl_display,
) callconv(.c) bool {
    const out = handoff orelse return false;
    if (out.size < @sizeOf(WayembedAdapterHandoff)) return false;
    if (server == null or display == null) return false;
    const token = adapterToken(format) orelse return false;
    out.* = .{
        .size = @sizeOf(WayembedAdapterHandoff),
        .version = adapter_abi_version,
        .format = format,
        .server = server,
        .display = display,
        .format_token = token,
        .format_userdata = null,
    };
    return true;
}

export fn wayembed_adapter_handoff_validate(
    handoff: ?*const WayembedAdapterHandoff,
) callconv(.c) bool {
    const h = handoff orelse return false;
    if (h.size < @sizeOf(WayembedAdapterHandoff)) return false;
    if (h.version != adapter_abi_version) return false;
    if (h.server == null or h.display == null) return false;
    const expected_token = adapterToken(h.format) orelse return false;
    const actual_token = h.format_token orelse return false;
    return std.mem.eql(u8, std.mem.span(expected_token), std.mem.span(actual_token));
}

export fn wayembed_adapter_fd_handoff_init(
    handoff: ?*WayembedAdapterFdHandoff,
    format: u32,
    server: ?*server_mod.Server,
    client: ?*wayembed_client,
    client_fd: i32,
) callconv(.c) bool {
    const out = handoff orelse return false;
    if (out.size < @sizeOf(WayembedAdapterFdHandoff)) return false;
    if (server == null or client == null or client_fd < 0) return false;
    const token = adapterToken(format) orelse return false;
    out.* = .{
        .size = @sizeOf(WayembedAdapterFdHandoff),
        .version = adapter_abi_version,
        .format = format,
        .server = server,
        .client = client,
        .client_fd = client_fd,
        .format_token = token,
        .format_userdata = null,
    };
    return true;
}

export fn wayembed_adapter_fd_handoff_validate(
    handoff: ?*const WayembedAdapterFdHandoff,
) callconv(.c) bool {
    const h = handoff orelse return false;
    if (h.size < @sizeOf(WayembedAdapterFdHandoff)) return false;
    if (h.version != adapter_abi_version) return false;
    if (h.server == null or h.client == null or h.client_fd < 0) return false;
    const expected_token = adapterToken(h.format) orelse return false;
    const actual_token = h.format_token orelse return false;
    return std.mem.eql(u8, std.mem.span(expected_token), std.mem.span(actual_token));
}

export fn wayembed_adapter_resize_validate(
    resize: ?*const WayembedAdapterResize,
) callconv(.c) bool {
    const r = resize orelse return false;
    if (r.size < @sizeOf(WayembedAdapterResize)) return false;
    if (r.version != adapter_abi_version) return false;
    if (r.width < 0 or r.height < 0) return false;
    return std.math.isFinite(r.scale) and r.scale > 0;
}

export fn wayembed_server_create(
    host: ?*const WayembedHostInterface,
    queue: ?*wlc.wl_event_queue,
) callconv(.c) ?*server_mod.Server {
    const iface = host orelse return null;
    const normalized = normalizeHostInterface(iface) orelse return null;
    return server_mod.Server.create(std.heap.c_allocator, &normalized, queue) catch null;
}

export fn wayembed_server_destroy(server: ?*server_mod.Server) callconv(.c) void {
    const s = server orelse return;
    s.destroy();
}

export fn wayembed_server_get_fd(server: ?*server_mod.Server) callconv(.c) c_int {
    const s = server orelse return -1;
    return s.getFd();
}

export fn wayembed_server_dispatch(server: ?*server_mod.Server) callconv(.c) void {
    const s = server orelse return;
    s.dispatch();
}

export fn wayembed_server_flush(server: ?*server_mod.Server) callconv(.c) void {
    const s = server orelse return;
    s.flush();
}

export fn wayembed_server_snapshot(server: ?*server_mod.Server) callconv(.c) ?*wayembed_snapshot {
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

export fn wayembed_snapshot_get_counts(
    snapshot: ?*const wayembed_snapshot,
    counts: ?*WayembedSnapshotCounts,
) callconv(.c) bool {
    const handle = snapshotHandleConst(snapshot) orelse return false;
    const out = counts orelse return false;
    if (out.size < @sizeOf(WayembedSnapshotCounts)) return false;
    if (out.version != abi_version) return false;

    out.* = .{
        .size = @sizeOf(WayembedSnapshotCounts),
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

export fn wayembed_snapshot_free(snapshot: ?*wayembed_snapshot) callconv(.c) void {
    const handle = snapshotHandle(snapshot) orelse return;
    handle.destroy();
}

export fn wayembed_server_open_client_display(
    server: ?*server_mod.Server,
) callconv(.c) ?*wlc.wl_display {
    const s = server orelse return null;
    return s.openClientDisplay();
}

export fn wayembed_server_close_client_display(
    server: ?*server_mod.Server,
    display: ?*wlc.wl_display,
) callconv(.c) bool {
    const s = server orelse return false;
    const d = display orelse return false;
    return s.closeClientDisplay(d);
}

export fn wayembed_server_open_client_fd(
    server: ?*server_mod.Server,
    out_client: ?*?*wayembed_client,
) callconv(.c) c_int {
    const out = out_client orelse return -1;
    out.* = null;
    const s = server orelse return -1;
    return s.openClientFd(out);
}

export fn wayembed_server_close_client(
    server: ?*server_mod.Server,
    client: ?*wayembed_client,
) callconv(.c) bool {
    const s = server orelse return false;
    const c = client orelse return false;
    return s.closeClient(c);
}

export fn wayembed_server_create_proxy(
    server: ?*server_mod.Server,
    client_display: ?*wlc.wl_display,
    host_object: ?*wlc.wl_proxy,
) callconv(.c) ?*wlc.wl_proxy {
    _ = server;
    _ = client_display;
    _ = host_object;
    return null;
}

export fn wayembed_server_destroy_proxy(
    server: ?*server_mod.Server,
    proxy: ?*wlc.wl_proxy,
) callconv(.c) void {
    _ = server;
    _ = proxy;
}

pub export fn wayembed_embed_attach(
    info: ?*const WayembedEmbedAttachInfo,
    out_embed: ?*?*wayembed_embed,
) callconv(.c) u32 {
    const out = out_embed orelse return embed_status_invalid_argument;
    out.* = null;
    const attach_info = info orelse return embed_status_invalid_argument;
    if (attach_info.size < @sizeOf(WayembedEmbedAttachInfo)) return embed_status_invalid_argument;
    if (attach_info.version != abi_version) return embed_status_invalid_argument;
    const c = clientHandle(attach_info.client) orelse return embed_status_invalid_argument;
    const parent = attach_info.parent_surface orelse return embed_status_invalid_argument;
    const child = attach_info.child_surface orelse return embed_status_invalid_argument;
    var handle: ?*server_mod.EmbedHandle = null;
    const status = c.server.embedAttach(c, parent, child, &handle);
    if (status == embed_status_ok) {
        out.* = @ptrCast(handle.?);
    }
    return status;
}

pub export fn wayembed_embed_resize(
    embed: ?*wayembed_embed,
    width: i32,
    height: i32,
) callconv(.c) u32 {
    const e = embedHandle(embed) orelse return embed_status_invalid_argument;
    return e.server.embedResize(e, width, height);
}

pub export fn wayembed_embed_id(embed: ?*const wayembed_embed) callconv(.c) u32 {
    const e = embedHandleConst(embed) orelse return 0;
    return @intFromEnum(e.embed_id);
}

pub export fn wayembed_embed_client(embed: ?*const wayembed_embed) callconv(.c) ?*wayembed_client {
    const e = embedHandleConst(embed) orelse return null;
    return e.server.opaqueClientForId(e.client_id);
}

fn clientHandle(client: ?*wayembed_client) ?*server_mod.ClientHandle {
    const c = client orelse return null;
    return @ptrCast(@alignCast(c));
}

fn embedHandle(embed: ?*wayembed_embed) ?*server_mod.EmbedHandle {
    const e = embed orelse return null;
    return @ptrCast(@alignCast(e));
}

fn embedHandleConst(embed: ?*const wayembed_embed) ?*const server_mod.EmbedHandle {
    const e = embed orelse return null;
    return @ptrCast(@alignCast(e));
}

fn snapshotHandle(snapshot: ?*wayembed_snapshot) ?*SnapshotHandle {
    const s = snapshot orelse return null;
    return @ptrCast(@alignCast(s));
}

fn snapshotHandleConst(snapshot: ?*const wayembed_snapshot) ?*const SnapshotHandle {
    const s = snapshot orelse return null;
    return @ptrCast(@alignCast(s));
}

fn adapterToken(format: u32) ?[*:0]const u8 {
    return switch (format) {
        adapter_format_clap => adapter_clap_token,
        adapter_format_lv2 => adapter_lv2_token,
        adapter_format_vst3 => adapter_vst3_token,
        else => null,
    };
}

// ===== production code above =====

test "ABI version is stable" {
    try std.testing.expectEqual(@as(u32, 2), wayembed_abi_version());
    try std.testing.expectEqual(@as(u32, 1), wayembed_adapter_abi_version());
}

test "Server null-handle is tolerated" {
    wayembed_server_destroy(null);
    try std.testing.expect(wayembed_server_get_fd(null) == -1);
    try std.testing.expect(!wayembed_server_close_client_display(null, null));
    try std.testing.expectEqual(@as(c_int, -1), wayembed_server_open_client_fd(null, null));
    try std.testing.expect(!wayembed_server_close_client(null, null));
    try std.testing.expect(wayembed_server_snapshot(null) == null);
    wayembed_snapshot_free(null);
    try std.testing.expect(!wayembed_snapshot_get_counts(null, null));
    try std.testing.expect(!wayembed_get_features(null));
    try std.testing.expectEqual(embed_status_invalid_argument, wayembed_embed_attach(null, null));
    try std.testing.expectEqual(embed_status_invalid_argument, wayembed_embed_resize(null, 0, 0));
    try std.testing.expectEqual(@as(u32, 0), wayembed_embed_id(null));
    try std.testing.expect(wayembed_embed_client(null) == null);
}

test "feature query validates size and version" {
    var features: WayembedFeatures = .{
        .size = @sizeOf(WayembedFeatures),
        .version = abi_version,
        .flags = 0,
    };

    try std.testing.expect(wayembed_get_features(&features));
    try std.testing.expectEqual(compiled_features, features.flags);
    try std.testing.expect((features.flags & feature_compositor) != 0);
    try std.testing.expect((features.flags & feature_surface) != 0);
    try std.testing.expect((features.flags & feature_seat) != 0);
    try std.testing.expect((features.flags & feature_xdg_shell) != 0);
    try std.testing.expect((features.flags & feature_linux_dmabuf) != 0);

    features.size = @offsetOf(WayembedFeatures, "flags");
    features.version = abi_version;
    try std.testing.expect(!wayembed_get_features(&features));

    features.size = @sizeOf(WayembedFeatures);
    features.version = abi_version + 1;
    try std.testing.expect(!wayembed_get_features(&features));
}

test "adapter handoff initialization validates inputs" {
    var handoff: WayembedAdapterHandoff = .{
        .size = @sizeOf(WayembedAdapterHandoff),
        .version = 0,
        .format = adapter_format_unknown,
        .server = null,
        .display = null,
        .format_token = null,
        .format_userdata = null,
    };

    try std.testing.expect(!wayembed_adapter_handoff_init(null, adapter_format_clap, null, null));
    try std.testing.expect(!wayembed_adapter_handoff_init(&handoff, adapter_format_unknown, null, null));
    try std.testing.expect(!wayembed_adapter_handoff_init(&handoff, adapter_format_clap, null, null));

    const server: *server_mod.Server = @ptrFromInt(@alignOf(server_mod.Server));
    const display: *wlc.wl_display = @ptrFromInt(1);
    try std.testing.expect(wayembed_adapter_handoff_init(&handoff, adapter_format_clap, server, display));
    try std.testing.expect(wayembed_adapter_handoff_validate(&handoff));
    try std.testing.expectEqual(adapter_abi_version, handoff.version);
    try std.testing.expectEqual(adapter_format_clap, handoff.format);

    handoff.format_token = adapter_lv2_token;
    try std.testing.expect(!wayembed_adapter_handoff_validate(&handoff));

    try std.testing.expect(wayembed_adapter_handoff_init(&handoff, adapter_format_lv2, server, display));
    try std.testing.expect(wayembed_adapter_handoff_validate(&handoff));
    try std.testing.expectEqual(adapter_format_lv2, handoff.format);

    handoff.format_token = adapter_clap_token;
    try std.testing.expect(!wayembed_adapter_handoff_validate(&handoff));

    try std.testing.expect(wayembed_adapter_handoff_init(&handoff, adapter_format_vst3, server, display));
    try std.testing.expect(wayembed_adapter_handoff_validate(&handoff));
    try std.testing.expectEqual(adapter_format_vst3, handoff.format);

    handoff.version = adapter_abi_version + 1;
    try std.testing.expect(!wayembed_adapter_handoff_validate(&handoff));
}

test "adapter fd handoff initialization validates inputs" {
    var handoff: WayembedAdapterFdHandoff = .{
        .size = @sizeOf(WayembedAdapterFdHandoff),
        .version = 0,
        .format = adapter_format_unknown,
        .server = null,
        .client = null,
        .client_fd = -1,
        .format_token = null,
        .format_userdata = null,
    };

    try std.testing.expect(!wayembed_adapter_fd_handoff_init(null, adapter_format_clap, null, null, -1));
    try std.testing.expect(!wayembed_adapter_fd_handoff_init(&handoff, adapter_format_unknown, null, null, -1));
    try std.testing.expect(!wayembed_adapter_fd_handoff_init(&handoff, adapter_format_clap, null, null, -1));

    const server: *server_mod.Server = @ptrFromInt(@alignOf(server_mod.Server));
    const client: *wayembed_client = @ptrFromInt(@alignOf(server_mod.ClientHandle));
    try std.testing.expect(!wayembed_adapter_fd_handoff_init(&handoff, adapter_format_clap, server, client, -1));
    try std.testing.expect(wayembed_adapter_fd_handoff_init(&handoff, adapter_format_clap, server, client, 42));
    try std.testing.expect(wayembed_adapter_fd_handoff_validate(&handoff));
    try std.testing.expectEqual(adapter_abi_version, handoff.version);
    try std.testing.expectEqual(adapter_format_clap, handoff.format);
    try std.testing.expectEqual(@as(i32, 42), handoff.client_fd);

    handoff.format_token = adapter_lv2_token;
    try std.testing.expect(!wayembed_adapter_fd_handoff_validate(&handoff));

    try std.testing.expect(wayembed_adapter_fd_handoff_init(&handoff, adapter_format_lv2, server, client, 42));
    try std.testing.expect(wayembed_adapter_fd_handoff_validate(&handoff));
    try std.testing.expectEqual(adapter_format_lv2, handoff.format);

    try std.testing.expect(wayembed_adapter_fd_handoff_init(&handoff, adapter_format_vst3, server, client, 42));
    try std.testing.expect(wayembed_adapter_fd_handoff_validate(&handoff));
    try std.testing.expectEqual(adapter_format_vst3, handoff.format);

    handoff.version = adapter_abi_version + 1;
    try std.testing.expect(!wayembed_adapter_fd_handoff_validate(&handoff));
}

test "adapter resize validation rejects invalid dimensions" {
    var resize: WayembedAdapterResize = .{
        .size = @sizeOf(WayembedAdapterResize),
        .version = adapter_abi_version,
        .width = 320,
        .height = 200,
        .scale = 1,
    };
    try std.testing.expect(wayembed_adapter_resize_validate(&resize));
    resize.width = -1;
    try std.testing.expect(!wayembed_adapter_resize_validate(&resize));
    resize.width = 320;
    resize.scale = 0;
    try std.testing.expect(!wayembed_adapter_resize_validate(&resize));
    resize.scale = std.math.inf(f64);
    try std.testing.expect(!wayembed_adapter_resize_validate(&resize));
    resize.scale = std.math.nan(f64);
    try std.testing.expect(!wayembed_adapter_resize_validate(&resize));
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
    const opaque_snapshot: *const wayembed_snapshot = @ptrCast(@constCast(&snapshot_handle));

    var counts: WayembedSnapshotCounts = .{
        .size = @sizeOf(WayembedSnapshotCounts),
        .version = abi_version,
        .clients = 0,
        .resources = 0,
        .surfaces = 0,
        .buffers = 0,
        .embeds = 0,
        .outputs = 0,
    };
    try std.testing.expect(wayembed_snapshot_get_counts(opaque_snapshot, &counts));
    try std.testing.expectEqual(@as(usize, 1), counts.clients);
    try std.testing.expectEqual(@as(usize, 6), counts.outputs);

    counts.size = @offsetOf(WayembedSnapshotCounts, "outputs");
    counts.version = abi_version;
    try std.testing.expect(!wayembed_snapshot_get_counts(opaque_snapshot, &counts));

    counts.size = @sizeOf(WayembedSnapshotCounts);
    counts.version = abi_version + 1;
    try std.testing.expect(!wayembed_snapshot_get_counts(opaque_snapshot, &counts));
}

test "host interface normalization accepts older append-only sizes" {
    var iface = emptyHostInterface();
    iface.size = @offsetOf(WayembedHostInterface, "on_protocol_error");
    const normalized = normalizeHostInterface(&iface).?;
    try std.testing.expectEqual(@sizeOf(WayembedHostInterface), normalized.size);
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
    iface.size = @offsetOf(WayembedHostInterface, "on_embed_mapped");
    const normalized = normalizeHostInterface(&iface).?;
    try std.testing.expect(normalized.on_protocol_error == null);
    try std.testing.expect(normalized.on_embed_mapped == null);
    try std.testing.expect(normalized.on_embed_resized == null);
    try std.testing.expect(normalized.on_embed_destroyed == null);
    try std.testing.expect(normalized.get_output_info == null);
}

test "host interface normalization accepts pre-output-info sizes" {
    var iface = emptyHostInterface();
    iface.size = @offsetOf(WayembedHostInterface, "get_output_info");
    const normalized = normalizeHostInterface(&iface).?;
    try std.testing.expect(normalized.get_output_info == null);
}

test "host interface normalization rejects too-small structs" {
    var iface = emptyHostInterface();
    iface.size = minimum_host_interface_size - 1;
    try std.testing.expect(normalizeHostInterface(&iface) == null);
}
