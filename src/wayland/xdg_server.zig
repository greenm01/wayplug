//! Generated stable XDG shell server-side C binding aliases.

pub const c = @import("server.zig").c;

pub const xdg_wm_base = c.struct_xdg_wm_base;
pub const xdg_positioner = c.struct_xdg_positioner;
pub const xdg_surface = c.struct_xdg_surface;
pub const xdg_toplevel = c.struct_xdg_toplevel;
pub const xdg_popup = c.struct_xdg_popup;

test "opaque types are declared" {
    const std = @import("std");
    try std.testing.expect(@sizeOf(?*xdg_wm_base) == @sizeOf(usize));
}
