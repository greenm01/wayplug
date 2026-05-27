//! Delegate for wl_seat. Pointer and keyboard forwarding are supported;
//! touch is intentionally left for a later protocol item.

const std = @import("std");
const keyboard_protocol = @import("keyboard.zig");
const pointer_protocol = @import("pointer.zig");
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
    const keyboard_bindings = keyboard_protocol.Bindings(Server, ResourceData);
    const pointer_bindings = pointer_protocol.Bindings(Server, ResourceData);

    return struct {
        pub const impl = wls.c.struct_wl_seat_interface{
            .get_pointer = seatGetPointer,
            .get_keyboard = seatGetKeyboard,
            .get_touch = seatGetTouch,
            .release = H.resourceRelease,
        };

        fn seatGetPointer(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32) callconv(.c) void {
            const data = H.dataForResource(resource) orelse return;
            if (!hasCapability(data, wls.c.WL_SEAT_CAPABILITY_POINTER)) {
                postMissingCapability(resource);
                return;
            }
            const seat = H.resourceProxyAs(wlp.wl_seat, resource) orelse return;
            const pointer = wlc.c.wl_seat_get_pointer(seat) orelse return;
            const wl_client = client orelse return;
            const version: u32 = @intCast(wls.c.wl_resource_get_version(data.wl_resource));
            const pointer_resource = data.server.createResource(
                wl_client,
                .pointer,
                &wls.c.wl_pointer_interface,
                version,
                id,
                @ptrCast(&pointer_bindings.impl),
                @ptrCast(pointer),
            ) orelse return;
            const pointer_data = H.dataForResource(pointer_resource) orelse return;
            _ = wlc.c.wl_pointer_add_listener(pointer, &pointer_bindings.listener, pointer_data);
        }

        fn seatGetKeyboard(client: ?*wls.wl_client, resource: ?*wls.wl_resource, id: u32) callconv(.c) void {
            const data = H.dataForResource(resource) orelse return;
            if (!hasCapability(data, wls.c.WL_SEAT_CAPABILITY_KEYBOARD)) {
                postMissingCapability(resource);
                return;
            }
            const seat = H.resourceProxyAs(wlp.wl_seat, resource) orelse return;
            const keyboard = wlc.c.wl_seat_get_keyboard(seat) orelse return;
            const wl_client = client orelse return;
            const version: u32 = @intCast(wls.c.wl_resource_get_version(data.wl_resource));
            const keyboard_resource = data.server.createResource(
                wl_client,
                .keyboard,
                &wls.c.wl_keyboard_interface,
                version,
                id,
                @ptrCast(&keyboard_bindings.impl),
                @ptrCast(keyboard),
            ) orelse return;
            const keyboard_data = H.dataForResource(keyboard_resource) orelse return;
            _ = wlc.c.wl_keyboard_add_listener(keyboard, &keyboard_bindings.listener, keyboard_data);
        }

        fn seatGetTouch(_: ?*wls.wl_client, resource: ?*wls.wl_resource, _: u32) callconv(.c) void {
            postMissingCapability(resource);
        }

        fn postMissingCapability(resource: ?*wls.wl_resource) void {
            const seat_resource = resource orelse return;
            wls.c.wl_resource_post_error(
                seat_resource,
                wls.c.WL_SEAT_ERROR_MISSING_CAPABILITY,
                "wayplug does not expose the requested wl_seat capability",
            );
        }

        fn hasCapability(data: *ResourceData, capability: c_int) bool {
            return (data.server.host.getSeatCapabilities() & @as(u32, @intCast(capability))) != 0;
        }
    };
}

test "compiles" {
    _ = create();
}
