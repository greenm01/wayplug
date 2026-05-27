//! Delegate for wl_keyboard. Forwards keymap, modifiers, and key events.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
