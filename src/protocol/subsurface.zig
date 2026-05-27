//! Delegate for wl_subsurface. Owns positioning forwarding for the
//! embedded child surface.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
