//! Delegate for xdg_popup. Forwards popup requests and events.

const std = @import("std");
const runtime = @import("runtime.zig");
const xdgc = @import("../wayland/xdg_client.zig");
const xdgs = @import("../wayland/xdg_server.zig");
const wlp = @import("../wayland/protocols.zig");
const wls = @import("../wayland/server.zig");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);

    return struct {
        pub const impl = xdgs.c.struct_xdg_popup_interface{
            .destroy = popupDestroy,
            .grab = popupGrab,
            .reposition = popupReposition,
        };

        pub const listener = xdgc.c.struct_xdg_popup_listener{
            .configure = popupConfigure,
            .popup_done = popupDone,
            .repositioned = popupRepositioned,
        };

        fn popupDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (H.proxyAs(xdgc.xdg_popup, data.upstream_proxy)) |popup| {
                    xdgc.c.xdg_popup_destroy(popup);
                    data.upstream_proxy = null;
                }
            }
            H.resourceRelease(null, resource);
        }

        fn popupGrab(_: ?*wls.wl_client, resource: ?*wls.wl_resource, seat_resource: ?*wls.wl_resource, serial: u32) callconv(.c) void {
            const popup = H.resourceProxyAs(xdgc.xdg_popup, resource) orelse return;
            const seat = H.resourceProxyAs(wlp.wl_seat, seat_resource) orelse return;
            xdgc.c.xdg_popup_grab(popup, seat, serial);
        }

        fn popupReposition(_: ?*wls.wl_client, resource: ?*wls.wl_resource, positioner_resource: ?*wls.wl_resource, token: u32) callconv(.c) void {
            const popup = H.resourceProxyAs(xdgc.xdg_popup, resource) orelse return;
            const positioner = H.resourceProxyAs(xdgc.xdg_positioner, positioner_resource) orelse return;
            xdgc.c.xdg_popup_reposition(popup, positioner, token);
        }

        fn popupConfigure(userdata: ?*anyopaque, _: ?*xdgc.xdg_popup, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            xdgs.c.xdg_popup_send_configure(data.wl_resource, x, y, width, height);
        }

        fn popupDone(userdata: ?*anyopaque, _: ?*xdgc.xdg_popup) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            xdgs.c.xdg_popup_send_popup_done(data.wl_resource);
        }

        fn popupRepositioned(userdata: ?*anyopaque, _: ?*xdgc.xdg_popup, token: u32) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            if (resourceVersionAtLeast(data.wl_resource, xdgs.c.XDG_POPUP_REPOSITIONED_SINCE_VERSION)) {
                xdgs.c.xdg_popup_send_repositioned(data.wl_resource, token);
            }
        }

        fn dataFromListener(userdata: ?*anyopaque) ?*ResourceData {
            const ptr = userdata orelse return null;
            return @ptrCast(@alignCast(ptr));
        }

        fn resourceVersionAtLeast(resource: *wls.wl_resource, version: c_int) bool {
            return wls.c.wl_resource_get_version(resource) >= version;
        }
    };
}

test "compiles" {
    _ = create();
}
