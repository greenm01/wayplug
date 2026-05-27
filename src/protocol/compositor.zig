//! Delegate for wl_compositor.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
