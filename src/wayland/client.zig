//! Opaque Wayland client-side types. No linkage to libwayland yet; the
//! host hands these in as opaque pointers across the C ABI.

pub const wl_display = opaque {};
pub const wl_proxy = opaque {};
pub const wl_event_queue = opaque {};

test "opaque types are declared" {
    const std = @import("std");
    try std.testing.expect(@sizeOf(?*wl_display) == @sizeOf(usize));
}
