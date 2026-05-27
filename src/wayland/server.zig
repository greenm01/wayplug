//! Opaque Wayland server-side types used by the local delegated server.
//! No linkage to libwayland yet.

pub const wl_client = opaque {};
pub const wl_resource = opaque {};
pub const wl_global = opaque {};

test "opaque types are declared" {
    const std = @import("std");
    try std.testing.expect(@sizeOf(?*wl_client) == @sizeOf(usize));
}
