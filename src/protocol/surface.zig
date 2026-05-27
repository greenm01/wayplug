//! Delegate for wl_surface. Owns the hot-path forwarding for
//! attach/damage/commit per docs/architecture.md § What Stays Direct.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
