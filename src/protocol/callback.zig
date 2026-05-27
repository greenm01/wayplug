//! Delegate for wl_callback. Owns the done-event forwarding for frame
//! callbacks.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
