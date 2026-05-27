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

test "active protocol bindings instantiate against server runtime" {
    const Server = wayplug.server.Server;
    const ResourceData = wayplug.server.ResourceData;

    const Registry = wayplug.protocol.registry.Bindings(Server, ResourceData);
    _ = Registry.bindCompositor;
    _ = Registry.bindSubcompositor;
    _ = Registry.bindShm;

    const Compositor = wayplug.protocol.compositor.Bindings(Server, ResourceData);
    _ = Compositor.impl;
    const Surface = wayplug.protocol.surface.Bindings(Server, ResourceData);
    _ = Surface.impl;
    const Subcompositor = wayplug.protocol.subcompositor.Bindings(Server, ResourceData);
    _ = Subcompositor.impl;
    const Subsurface = wayplug.protocol.subsurface.Bindings(Server, ResourceData);
    _ = Subsurface.impl;
    const Shm = wayplug.protocol.shm.Bindings(Server, ResourceData);
    _ = Shm.impl;
    const ShmPool = wayplug.protocol.shm_pool.Bindings(Server, ResourceData);
    _ = ShmPool.impl;
    const Buffer = wayplug.protocol.buffer.Bindings(Server, ResourceData);
    _ = Buffer.impl;
    _ = Buffer.listener;
    const Callback = wayplug.protocol.callback.Bindings(Server, ResourceData);
    _ = Callback.listener;
    const Region = wayplug.protocol.region.Bindings(Server, ResourceData);
    _ = Region.impl;
}
