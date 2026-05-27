//! Wayland client-side C bindings. The host hands these pointers across
//! the C ABI, and protocol delegates use the generated inline helpers to
//! forward upstream requests.

pub const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("wayland-client-protocol.h");
    @cInclude("xdg-shell-client-protocol.h");
});

pub const wl_display = c.struct_wl_display;
pub const wl_proxy = c.struct_wl_proxy;
pub const wl_event_queue = c.struct_wl_event_queue;

test "opaque types are declared" {
    const std = @import("std");
    try std.testing.expect(@sizeOf(?*wl_display) == @sizeOf(usize));
}
