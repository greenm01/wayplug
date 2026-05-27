//! Delegate for wl_subcompositor. Creates wl_subsurface resources and
//! triggers embedAttachChild on the engine.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
