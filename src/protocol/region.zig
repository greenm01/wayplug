//! Delegate for wl_region. Forwards add/subtract requests to the
//! upstream region proxy.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
