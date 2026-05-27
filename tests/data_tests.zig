//! Cross-module data-layer integration tests. Exercises the public
//! `data.*` surface via `@import("wayplug")`.

const std = @import("std");
const wayplug = @import("wayplug");

test "snapshot picks up records inserted across two domains" {
    var m = wayplug.data.model.Model.init(std.testing.allocator);
    defer m.deinit();

    const cid = try wayplug.engine.client.clientCreate(&m, -1, -1);
    _ = cid;
    _ = try wayplug.engine.surface.surfaceCreate(
        &m,
        @enumFromInt(1),
        @enumFromInt(1),
    );

    var snap = try wayplug.data.snapshot.snapshot(std.testing.allocator, &m);
    defer wayplug.data.snapshot.snapshotFree(&snap);

    try std.testing.expectEqual(@as(usize, 1), snap.counts.clients);
    try std.testing.expectEqual(@as(usize, 1), snap.counts.surfaces);
}

test "invariants pass after a normal create/destroy round-trip" {
    var m = wayplug.data.model.Model.init(std.testing.allocator);
    defer m.deinit();

    const cid = try wayplug.engine.client.clientCreate(&m, -1, -1);
    wayplug.engine.client.clientDestroy(&m, cid);

    const report = wayplug.data.invariants.check(&m);
    try std.testing.expect(report.ok());
}
