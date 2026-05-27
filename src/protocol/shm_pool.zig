//! Delegate for wl_shm_pool. Owns the fd handoff for plugin-supplied
//! shared-memory buffers.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
