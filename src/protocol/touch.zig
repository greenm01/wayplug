//! Delegate for wl_touch. Forwards touch events from the host seat and
//! translates embedded-child touch coordinates.

const std = @import("std");
const runtime = @import("runtime.zig");
const wlc = @import("../wayland/client.zig");
const wlp = @import("../wayland/protocols.zig");
const wls = @import("../wayland/server.zig");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn shouldForwardShapeOrientation(resource_version: c_int, tracked: bool) bool {
    return tracked and resource_version >= wls.c.WL_TOUCH_SHAPE_SINCE_VERSION;
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);

    return struct {
        pub const impl = wls.c.struct_wl_touch_interface{
            .release = touchRelease,
        };

        pub const listener = wlc.c.struct_wl_touch_listener{
            .down = touchDown,
            .up = touchUp,
            .motion = touchMotion,
            .frame = touchFrame,
            .cancel = touchCancel,
            .shape = touchShape,
            .orientation = touchOrientation,
        };

        fn touchRelease(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (H.proxyAs(wlp.wl_touch, data.upstream_proxy)) |touch| {
                    if (resourceVersionAtLeast(data.wl_resource, wls.c.WL_TOUCH_RELEASE_SINCE_VERSION)) {
                        wlc.c.wl_touch_release(touch);
                    } else {
                        wlc.c.wl_touch_destroy(touch);
                    }
                    data.upstream_proxy = null;
                }
            }
            H.resourceRelease(null, resource);
        }

        fn touchDown(
            userdata: ?*anyopaque,
            _: ?*wlp.wl_touch,
            serial: u32,
            time: u32,
            surface: ?*wlp.wl_surface,
            id: i32,
            x: wlc.c.wl_fixed_t,
            y: wlc.c.wl_fixed_t,
        ) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            const upstream_surface = surface orelse return;
            const plugin_surface = data.server.surfaceResourceForUpstreamSurface(upstream_surface) orelse return;
            data.touch_points.put(data.server.allocator, id, upstream_surface) catch return;
            const translated = data.server.translatePointerCoords(data.client_id, upstream_surface, x, y);
            wls.c.wl_touch_send_down(data.wl_resource, serial, time, plugin_surface, id, translated.x, translated.y);
        }

        fn touchUp(
            userdata: ?*anyopaque,
            _: ?*wlp.wl_touch,
            serial: u32,
            time: u32,
            id: i32,
        ) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            if (data.touch_points.get(id) == null) return;
            wls.c.wl_touch_send_up(data.wl_resource, serial, time, id);
            _ = data.touch_points.swapRemove(id);
        }

        fn touchMotion(
            userdata: ?*anyopaque,
            _: ?*wlp.wl_touch,
            time: u32,
            id: i32,
            x: wlc.c.wl_fixed_t,
            y: wlc.c.wl_fixed_t,
        ) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            const upstream_surface = data.touch_points.get(id) orelse return;
            const translated = data.server.translatePointerCoords(data.client_id, upstream_surface, x, y);
            wls.c.wl_touch_send_motion(data.wl_resource, time, id, translated.x, translated.y);
        }

        fn touchFrame(userdata: ?*anyopaque, _: ?*wlp.wl_touch) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            wls.c.wl_touch_send_frame(data.wl_resource);
        }

        fn touchCancel(userdata: ?*anyopaque, _: ?*wlp.wl_touch) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            wls.c.wl_touch_send_cancel(data.wl_resource);
            data.touch_points.clearRetainingCapacity();
        }

        fn touchShape(
            userdata: ?*anyopaque,
            _: ?*wlp.wl_touch,
            id: i32,
            major: wlc.c.wl_fixed_t,
            minor: wlc.c.wl_fixed_t,
        ) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            if (!shouldForwardShapeOrientation(
                wls.c.wl_resource_get_version(data.wl_resource),
                data.touch_points.get(id) != null,
            )) return;
            wls.c.wl_touch_send_shape(data.wl_resource, id, major, minor);
        }

        fn touchOrientation(
            userdata: ?*anyopaque,
            _: ?*wlp.wl_touch,
            id: i32,
            orientation: wlc.c.wl_fixed_t,
        ) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            if (!shouldForwardShapeOrientation(
                wls.c.wl_resource_get_version(data.wl_resource),
                data.touch_points.get(id) != null,
            )) return;
            wls.c.wl_touch_send_orientation(data.wl_resource, id, orientation);
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

test "shape and orientation require touch v6 and tracked id" {
    try std.testing.expect(!shouldForwardShapeOrientation(5, true));
    try std.testing.expect(!shouldForwardShapeOrientation(6, false));
    try std.testing.expect(shouldForwardShapeOrientation(6, true));
}

test "compiles" {
    _ = create();
}
