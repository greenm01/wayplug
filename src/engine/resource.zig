//! Resource lifecycle: create/destroy plus the wl_resource and
//! upstream-proxy lookups. Per docs/dod.md § Operations.

const std = @import("std");
const types = @import("../data/types.zig");
const model_mod = @import("../data/model.zig");
const wlc = @import("../wayland/client.zig");
const wls = @import("../wayland/server.zig");

pub fn resourceCreate(
    m: *model_mod.Model,
    client_id: types.ClientId,
    kind: types.ResourceKind,
    wl_resource: ?*wls.wl_resource,
    upstream_proxy: ?*wlc.wl_proxy,
) !types.ResourceId {
    const id = try m.nextResourceId();
    try m.resources.insert(m.allocator, id, .{
        .id = id,
        .client_id = client_id,
        .kind = kind,
        .state = .alive,
        .wl_resource = wl_resource,
        .upstream_proxy = upstream_proxy,
        .generation = 1,
    });
    if (wl_resource) |wr| try m.resource_by_wl_resource.put(m.allocator, wr, id);
    if (upstream_proxy) |up| try m.resource_by_upstream_proxy.put(m.allocator, up, id);
    return id;
}

pub fn resourceDestroy(m: *model_mod.Model, id: types.ResourceId) void {
    if (m.resources.get(id)) |r| {
        if (r.wl_resource) |wr| _ = m.resource_by_wl_resource.swapRemove(wr);
        if (r.upstream_proxy) |up| _ = m.resource_by_upstream_proxy.swapRemove(up);
    }
    _ = m.resources.delete(id);
}

pub fn resourceForWlResource(m: *const model_mod.Model, wr: *wls.wl_resource) ?types.ResourceId {
    return m.resource_by_wl_resource.get(wr);
}

pub fn resourceForUpstreamProxy(m: *const model_mod.Model, p: *wlc.wl_proxy) ?types.ResourceId {
    return m.resource_by_upstream_proxy.get(p);
}

pub fn upstreamProxyForResource(m: *const model_mod.Model, id: types.ResourceId) ?*wlc.wl_proxy {
    const r = m.resources.get(id) orelse return null;
    return r.upstream_proxy;
}

// ===== production code above =====

test "resourceCreate registers and resourceDestroy removes" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    const cid = try m.nextClientId();
    const rid = try resourceCreate(&m, cid, .surface, null, null);
    try std.testing.expect(m.resources.contains(rid));
    resourceDestroy(&m, rid);
    try std.testing.expect(!m.resources.contains(rid));
}
