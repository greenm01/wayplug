//! Internal wrapper around the host-provided callback table.
//!
//! Engine and protocol code call through this wrapper instead of
//! reaching into the C ABI struct directly. Null function pointers in
//! the host interface are treated as no-ops per
//! docs/architecture.md § Host Notifications.

const std = @import("std");
const c_api = @import("c_api.zig");
const wlc = @import("wayland/client.zig");
const wls = @import("wayland/server.zig");
const wlp = @import("wayland/protocols.zig");

pub const default_seat_name = "wayembed-seat";
pub const default_seat_capabilities: u32 = @intCast(wls.c.WL_SEAT_CAPABILITY_POINTER);
pub const supported_seat_capabilities: u32 =
    @as(u32, @intCast(wls.c.WL_SEAT_CAPABILITY_POINTER)) |
    @as(u32, @intCast(wls.c.WL_SEAT_CAPABILITY_KEYBOARD)) |
    @as(u32, @intCast(wls.c.WL_SEAT_CAPABILITY_TOUCH));
pub const default_output_make: [*:0]const u8 = "wayembed";
pub const default_output_model: [*:0]const u8 = "delegated-output";
pub const default_output_name: [*:0]const u8 = "wayembed-0";
pub const default_output_description: [*:0]const u8 = "wayembed delegated output";

pub const Host = struct {
    iface: *const c_api.WayembedHostInterface,

    pub fn init(iface: *const c_api.WayembedHostInterface) Host {
        return .{ .iface = iface };
    }

    pub fn getCompositor(self: Host) ?*wlp.wl_compositor {
        const f = self.iface.get_compositor orelse return null;
        return f(self.iface.userdata);
    }

    pub fn getSubcompositor(self: Host) ?*wlp.wl_subcompositor {
        const f = self.iface.get_subcompositor orelse return null;
        return f(self.iface.userdata);
    }

    pub fn getShm(self: Host) ?*wlp.wl_shm {
        const f = self.iface.get_shm orelse return null;
        return f(self.iface.userdata);
    }

    pub fn getSeat(self: Host) ?*wlp.wl_seat {
        const f = self.iface.get_seat orelse return null;
        return f(self.iface.userdata);
    }

    pub fn getSeatCapabilities(self: Host) u32 {
        const caps = if (self.iface.get_seat_capabilities) |f|
            f(self.iface.userdata)
        else
            default_seat_capabilities;
        return caps & supported_seat_capabilities;
    }

    pub fn getSeatName(self: Host) [*c]const u8 {
        const f = self.iface.get_seat_name orelse return default_seat_name;
        return f(self.iface.userdata) orelse default_seat_name;
    }

    pub fn getXdgWmBase(self: Host) ?*wlp.xdg_wm_base {
        const f = self.iface.get_xdg_wm_base orelse return null;
        return f(self.iface.userdata);
    }

    pub fn getOutputInfo(self: Host) ?c_api.WayembedOutputInfo {
        const f = self.iface.get_output_info orelse return null;
        var info = defaultOutputInfo();
        if (!f(self.iface.userdata, &info)) return null;
        sanitizeOutputInfo(&info);
        return info;
    }

    pub fn getDmabuf(self: Host) ?*wlp.zwp_linux_dmabuf_v1 {
        const f = self.iface.get_dmabuf orelse return null;
        return f(self.iface.userdata);
    }

    pub fn getSubsurfaceOffset(
        self: Host,
        x: *i32,
        y: *i32,
        display: *wlc.wl_display,
        parent: *wlp.wl_surface,
        child: *wlp.wl_surface,
    ) bool {
        const f = self.iface.get_subsurface_offset orelse return false;
        return f(self.iface.userdata, x, y, display, parent, child);
    }

    pub fn onClientConnected(self: Host, client: ?*c_api.wayembed_client) void {
        if (self.iface.on_client_connected) |f| f(self.iface.userdata, client);
    }

    pub fn onSurfaceCreated(
        self: Host,
        client: ?*c_api.wayembed_client,
        plugin_child_surface: ?*wlp.wl_surface,
    ) void {
        if (self.iface.on_surface_created) |f| {
            f(self.iface.userdata, client, plugin_child_surface);
        }
    }

    pub fn onClientClosed(self: Host, client: ?*c_api.wayembed_client) void {
        if (self.iface.on_client_closed) |f| f(self.iface.userdata, client);
    }

    pub fn onProtocolError(self: Host, client: ?*c_api.wayembed_client, code: u32) void {
        if (self.iface.on_protocol_error) |f| f(self.iface.userdata, client, code);
    }

    pub fn onEmbedMapped(self: Host, embed_id: u32) void {
        if (self.iface.on_embed_mapped) |f| f(self.iface.userdata, embed_id);
    }

    pub fn onEmbedResized(self: Host, embed_id: u32, width: i32, height: i32) void {
        if (self.iface.on_embed_resized) |f| f(self.iface.userdata, embed_id, width, height);
    }

    pub fn onEmbedDestroyed(self: Host, embed_id: u32) void {
        if (self.iface.on_embed_destroyed) |f| f(self.iface.userdata, embed_id);
    }
};

pub fn defaultOutputInfo() c_api.WayembedOutputInfo {
    return .{
        .size = @sizeOf(c_api.WayembedOutputInfo),
        .version = c_api.abi_version,
        .x = 0,
        .y = 0,
        .physical_width = 0,
        .physical_height = 0,
        .subpixel = @intCast(wls.c.WL_OUTPUT_SUBPIXEL_UNKNOWN),
        .make = default_output_make,
        .model = default_output_model,
        .transform = @intCast(wls.c.WL_OUTPUT_TRANSFORM_NORMAL),
        .mode_flags = @intCast(wls.c.WL_OUTPUT_MODE_CURRENT),
        .mode_width = 1,
        .mode_height = 1,
        .mode_refresh = 0,
        .scale = 1,
        .name = default_output_name,
        .description = default_output_description,
    };
}

fn sanitizeOutputInfo(info: *c_api.WayembedOutputInfo) void {
    info.size = @sizeOf(c_api.WayembedOutputInfo);
    info.version = c_api.abi_version;
    if (info.make == null) info.make = default_output_make;
    if (info.model == null) info.model = default_output_model;
    if (info.name == null) info.name = default_output_name;
    if (info.description == null) info.description = default_output_description;
    if (info.scale <= 0) info.scale = 1;
    if (info.mode_width <= 0) info.mode_width = 1;
    if (info.mode_height <= 0) info.mode_height = 1;
    if (info.mode_flags == 0) info.mode_flags = @intCast(wls.c.WL_OUTPUT_MODE_CURRENT);
}

// ===== production code above =====

test "Host wraps a null-callback interface as no-op" {
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
    const h = Host.init(&iface);
    try std.testing.expect(h.getCompositor() == null);
    try std.testing.expectEqual(default_seat_capabilities, h.getSeatCapabilities());
    try std.testing.expectEqualStrings(default_seat_name, std.mem.span(h.getSeatName()));
    h.onClientConnected(null); // must not crash
    h.onEmbedMapped(1); // must not crash
}

fn noisySeatCapabilities(_: ?*anyopaque) callconv(.c) u32 {
    return @as(u32, @intCast(wls.c.WL_SEAT_CAPABILITY_POINTER)) |
        @as(u32, @intCast(wls.c.WL_SEAT_CAPABILITY_KEYBOARD)) |
        @as(u32, @intCast(wls.c.WL_SEAT_CAPABILITY_TOUCH));
}

test "Host masks seat capabilities to supported devices" {
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
        .get_seat_capabilities = noisySeatCapabilities,
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
    const h = Host.init(&iface);
    try std.testing.expectEqual(supported_seat_capabilities, h.getSeatCapabilities());
}
