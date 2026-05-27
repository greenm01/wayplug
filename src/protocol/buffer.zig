//! Delegate for wl_buffer. Forwards buffer-release events from the
//! upstream proxy back to the plugin resource.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
