//! Delegate for xdg_positioner. Forwards popup positioning requests.

const std = @import("std");
const runtime = @import("runtime.zig");
const xdgc = @import("../wayland/xdg_client.zig");
const xdgs = @import("../wayland/xdg_server.zig");
const wlc = @import("../wayland/client.zig");
const wls = @import("../wayland/server.zig");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);

    return struct {
        pub const impl = xdgs.c.struct_xdg_positioner_interface{
            .destroy = positionerDestroy,
            .set_size = positionerSetSize,
            .set_anchor_rect = positionerSetAnchorRect,
            .set_anchor = positionerSetAnchor,
            .set_gravity = positionerSetGravity,
            .set_constraint_adjustment = positionerSetConstraintAdjustment,
            .set_offset = positionerSetOffset,
            .set_reactive = positionerSetReactive,
            .set_parent_size = positionerSetParentSize,
            .set_parent_configure = positionerSetParentConfigure,
        };

        fn positionerDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (H.proxyAs(xdgc.xdg_positioner, data.upstream_proxy)) |positioner| {
                    xdgc.c.xdg_positioner_destroy(positioner);
                    data.upstream_proxy = null;
                }
            }
            H.resourceRelease(null, resource);
        }

        fn positionerSetSize(_: ?*wls.wl_client, resource: ?*wls.wl_resource, width: i32, height: i32) callconv(.c) void {
            const positioner = H.resourceProxyAs(xdgc.xdg_positioner, resource) orelse return;
            xdgc.c.xdg_positioner_set_size(positioner, width, height);
        }

        fn positionerSetAnchorRect(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32, width: i32, height: i32) callconv(.c) void {
            const positioner = H.resourceProxyAs(xdgc.xdg_positioner, resource) orelse return;
            xdgc.c.xdg_positioner_set_anchor_rect(positioner, x, y, width, height);
        }

        fn positionerSetAnchor(_: ?*wls.wl_client, resource: ?*wls.wl_resource, anchor: u32) callconv(.c) void {
            const positioner = H.resourceProxyAs(xdgc.xdg_positioner, resource) orelse return;
            xdgc.c.xdg_positioner_set_anchor(positioner, anchor);
        }

        fn positionerSetGravity(_: ?*wls.wl_client, resource: ?*wls.wl_resource, gravity: u32) callconv(.c) void {
            const positioner = H.resourceProxyAs(xdgc.xdg_positioner, resource) orelse return;
            xdgc.c.xdg_positioner_set_gravity(positioner, gravity);
        }

        fn positionerSetConstraintAdjustment(_: ?*wls.wl_client, resource: ?*wls.wl_resource, adjustment: u32) callconv(.c) void {
            const positioner = H.resourceProxyAs(xdgc.xdg_positioner, resource) orelse return;
            xdgc.c.xdg_positioner_set_constraint_adjustment(positioner, adjustment);
        }

        fn positionerSetOffset(_: ?*wls.wl_client, resource: ?*wls.wl_resource, x: i32, y: i32) callconv(.c) void {
            const positioner = H.resourceProxyAs(xdgc.xdg_positioner, resource) orelse return;
            xdgc.c.xdg_positioner_set_offset(positioner, x, y);
        }

        fn positionerSetReactive(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            const positioner = H.resourceProxyAs(xdgc.xdg_positioner, resource) orelse return;
            xdgc.c.xdg_positioner_set_reactive(positioner);
        }

        fn positionerSetParentSize(_: ?*wls.wl_client, resource: ?*wls.wl_resource, width: i32, height: i32) callconv(.c) void {
            const positioner = H.resourceProxyAs(xdgc.xdg_positioner, resource) orelse return;
            xdgc.c.xdg_positioner_set_parent_size(positioner, width, height);
        }

        fn positionerSetParentConfigure(_: ?*wls.wl_client, resource: ?*wls.wl_resource, serial: u32) callconv(.c) void {
            const positioner = H.resourceProxyAs(xdgc.xdg_positioner, resource) orelse return;
            xdgc.c.xdg_positioner_set_parent_configure(positioner, serial);
        }
    };
}

test "compiles" {
    _ = create();
}
