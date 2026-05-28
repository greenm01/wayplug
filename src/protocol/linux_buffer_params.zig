//! Delegate for zwp_linux_buffer_params_v1. Owns dmabuf fd handoff and
//! wl_buffer creation callbacks.

const std = @import("std");
const buffer_protocol = @import("buffer.zig");
const runtime = @import("runtime.zig");
const dmabufc = @import("../wayland/dmabuf_client.zig");
const dmabufs = @import("../wayland/dmabuf_server.zig");
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

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);
    const buffer_bindings = buffer_protocol.Bindings(Server, ResourceData);

    return struct {
        pub const impl = dmabufs.c.struct_zwp_linux_buffer_params_v1_interface{
            .destroy = paramsDestroy,
            .add = paramsAdd,
            .create = paramsCreate,
            .create_immed = paramsCreateImmed,
        };

        pub const listener = dmabufc.c.struct_zwp_linux_buffer_params_v1_listener{
            .created = paramsCreated,
            .failed = paramsFailed,
        };

        fn paramsDestroy(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (H.proxyAs(wlp.zwp_linux_buffer_params_v1, data.upstream_proxy)) |params| {
                    dmabufc.c.zwp_linux_buffer_params_v1_destroy(params);
                    data.upstream_proxy = null;
                }
            }
            H.resourceRelease(null, resource);
        }

        fn paramsAdd(
            _: ?*wls.wl_client,
            resource: ?*wls.wl_resource,
            fd: i32,
            plane_idx: u32,
            offset: u32,
            stride: u32,
            modifier_hi: u32,
            modifier_lo: u32,
        ) callconv(.c) void {
            const params = H.resourceProxyAs(wlp.zwp_linux_buffer_params_v1, resource) orelse {
                _ = sys.close(fd);
                return;
            };
            dmabufc.c.zwp_linux_buffer_params_v1_add(params, fd, plane_idx, offset, stride, modifier_hi, modifier_lo);
            _ = sys.close(fd);
        }

        fn paramsCreate(
            _: ?*wls.wl_client,
            resource: ?*wls.wl_resource,
            width: i32,
            height: i32,
            format: u32,
            flags: u32,
        ) callconv(.c) void {
            const params = H.resourceProxyAs(wlp.zwp_linux_buffer_params_v1, resource) orelse return;
            dmabufc.c.zwp_linux_buffer_params_v1_create(params, width, height, format, flags);
        }

        fn paramsCreateImmed(
            client: ?*wls.wl_client,
            resource: ?*wls.wl_resource,
            buffer_id: u32,
            width: i32,
            height: i32,
            format: u32,
            flags: u32,
        ) callconv(.c) void {
            const data = H.dataForResource(resource) orelse return;
            const params = H.resourceProxyAs(wlp.zwp_linux_buffer_params_v1, resource) orelse return;
            const buffer = dmabufc.c.zwp_linux_buffer_params_v1_create_immed(params, width, height, format, flags) orelse return;
            const wl_client = client orelse return;
            _ = createBufferResource(data, wl_client, buffer_id, buffer);
        }

        fn paramsCreated(userdata: ?*anyopaque, _: ?*wlp.zwp_linux_buffer_params_v1, buffer: ?*wlp.wl_buffer) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            const upstream_buffer = buffer orelse {
                dmabufs.c.zwp_linux_buffer_params_v1_send_failed(data.wl_resource);
                return;
            };
            const wl_client = wls.c.wl_resource_get_client(data.wl_resource) orelse {
                dmabufc.c.wl_buffer_destroy(upstream_buffer);
                dmabufs.c.zwp_linux_buffer_params_v1_send_failed(data.wl_resource);
                return;
            };
            const buffer_resource = createBufferResource(data, wl_client, 0, upstream_buffer) orelse {
                dmabufs.c.zwp_linux_buffer_params_v1_send_failed(data.wl_resource);
                return;
            };
            dmabufs.c.zwp_linux_buffer_params_v1_send_created(data.wl_resource, buffer_resource);
        }

        fn paramsFailed(userdata: ?*anyopaque, _: ?*wlp.zwp_linux_buffer_params_v1) callconv(.c) void {
            const data = dataFromListener(userdata) orelse return;
            dmabufs.c.zwp_linux_buffer_params_v1_send_failed(data.wl_resource);
        }

        fn createBufferResource(
            data: *ResourceData,
            wl_client: *wls.wl_client,
            id: u32,
            buffer: *wlp.wl_buffer,
        ) ?*wls.wl_resource {
            const buffer_resource = data.server.createResource(
                wl_client,
                .buffer,
                &wls.c.wl_buffer_interface,
                1,
                id,
                @ptrCast(&buffer_bindings.impl),
                @ptrCast(buffer),
            ) orelse {
                dmabufc.c.wl_buffer_destroy(buffer);
                return null;
            };
            const buffer_data = H.dataForResource(buffer_resource) orelse {
                wls.c.wl_resource_destroy(buffer_resource);
                return null;
            };
            _ = data.server.engine.bufferCreate(data.client_id, buffer_data.resource_id) catch {
                wls.c.wl_resource_destroy(buffer_resource);
                return null;
            };
            _ = wlc.c.wl_buffer_add_listener(buffer, &buffer_bindings.listener, buffer_data);
            return buffer_resource;
        }

        fn dataFromListener(userdata: ?*anyopaque) ?*ResourceData {
            const ptr = userdata orelse return null;
            return @ptrCast(@alignCast(ptr));
        }
    };
}

test "compiles" {
    _ = create();
}
