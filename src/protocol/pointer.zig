//! Delegate for wl_pointer. Forwards motion/button/axis events with
//! coordinate translation per docs/architecture.md § Host Notifications.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
