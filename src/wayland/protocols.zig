//! Opaque Wayland protocol-interface types the host hands across the
//! `wayplug_host_interface` getters.

pub const wl_compositor = opaque {};
pub const wl_subcompositor = opaque {};
pub const wl_surface = opaque {};
pub const wl_shm = opaque {};
pub const wl_seat = opaque {};
pub const wl_output = opaque {};
pub const xdg_wm_base = opaque {};
pub const zwp_linux_dmabuf_v1 = opaque {};

test "opaque types are declared" {
    const std = @import("std");
    try std.testing.expect(@sizeOf(?*wl_compositor) == @sizeOf(usize));
}
