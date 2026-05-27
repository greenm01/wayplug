//! wl_registry bind dispatch. Advertises only the globals the host
//! supplies through `wayplug_host_interface`.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
