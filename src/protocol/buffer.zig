//! Delegate for wl_buffer. Forwards buffer-release events from the
//! upstream proxy back to the plugin resource.

const std = @import("std");
const runtime = @import("runtime.zig");
const wlc = @import("../wayland/client.zig");
const wlp = @import("../wayland/protocols.zig");
const wls = @import("../wayland/server.zig");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);

    return struct {
        pub const impl = wls.c.struct_wl_buffer_interface{ .destroy = bufferDestroy };
        pub const listener = wlc.c.struct_wl_buffer_listener{ .release = bufferRelease };

        fn bufferDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (H.proxyAs(wlp.wl_buffer, data.upstream_proxy)) |buffer| {
                    wlc.c.wl_buffer_destroy(buffer);
                    data.upstream_proxy = null;
                }
            }
            H.resourceRelease(null, resource);
        }

        fn bufferRelease(data: ?*anyopaque, _: ?*wlp.wl_buffer) callconv(.c) void {
            const resource_data: *ResourceData = @ptrCast(@alignCast(data orelse return));
            wls.c.wl_buffer_send_release(resource_data.wl_resource);
        }
    };
}

test "compiles" {
    _ = create();
}
