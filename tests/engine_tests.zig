//! Cross-domain engine integration tests.

const std = @import("std");
const wayembed = @import("wayembed");

fn fakeWlClient(comptime address: usize) *wayembed.wayland.server.wl_client {
    return @ptrFromInt(address);
}

fn fakeDisplay(comptime address: usize) *wayembed.wayland.client.wl_display {
    return @ptrFromInt(address);
}

fn fakeProxy(comptime address: usize) *wayembed.wayland.client.wl_proxy {
    return @ptrFromInt(address);
}

test "embed attaches a child surface and clears on destroy" {
    var m = wayembed.data.model.Model.init(std.testing.allocator);
    defer m.deinit();

    const cid = try wayembed.engine.client.clientCreate(&m, -1, -1);
    const parent_rid = try m.nextResourceId();
    const child_rid = try m.nextResourceId();
    const parent_sid = try wayembed.engine.surface.surfaceCreate(&m, cid, parent_rid);
    const child_sid = try wayembed.engine.surface.surfaceCreate(&m, cid, child_rid);

    const eid = try wayembed.engine.embed.embedCreate(&m, cid, parent_sid);
    try wayembed.engine.embed.embedAttachChild(&m, eid, child_sid);
    try wayembed.engine.embed.embedResize(&m, eid, 320, 240);

    const e = m.embeds.get(eid).?;
    try std.testing.expect(e.state == .child_ready);
    try std.testing.expect(e.width == 320);
    try std.testing.expect(wayembed.engine.embed.embedForChildSurface(&m, child_sid).? == eid);

    wayembed.engine.embed.embedDestroy(&m, eid);
    try std.testing.expect(wayembed.engine.embed.embedForChildSurface(&m, child_sid) == null);
}

test "effect queue retains append order until cleared" {
    var q = wayembed.engine.effects.Queue.init(std.testing.allocator);
    defer q.deinit();

    try q.push(.{ .client_connected = @enumFromInt(1) });
    try q.push(.diagnostics_dirty);
    try q.push(.{ .embed_mapped = @enumFromInt(7) });

    const pending = q.pending();
    try std.testing.expectEqual(@as(usize, 3), pending.len);
    try std.testing.expect(pending[2] == .embed_mapped);

    q.clear();
    try std.testing.expectEqual(@as(usize, 0), q.count());
}

test "embed map and resize queue lifecycle effects" {
    var engine = wayembed.engine.Engine.init(std.testing.allocator);
    defer engine.deinit();

    const cid = try engine.clientCreate(-1, -1);
    const parent_rid = try engine.resourceCreate(cid, .surface, null, fakeProxy(0x1000));
    const parent_sid = try engine.surfaceCreate(cid, parent_rid);
    const embed_id = try engine.embedCreate(cid, parent_sid);
    engine.effects.clear();

    try engine.embedMap(embed_id);
    try engine.embedResize(embed_id, 320, 240);

    try std.testing.expectEqual(@as(usize, 2), engine.effects.count());
    try std.testing.expectEqual(embed_id, engine.effects.pending()[0].embed_mapped);
    const resized = engine.effects.pending()[1].embed_resized;
    try std.testing.expectEqual(embed_id, resized.embed_id);
    try std.testing.expectEqual(@as(i32, 320), resized.width);
    try std.testing.expectEqual(@as(i32, 240), resized.height);
    try std.testing.expect(engine.model.embeds.get(embed_id).?.state == .mapped);
}

test "clientDestroy tears down owned embed graph and indexes before client_closed effect" {
    var engine = wayembed.engine.Engine.init(std.testing.allocator);
    defer engine.deinit();

    const cid = try engine.clientCreate(-1, -1);
    try engine.clientSetWaylandHandles(cid, fakeWlClient(0x1000), fakeDisplay(0x2000));

    const parent_rid = try engine.resourceCreate(cid, .surface, null, fakeProxy(0x3000));
    const child_rid = try engine.resourceCreate(cid, .surface, null, fakeProxy(0x4000));
    const subsurface_rid = try engine.resourceCreate(cid, .subsurface, null, fakeProxy(0x5000));
    const buffer_rid = try engine.resourceCreate(cid, .buffer, null, fakeProxy(0x6000));
    const callback_rid = try engine.resourceCreate(cid, .callback, null, fakeProxy(0x7000));
    const region_rid = try engine.resourceCreate(cid, .region, null, fakeProxy(0x8000));
    const touch_rid = try engine.resourceCreate(cid, .touch, null, fakeProxy(0x9000));

    const parent_sid = try engine.surfaceCreate(cid, parent_rid);
    const child_sid = try engine.surfaceCreate(cid, child_rid);
    const buffer_id = try wayembed.engine.buffer.bufferCreate(&engine.model, cid, buffer_rid);
    const embed_id = try engine.embedCreate(cid, parent_sid);
    try engine.embedAttachChild(embed_id, child_sid);
    try engine.embedSetSubsurfaceResource(embed_id, subsurface_rid);

    try std.testing.expect(engine.model.client_by_wl_client.get(fakeWlClient(0x1000)).? == cid);
    try std.testing.expect(engine.model.resource_by_upstream_proxy.get(fakeProxy(0x5000)).? == subsurface_rid);
    try std.testing.expect(engine.model.surface_by_resource.get(child_rid).? == child_sid);
    try std.testing.expect(engine.model.buffer_by_resource.get(buffer_rid).? == buffer_id);
    try std.testing.expect(engine.model.embed_by_child_surface.get(child_sid).? == embed_id);
    engine.effects.clear();

    try engine.clientDestroy(cid);

    try std.testing.expect(!engine.model.clients.contains(cid));
    try std.testing.expect(!engine.model.embeds.contains(embed_id));
    try std.testing.expect(!engine.model.surfaces.contains(parent_sid));
    try std.testing.expect(!engine.model.surfaces.contains(child_sid));
    try std.testing.expect(!engine.model.buffers.contains(buffer_id));
    try std.testing.expect(!engine.model.resources.contains(parent_rid));
    try std.testing.expect(!engine.model.resources.contains(child_rid));
    try std.testing.expect(!engine.model.resources.contains(subsurface_rid));
    try std.testing.expect(!engine.model.resources.contains(buffer_rid));
    try std.testing.expect(!engine.model.resources.contains(callback_rid));
    try std.testing.expect(!engine.model.resources.contains(region_rid));
    try std.testing.expect(!engine.model.resources.contains(touch_rid));
    try std.testing.expect(engine.model.client_by_wl_client.get(fakeWlClient(0x1000)) == null);
    try std.testing.expect(engine.model.client_by_display.get(fakeDisplay(0x2000)) == null);
    try std.testing.expect(engine.model.resource_by_upstream_proxy.get(fakeProxy(0x5000)) == null);
    try std.testing.expect(engine.model.surface_by_resource.get(child_rid) == null);
    try std.testing.expect(engine.model.buffer_by_resource.get(buffer_rid) == null);
    try std.testing.expect(engine.model.embed_by_child_surface.get(child_sid) == null);
    try std.testing.expect(engine.model.embed_by_parent_surface.get(parent_sid) == null);
    try std.testing.expectEqual(@as(usize, 2), engine.effects.count());
    try std.testing.expectEqual(embed_id, engine.effects.pending()[0].embed_destroyed);
    try std.testing.expectEqual(cid, engine.effects.pending()[1].client_closed);
}

test "clientDestroy preserves records owned by other clients" {
    var engine = wayembed.engine.Engine.init(std.testing.allocator);
    defer engine.deinit();

    const doomed = try engine.clientCreate(-1, -1);
    const kept = try engine.clientCreate(-1, -1);
    try engine.clientSetWaylandHandles(doomed, fakeWlClient(0x9000), fakeDisplay(0xa000));
    try engine.clientSetWaylandHandles(kept, fakeWlClient(0xb000), fakeDisplay(0xc000));

    const doomed_resource = try engine.resourceCreate(doomed, .surface, null, fakeProxy(0xd000));
    const doomed_surface = try engine.surfaceCreate(doomed, doomed_resource);
    const kept_resource = try engine.resourceCreate(kept, .surface, null, fakeProxy(0xe000));
    const kept_surface = try engine.surfaceCreate(kept, kept_resource);
    engine.effects.clear();

    try engine.clientDestroy(doomed);

    try std.testing.expect(!engine.model.clients.contains(doomed));
    try std.testing.expect(!engine.model.surfaces.contains(doomed_surface));
    try std.testing.expect(!engine.model.resources.contains(doomed_resource));
    try std.testing.expect(engine.model.clients.contains(kept));
    try std.testing.expect(engine.model.surfaces.contains(kept_surface));
    try std.testing.expect(engine.model.resources.contains(kept_resource));
    try std.testing.expect(engine.model.client_by_wl_client.get(fakeWlClient(0xb000)).? == kept);
    try std.testing.expect(engine.model.client_by_display.get(fakeDisplay(0xc000)).? == kept);
    try std.testing.expect(engine.model.resource_by_upstream_proxy.get(fakeProxy(0xe000)).? == kept_resource);
    try std.testing.expect(engine.model.surface_by_resource.get(kept_resource).? == kept_surface);
    try std.testing.expectEqual(doomed, engine.effects.pending()[0].client_closed);
}
