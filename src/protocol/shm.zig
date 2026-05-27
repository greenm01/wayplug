//! Delegate for wl_shm. Forwards format advertisements from the host
//! and creates shm pools on bind.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
