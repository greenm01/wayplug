//! Protocol-layer smoke tests. Every delegate's `create()` must return a
//! zero-init struct without crashing. Real behavior tests land here as
//! interfaces are implemented.

const std = @import("std");
const wayplug = @import("wayplug");

test "every protocol delegate has a create() that compiles" {
    _ = wayplug.protocol.server_display.create();
    _ = wayplug.protocol.registry.create();
    _ = wayplug.protocol.compositor.create();
    _ = wayplug.protocol.surface.create();
    _ = wayplug.protocol.subcompositor.create();
    _ = wayplug.protocol.subsurface.create();
    _ = wayplug.protocol.shm.create();
    _ = wayplug.protocol.shm_pool.create();
    _ = wayplug.protocol.buffer.create();
    _ = wayplug.protocol.callback.create();
    _ = wayplug.protocol.region.create();
    _ = wayplug.protocol.seat.create();
    _ = wayplug.protocol.pointer.create();
    _ = wayplug.protocol.keyboard.create();
    _ = wayplug.protocol.output.create();
}
