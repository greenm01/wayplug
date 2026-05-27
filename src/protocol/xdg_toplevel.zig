//! Delegate for xdg_toplevel. Forwards toplevel requests and events.

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
        pub const impl = xdgs.c.struct_xdg_toplevel_interface{
            .destroy = toplevelDestroy,
            .set_parent = toplevelSetParent,
            .set_title = toplevelSetTitle,
            .set_app_id = toplevelSetAppId,
            .show_window_menu = toplevelShowWindowMenu,
            .move = toplevelMove,
            .resize = toplevelResize,
            .set_max_size = toplevelSetMaxSize,
            .set_min_size = toplevelSetMinSize,
            .set_maximized = toplevelSetMaximized,
            .unset_maximized = toplevelUnsetMaximized,
            .set_fullscreen = toplevelSetFullscreen,
            .unset_fullscreen = toplevelUnsetFullscreen,
            .set_minimized = toplevelSetMinimized,
        };

        pub const listener = xdgc.c.struct_xdg_toplevel_listener{
            .configure = toplevelConfigure,
            .close = toplevelClose,
            .configure_bounds = toplevelConfigureBounds,
            .wm_capabilities = toplevelWmCapabilities,
        };

        fn toplevelDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (H.proxyAs(xdgc.xdg_toplevel, data.upstream_proxy)) |toplevel| {
                    xdgc.c.xdg_toplevel_destroy(toplevel);
                    data.upstream_proxy = null;
                }
            }
            H.resourceRelease(null, resource);
        }

        fn toplevelSetParent(_: ?*wls.wl_client, resource: ?*wls.wl_resource, parent_resource: ?*wls.wl_resource) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            const parent = H.resourceProxyAs(xdgc.xdg_toplevel, parent_resource);
            xdgc.c.xdg_toplevel_set_parent(toplevel, parent);
        }

        fn toplevelSetTitle(_: ?*wls.wl_client, resource: ?*wls.wl_resource, title: [*c]const u8) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            xdgc.c.xdg_toplevel_set_title(toplevel, title);
        }

        fn toplevelSetAppId(_: ?*wls.wl_client, resource: ?*wls.wl_resource, app_id: [*c]const u8) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            xdgc.c.xdg_toplevel_set_app_id(toplevel, app_id);
        }

        fn toplevelShowWindowMenu(_: ?*wls.wl_client, resource: ?*wls.wl_resource, seat_resource: ?*wls.wl_resource, serial: u32, x: i32, y: i32) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            const seat = H.resourceProxyAs(wlp.wl_seat, seat_resource) orelse return;
            xdgc.c.xdg_toplevel_show_window_menu(toplevel, seat, serial, x, y);
        }

        fn toplevelMove(_: ?*wls.wl_client, resource: ?*wls.wl_resource, seat_resource: ?*wls.wl_resource, serial: u32) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            const seat = H.resourceProxyAs(wlp.wl_seat, seat_resource) orelse return;
            xdgc.c.xdg_toplevel_move(toplevel, seat, serial);
        }

        fn toplevelResize(_: ?*wls.wl_client, resource: ?*wls.wl_resource, seat_resource: ?*wls.wl_resource, serial: u32, edges: u32) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            const seat = H.resourceProxyAs(wlp.wl_seat, seat_resource) orelse return;
            xdgc.c.xdg_toplevel_resize(toplevel, seat, serial, edges);
        }

        fn toplevelSetMaxSize(_: ?*wls.wl_client, resource: ?*wls.wl_resource, width: i32, height: i32) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            xdgc.c.xdg_toplevel_set_max_size(toplevel, width, height);
        }

        fn toplevelSetMinSize(_: ?*wls.wl_client, resource: ?*wls.wl_resource, width: i32, height: i32) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            xdgc.c.xdg_toplevel_set_min_size(toplevel, width, height);
        }

        fn toplevelSetMaximized(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            xdgc.c.xdg_toplevel_set_maximized(toplevel);
        }

        fn toplevelUnsetMaximized(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            xdgc.c.xdg_toplevel_unset_maximized(toplevel);
        }

        fn toplevelSetFullscreen(_: ?*wls.wl_client, resource: ?*wls.wl_resource, output_resource: ?*wls.wl_resource) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            const output = H.resourceProxyAs(wlp.wl_output, output_resource);
            xdgc.c.xdg_toplevel_set_fullscreen(toplevel, output);
        }

        fn toplevelUnsetFullscreen(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            xdgc.c.xdg_toplevel_unset_fullscreen(toplevel);
        }

        fn toplevelSetMinimized(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            const toplevel = H.resourceProxyAs(xdgc.xdg_toplevel, resource) orelse return;
            xdgc.c.xdg_toplevel_set_minimized(toplevel);
        }

        fn toplevelConfigure(userdata: ?*anyopaque, _: ?*xdgc.xdg_toplevel, width: i32, height: i32, states: [*c]xdgc.c.struct_wl_array) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            xdgs.c.xdg_toplevel_send_configure(data.wl_resource, width, height, @ptrCast(states));
        }

        fn toplevelClose(userdata: ?*anyopaque, _: ?*xdgc.xdg_toplevel) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            xdgs.c.xdg_toplevel_send_close(data.wl_resource);
        }

        fn toplevelConfigureBounds(userdata: ?*anyopaque, _: ?*xdgc.xdg_toplevel, width: i32, height: i32) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            if (resourceVersionAtLeast(data.wl_resource, xdgs.c.XDG_TOPLEVEL_CONFIGURE_BOUNDS_SINCE_VERSION)) {
                xdgs.c.xdg_toplevel_send_configure_bounds(data.wl_resource, width, height);
            }
        }

        fn toplevelWmCapabilities(userdata: ?*anyopaque, _: ?*xdgc.xdg_toplevel, capabilities: [*c]xdgc.c.struct_wl_array) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            if (resourceVersionAtLeast(data.wl_resource, xdgs.c.XDG_TOPLEVEL_WM_CAPABILITIES_SINCE_VERSION)) {
                xdgs.c.xdg_toplevel_send_wm_capabilities(data.wl_resource, @ptrCast(capabilities));
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
