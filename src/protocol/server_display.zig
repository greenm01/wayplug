//! Local wl_display server stub. Hosts the per-client connection
//! endpoints created by `wayembed_server_open_client_display`.

const std = @import("std");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

test "compiles" {
    _ = create();
}
