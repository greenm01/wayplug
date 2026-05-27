//! Buffer lifecycle.

const std = @import("std");
const types = @import("../data/types.zig");
const model_mod = @import("../data/model.zig");

pub fn bufferCreate(
    m: *model_mod.Model,
    client_id: types.ClientId,
    resource_id: types.ResourceId,
) !types.BufferId {
    const id = try m.nextBufferId();
    try m.buffers.insert(m.allocator, id, .{
        .id = id,
        .client_id = client_id,
        .resource_id = resource_id,
    });
    try m.buffer_by_resource.put(m.allocator, resource_id, id);
    return id;
}

pub fn bufferDestroy(m: *model_mod.Model, id: types.BufferId) void {
    if (m.buffers.get(id)) |b| {
        _ = m.buffer_by_resource.swapRemove(b.resource_id);
    }
    _ = m.buffers.delete(id);
}

pub fn bufferForResource(m: *const model_mod.Model, rid: types.ResourceId) ?types.BufferId {
    return m.buffer_by_resource.get(rid);
}

// ===== production code above =====

test "buffer create and destroy" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    const cid = try m.nextClientId();
    const rid = try m.nextResourceId();
    const bid = try bufferCreate(&m, cid, rid);
    try std.testing.expect(m.buffers.contains(bid));
    bufferDestroy(&m, bid);
    try std.testing.expect(!m.buffers.contains(bid));
}
