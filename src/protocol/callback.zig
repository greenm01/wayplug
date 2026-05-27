//! Delegate for wl_callback. Owns the done-event forwarding for frame
//! callbacks.

const std = @import("std");
const wlc = @import("../wayland/client.zig");
const wlp = @import("../wayland/protocols.zig");
const wls = @import("../wayland/server.zig");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    _ = Server;

    return struct {
        pub const listener = wlc.c.struct_wl_callback_listener{ .done = callbackDone };

        fn callbackDone(data: ?*anyopaque, _: ?*wlp.wl_callback, callback_data: u32) callconv(.c) void {
            const resource_data: *ResourceData = @ptrCast(@alignCast(data orelse return));
            wls.c.wl_callback_send_done(resource_data.wl_resource, callback_data);
            wls.c.wl_resource_destroy(resource_data.wl_resource);
        }
    };
}

test "compiles" {
    _ = create();
}
