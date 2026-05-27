//! Delegate for wl_keyboard. Forwards keymap, modifiers, and key events.

const std = @import("std");
const runtime = @import("runtime.zig");
const wlc = @import("../wayland/client.zig");
const wlp = @import("../wayland/protocols.zig");
const wls = @import("../wayland/server.zig");

const sys = @cImport({
    @cInclude("unistd.h");
});

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn normalizeKeyStateForVersion(resource_version: c_int, state: u32) u32 {
    const repeated: u32 = @intCast(wls.c.WL_KEYBOARD_KEY_STATE_REPEATED);
    if (resource_version < wls.c.WL_KEYBOARD_KEY_STATE_REPEATED_SINCE_VERSION and state == repeated) {
        return @intCast(wls.c.WL_KEYBOARD_KEY_STATE_PRESSED);
    }
    return state;
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);

    return struct {
        pub const impl = wls.c.struct_wl_keyboard_interface{
            .release = keyboardRelease,
        };

        pub const listener = wlc.c.struct_wl_keyboard_listener{
            .keymap = keyboardKeymap,
            .enter = keyboardEnter,
            .leave = keyboardLeave,
            .key = keyboardKey,
            .modifiers = keyboardModifiers,
            .repeat_info = keyboardRepeatInfo,
        };

        fn keyboardRelease(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (H.proxyAs(wlp.wl_keyboard, data.upstream_proxy)) |keyboard| {
                    if (resourceVersionAtLeast(data.wl_resource, wls.c.WL_KEYBOARD_RELEASE_SINCE_VERSION)) {
                        wlc.c.wl_keyboard_release(keyboard);
                    } else {
                        wlc.c.wl_keyboard_destroy(keyboard);
                    }
                    data.upstream_proxy = null;
                }
            }
            H.resourceRelease(null, resource);
        }

        fn keyboardKeymap(
            userdata: ?*anyopaque,
            _: ?*wlp.wl_keyboard,
            format: u32,
            fd: i32,
            size: u32,
        ) callconv(.c) void {
            const data = dataFromListener(userdata) orelse {
                _ = sys.close(fd);
                return;
            };
            wls.c.wl_keyboard_send_keymap(data.wl_resource, format, fd, size);
            _ = sys.close(fd);
        }

        fn keyboardEnter(
            userdata: ?*anyopaque,
            _: ?*wlp.wl_keyboard,
            serial: u32,
            surface: ?*wlp.wl_surface,
            keys: [*c]wlc.c.struct_wl_array,
        ) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            const upstream_surface = surface orelse return;
            const plugin_surface = data.server.surfaceResourceForUpstreamSurface(upstream_surface) orelse return;
            wls.c.wl_keyboard_send_enter(data.wl_resource, serial, plugin_surface, @ptrCast(keys));
        }

        fn keyboardLeave(
            userdata: ?*anyopaque,
            _: ?*wlp.wl_keyboard,
            serial: u32,
            surface: ?*wlp.wl_surface,
        ) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            const upstream_surface = surface orelse return;
            const plugin_surface = data.server.surfaceResourceForUpstreamSurface(upstream_surface) orelse return;
            wls.c.wl_keyboard_send_leave(data.wl_resource, serial, plugin_surface);
        }

        fn keyboardKey(
            userdata: ?*anyopaque,
            _: ?*wlp.wl_keyboard,
            serial: u32,
            time: u32,
            key: u32,
            state: u32,
        ) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            const version = wls.c.wl_resource_get_version(data.wl_resource);
            const normalized_state = normalizeKeyStateForVersion(version, state);
            wls.c.wl_keyboard_send_key(data.wl_resource, serial, time, key, normalized_state);
        }

        fn keyboardModifiers(
            userdata: ?*anyopaque,
            _: ?*wlp.wl_keyboard,
            serial: u32,
            mods_depressed: u32,
            mods_latched: u32,
            mods_locked: u32,
            group: u32,
        ) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            wls.c.wl_keyboard_send_modifiers(data.wl_resource, serial, mods_depressed, mods_latched, mods_locked, group);
        }

        fn keyboardRepeatInfo(
            userdata: ?*anyopaque,
            _: ?*wlp.wl_keyboard,
            rate: i32,
            delay: i32,
        ) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            if (resourceVersionAtLeast(data.wl_resource, wls.c.WL_KEYBOARD_REPEAT_INFO_SINCE_VERSION)) {
                wls.c.wl_keyboard_send_repeat_info(data.wl_resource, rate, delay);
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

test "key state repeated downgrades before keyboard v10" {
    try std.testing.expectEqual(
        @as(u32, @intCast(wls.c.WL_KEYBOARD_KEY_STATE_PRESSED)),
        normalizeKeyStateForVersion(9, @intCast(wls.c.WL_KEYBOARD_KEY_STATE_REPEATED)),
    );
    try std.testing.expectEqual(
        @as(u32, @intCast(wls.c.WL_KEYBOARD_KEY_STATE_REPEATED)),
        normalizeKeyStateForVersion(10, @intCast(wls.c.WL_KEYBOARD_KEY_STATE_REPEATED)),
    );
}

test "compiles" {
    _ = create();
}
