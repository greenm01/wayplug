//! Client-side Wayland protocol object types the host hands across the
//! `wayplug_host_interface` getters.

const wlc = @import("client.zig");

pub const wl_compositor = wlc.c.struct_wl_compositor;
pub const wl_subcompositor = wlc.c.struct_wl_subcompositor;
pub const wl_subsurface = wlc.c.struct_wl_subsurface;
pub const wl_surface = wlc.c.struct_wl_surface;
pub const wl_region = wlc.c.struct_wl_region;
pub const wl_shm = wlc.c.struct_wl_shm;
pub const wl_shm_pool = wlc.c.struct_wl_shm_pool;
pub const wl_buffer = wlc.c.struct_wl_buffer;
pub const wl_callback = wlc.c.struct_wl_callback;
pub const wl_seat = wlc.c.struct_wl_seat;
pub const wl_output = wlc.c.struct_wl_output;

// Phase 2+ protocols stay opaque until their generated bindings land.
pub const xdg_wm_base = opaque {};
pub const zwp_linux_dmabuf_v1 = opaque {};

test "opaque types are declared" {
    const std = @import("std");
    try std.testing.expect(@sizeOf(?*wl_compositor) == @sizeOf(usize));
}
