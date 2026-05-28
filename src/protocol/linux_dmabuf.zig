//! Delegate for zwp_linux_dmabuf_v1. Advertises the host-provided dmabuf
//! factory and forwards buffer-param creation.

const std = @import("std");
const params_protocol = @import("linux_buffer_params.zig");
const runtime = @import("runtime.zig");
const dmabufc = @import("../wayland/dmabuf_client.zig");
const dmabufs = @import("../wayland/dmabuf_server.zig");
const wlp = @import("../wayland/protocols.zig");
const wls = @import("../wayland/server.zig");

pub const max_version = 3;

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);
    const params_bindings = params_protocol.Bindings(Server, ResourceData);

    return struct {
        pub const impl = dmabufs.c.struct_zwp_linux_dmabuf_v1_interface{
            .destroy = H.resourceRelease,
            .create_params = dmabufCreateParams,
            .get_default_feedback = null,
            .get_surface_feedback = null,
        };

        pub const listener = dmabufc.c.struct_zwp_linux_dmabuf_v1_listener{
            .format = dmabufFormat,
            .modifier = dmabufModifier,
        };

        fn dmabufCreateParams(client: ?*wls.wl_client, resource: ?*wls.wl_resource, params_id: u32) callconv(.c) void {
            const data = H.dataForResource(resource) orelse return;
            const dmabuf = H.resourceProxyAs(wlp.zwp_linux_dmabuf_v1, resource) orelse return;
            const params = dmabufc.c.zwp_linux_dmabuf_v1_create_params(dmabuf) orelse return;
            const wl_client = client orelse return;
            const params_resource = data.server.createResource(
                wl_client,
                .linux_buffer_params,
                &dmabufs.c.zwp_linux_buffer_params_v1_interface,
                resourceVersion(resource),
                params_id,
                @ptrCast(&params_bindings.impl),
                @ptrCast(params),
            ) orelse return;
            const params_data = H.dataForResource(params_resource) orelse return;
            _ = dmabufc.c.zwp_linux_buffer_params_v1_add_listener(params, &params_bindings.listener, params_data);
        }

        fn dmabufFormat(userdata: ?*anyopaque, _: ?*wlp.zwp_linux_dmabuf_v1, format: u32) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            dmabufs.c.zwp_linux_dmabuf_v1_send_format(data.wl_resource, format);
        }

        fn dmabufModifier(
            userdata: ?*anyopaque,
            _: ?*wlp.zwp_linux_dmabuf_v1,
            format: u32,
            modifier_hi: u32,
            modifier_lo: u32,
        ) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            dmabufs.c.zwp_linux_dmabuf_v1_send_modifier(data.wl_resource, format, modifier_hi, modifier_lo);
        }

        fn dataFromListener(userdata: ?*anyopaque) ?*ResourceData {
            const ptr = userdata orelse return null;
            return @ptrCast(@alignCast(ptr));
        }

        fn resourceVersion(resource: ?*wls.wl_resource) u32 {
            const r = resource orelse return 1;
            return @intCast(wls.c.wl_resource_get_version(r));
        }
    };
}

test "compiles" {
    _ = create();
}
