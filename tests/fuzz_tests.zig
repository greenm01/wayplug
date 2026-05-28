//! Deterministic fuzz-style tests.

const std = @import("std");
const wayembed = @import("wayembed");
const harness = @import("fuzz_harness");

test "targeted lifecycle fuzz preserves model invariants" {
    const seeds = [_]u64{
        0x1199_2026_0000_0001,
        0x1199_2026_0000_0002,
        0x1199_2026_0000_0003,
        0x1199_2026_0000_0004,
        0x1199_2026_0000_0005,
        0x1199_2026_0000_0006,
        0x1199_2026_0000_0007,
        0x1199_2026_0000_0008,
    };

    for (seeds) |seed| {
        try harness.runLifecycleSeed(seed, 128);
    }
}

test "byte corpus lifecycle fuzz preserves model invariants" {
    const corpus = [_][]const u8{
        &.{ 0, 1, 2, 4, 11, 5, 5, 10, 9, 7, 8 },
        &.{ 0, 4, 4, 6, 5, 11, 1, 2, 3, 10 },
        &.{ 5, 6, 7, 8, 9, 10, 11, 0, 0, 4, 5 },
        "wayembed-lifecycle-fuzz-corpus-0001",
    };

    for (corpus, 0..) |bytes, index| {
        var label_buf: [32]u8 = undefined;
        const label = try std.fmt.bufPrint(&label_buf, "corpus-{}", .{index});
        try harness.runLifecycleBytes(std.testing.allocator, bytes, label);
    }
}

test "delegate-request fuzz cases keep teardown stable" {
    var engine = wayembed.engine.Engine.init(std.testing.allocator);
    defer engine.deinit();

    const client_id = try engine.clientCreate(-1, -1);
    const parent_resource_id = try engine.resourceCreate(client_id, .surface, null, null);
    const child_resource_id = try engine.resourceCreate(client_id, .surface, null, null);
    const parent_surface_id = try engine.surfaceCreate(client_id, parent_resource_id);
    const child_surface_id = try engine.surfaceCreate(client_id, child_resource_id);
    const embed_id = try engine.embedCreate(client_id, parent_surface_id);
    try engine.embedAttachChild(embed_id, child_surface_id);
    try engine.surfaceAssignRole(child_surface_id, .subsurface);
    try std.testing.expectError(error.RoleAlreadyAssigned, engine.surfaceAssignRole(child_surface_id, .popup));
    try engine.protocolError(client_id, 1);
    try engine.clientDestroy(client_id);
    try engine.clientDestroy(client_id);

    try std.testing.expect(wayembed.data.invariants.check(&engine.model).ok());
}
