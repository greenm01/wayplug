//! Wayland server-side C bindings used by the local delegated server.

pub const c = @cImport({
    @cInclude("wayland-server.h");
    @cInclude("wayland-server-protocol.h");
});

pub const wl_client = c.struct_wl_client;
pub const wl_display = c.struct_wl_display;
pub const wl_event_loop = c.struct_wl_event_loop;
pub const wl_resource = c.struct_wl_resource;
pub const wl_global = c.struct_wl_global;
pub const wl_interface = c.struct_wl_interface;

test "opaque types are declared" {
    const std = @import("std");
    try std.testing.expect(@sizeOf(?*wl_client) == @sizeOf(usize));
}
