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

pub const Host = struct {
    iface: *const c_api.WayplugHostInterface,

    pub fn init(iface: *const c_api.WayplugHostInterface) Host {
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

    pub fn getXdgWmBase(self: Host) ?*wlp.xdg_wm_base {
        const f = self.iface.get_xdg_wm_base orelse return null;
        return f(self.iface.userdata);
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

    pub fn onClientConnected(self: Host, client: ?*c_api.wayplug_client) void {
        if (self.iface.on_client_connected) |f| f(self.iface.userdata, client);
    }

    pub fn onSurfaceCreated(
        self: Host,
        client: ?*c_api.wayplug_client,
        plugin_child_surface: ?*wlp.wl_surface,
    ) void {
        if (self.iface.on_surface_created) |f| {
            f(self.iface.userdata, client, plugin_child_surface);
        }
    }

    pub fn onClientClosed(self: Host, client: ?*c_api.wayplug_client) void {
        if (self.iface.on_client_closed) |f| f(self.iface.userdata, client);
    }

    pub fn onProtocolError(self: Host, client: ?*c_api.wayplug_client, code: u32) void {
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

// ===== production code above =====

test "Host wraps a null-callback interface as no-op" {
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
        .on_embed_mapped = null,
        .on_embed_resized = null,
        .on_embed_destroyed = null,
    };
    const h = Host.init(&iface);
    try std.testing.expect(h.getCompositor() == null);
    h.onClientConnected(null); // must not crash
    h.onEmbedMapped(1); // must not crash
}
