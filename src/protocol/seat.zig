//! Delegate for wl_seat. Forwards capabilities and name from the host
//! upstream seat; dispatches get_pointer/get_keyboard/get_touch to the
//! per-device delegates.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
