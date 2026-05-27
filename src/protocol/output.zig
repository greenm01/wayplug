//! Delegate for wl_output. Sends host-provided mode, geometry, and scale
//! metadata to plugin clients.

const std = @import("std");
const c_api = @import("../c_api.zig");
const runtime = @import("runtime.zig");
const wls = @import("../wayland/server.zig");

pub const Delegate = struct {};

pub fn create() Delegate {
    return .{};
}

pub fn sendInitial(resource: *wls.wl_resource, info: c_api.WayembedOutputInfo) void {
    const version = wls.c.wl_resource_get_version(resource);
    wls.c.wl_output_send_geometry(
        resource,
        info.x,
        info.y,
        info.physical_width,
        info.physical_height,
        info.subpixel,
        info.make.?,
        info.model.?,
        info.transform,
    );
    wls.c.wl_output_send_mode(
        resource,
        info.mode_flags,
        info.mode_width,
        info.mode_height,
        info.mode_refresh,
    );
    if (version >= wls.c.WL_OUTPUT_SCALE_SINCE_VERSION) {
        wls.c.wl_output_send_scale(resource, info.scale);
    }
    if (version >= wls.c.WL_OUTPUT_NAME_SINCE_VERSION) {
        wls.c.wl_output_send_name(resource, info.name.?);
    }
    if (version >= wls.c.WL_OUTPUT_DESCRIPTION_SINCE_VERSION) {
        wls.c.wl_output_send_description(resource, info.description.?);
    }
    if (version >= wls.c.WL_OUTPUT_DONE_SINCE_VERSION) {
        wls.c.wl_output_send_done(resource);
    }
}

pub fn Bindings(comptime Server: type, comptime ResourceData: type) type {
    const H = runtime.Helpers(Server, ResourceData);

    return struct {
        pub const impl = wls.c.struct_wl_output_interface{
            .release = outputRelease,
        };

        fn outputRelease(_: ?*wls.wl_client, resource: ?*wls.wl_resource) callconv(.c) void {
            if (H.dataForResource(resource)) |data| {
                if (data.server.engine.outputForResource(data.resource_id)) |output_id| {
                    data.server.engine.outputDestroy(output_id);
                }
            }
            H.resourceRelease(null, resource);
        }
    };
}

test "compiles" {
    _ = create();
}
