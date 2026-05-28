//! Generated stable Linux dmabuf server-side C binding aliases.

pub const c = @import("server.zig").c;

pub const zwp_linux_dmabuf_v1 = c.struct_zwp_linux_dmabuf_v1;
pub const zwp_linux_buffer_params_v1 = c.struct_zwp_linux_buffer_params_v1;
pub const zwp_linux_dmabuf_feedback_v1 = c.struct_zwp_linux_dmabuf_feedback_v1;

test "opaque types are declared" {
    const std = @import("std");
    try std.testing.expect(@sizeOf(?*zwp_linux_dmabuf_v1) == @sizeOf(usize));
}
