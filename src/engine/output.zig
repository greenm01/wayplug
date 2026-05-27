//! Output lifecycle.

const std = @import("std");
const types = @import("../data/types.zig");
const model_mod = @import("../data/model.zig");

pub fn outputCreate(
    m: *model_mod.Model,
    resource_id: types.ResourceId,
    name: u32,
) !types.OutputId {
    const id = try m.nextOutputId();
    try m.outputs.insert(m.allocator, id, .{
        .id = id,
        .resource_id = resource_id,
        .name = name,
    });
    return id;
}

pub fn outputDestroy(m: *model_mod.Model, id: types.OutputId) void {
    _ = m.outputs.delete(id);
}

// ===== production code above =====

test "output create and destroy" {
    var m = model_mod.Model.init(std.testing.allocator);
    defer m.deinit();
    const rid = try m.nextResourceId();
    const oid = try outputCreate(&m, rid, 0);
    try std.testing.expect(m.outputs.contains(oid));
    outputDestroy(&m, oid);
    try std.testing.expect(!m.outputs.contains(oid));
}
