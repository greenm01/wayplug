//! Delegate for wl_output. Forwards mode/geometry/scale events from the
//! host upstream output.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
