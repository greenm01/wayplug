//! Embed lifecycle: parent-child surface relationship, resize, mapping.
//!
//! This is the heart of the embedded-plugin-editor use case. Per
//! docs/host-integration.md, host code reaches the engine via
//! `wayplug_embed_attach` and `wayplug_embed_resize` on the C ABI.

const std = @import("std");
const types = @import("../data/types.zig");
const model_mod = @import("../data/model.zig");

pub fn embedCreate(
    m: *model_mod.Model,
    client_id: types.ClientId,
    host_parent_surface: types.SurfaceId,
) !types.EmbedId {
    const id = try m.nextEmbedId();
    try m.embeds.insert(m.allocator, id, .{
        .id = id,
        .client_id = client_id,
        .state = .reserved,
        .host_parent_surface_id = host_parent_surface,
        .plugin_child_surface_id = .null_id,
        .subsurface_resource_id = .null_id,
        .x = 0,
        .y = 0,
        .width = 0,
        .height = 0,
    });
    try m.embed_by_parent_surface.put(m.allocator, host_parent_surface, id);
    return id;
}

pub fn embedAttachChild(
    m: *model_mod.Model,
    id: types.EmbedId,
    child_surface: types.SurfaceId,
) !void {
    const e = m.embeds.getMutable(id) orelse return error.UnknownEmbed;
    e.plugin_child_surface_id = child_surface;
    e.state = .child_ready;
    try m.embed_by_child_surface.put(m.allocator, child_surface, id);
}

pub fn embedSetSubsurfaceResource(
    m: *model_mod.Model,
    id: types.EmbedId,
    resource_id: types.ResourceId,
) !void {
    const e = m.embeds.getMutable(id) orelse return error.UnknownEmbed;
    e.subsurface_resource_id = resource_id;
}

pub fn embedResize(m: *model_mod.Model, id: types.EmbedId, width: i32, height: i32) !void {
    const e = m.embeds.getMutable(id) orelse return error.UnknownEmbed;
    e.width = width;
    e.height = height;
}

pub fn embedDestroy(m: *model_mod.Model, id: types.EmbedId) void {
    if (m.embeds.get(id)) |e| {
        _ = m.embed_by_parent_surface.swapRemove(e.host_parent_surface_id);
        if (e.plugin_child_surface_id != .null_id) {
            _ = m.embed_by_child_surface.swapRemove(e.plugin_child_surface_id);
        }
    }
    _ = m.embeds.delete(id);
}

pub fn embedForChildSurface(m: *const model_mod.Model, sid: types.SurfaceId) ?types.EmbedId {
    return m.embed_by_child_surface.get(sid);
}

pub fn embedForParentSurface(m: *const model_mod.Model, sid: types.SurfaceId) ?types.EmbedId {
    return m.embed_by_parent_surface.get(sid);
}

// ===== production code above =====

test "embed create, attach child, resize, destroy" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();

    const cid = try m.nextClientId();
    const parent = try m.nextSurfaceId();
    const child = try m.nextSurfaceId();

    const eid = try embedCreate(&m, cid, parent);
    try embedAttachChild(&m, eid, child);
    try embedResize(&m, eid, 400, 300);

    const e = m.embeds.get(eid).?;
    try std.testing.expect(e.state == .child_ready);
    try std.testing.expect(e.width == 400);
    try std.testing.expect(embedForChildSurface(&m, child).? == eid);

    embedDestroy(&m, eid);
    try std.testing.expect(!m.embeds.contains(eid));
    try std.testing.expect(embedForChildSurface(&m, child) == null);
}
