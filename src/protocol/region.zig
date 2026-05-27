//! Delegate for wl_region. Forwards add/subtract requests to the
//! upstream region proxy.

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
        pub const impl = wls.c.struct_wl_region_interface{
            .destroy = regionDestroy,
            .add = regionAdd,
            .subtract = regionSubtract,
        };

        fn regionDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (H.proxyAs(wlp.wl_region, data.upstream_proxy)) |region| {
                    wlc.c.wl_region_destroy(region);
                    data.upstream_proxy = null;
                }
            }
            H.resourceRelease(null, resource);
        }

        fn regionAdd(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
            const region = H.resourceProxyAs(wlp.wl_region, resource) orelse return;
            wlc.c.wl_region_add(region, x, y, width, height);
        }

        fn regionSubtract(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
            const region = H.resourceProxyAs(wlp.wl_region, resource) orelse return;
            wlc.c.wl_region_subtract(region, x, y, width, height);
        }
    };
}

test "compiles" {
    _ = create();
}
