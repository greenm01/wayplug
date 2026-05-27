# Architecture

`wayplug` should use a hybrid architecture.

The Wayland protocol hot path should stay direct and object-oriented. A small
central state layer should handle lifecycle, ownership, policy, and cleanup.
This avoids forcing every Wayland request through an application-style update
loop while still keeping the hard parts explicit.

The data model and ownership rules are described in more detail in
[Data-Oriented Design](dod.md). This document focuses on the larger module
shape and runtime flow.

## Shape

```text
Host application
        |
        | C ABI
        v
+-----------------------------+
| wayplug server              |
|                             |
| central lifecycle state     |
| client/embed/object tables  |
| policy and cleanup rules    |
+-----------------------------+
        |
        | owns
        v
+-----------------------------+
| protocol delegates          |
|                             |
| wl_compositor               |
| wl_surface                  |
| wl_subcompositor            |
| wl_shm / wl_buffer          |
| wl_seat / input devices     |
| wl_output                   |
+-----------------------------+
        |
        | forward requests/events
        v
Real Wayland compositor connection
```

## Project Tree

This is the proposed starting structure. It is intentionally modular, but not
deeply abstract. Each directory should have a narrow job.

```text
wayplug/
  build.zig
  include/
    wayplug.h
  src/
    wayplug.zig

    c_api.zig
    server.zig
    host.zig
    errors.zig

    types/
      core.zig
      client.zig
      resource.zig
      surface.zig
      buffer.zig
      embed.zig
      output.zig
      model.zig

    state/
      entity_manager.zig
      id_gen.zig
      iterators.zig
      queries.zig
      invariants.zig
      snapshot.zig
      engine.zig

    ops/
      client_ops.zig
      resource_ops.zig
      surface_ops.zig
      buffer_ops.zig
      embed_ops.zig
      output_ops.zig

    systems/
      lifecycle.zig
      embed_policy.zig
      input_translation.zig
      diagnostics.zig

    protocol/
      server_display.zig
      registry.zig
      compositor.zig
      surface.zig
      subcompositor.zig
      shm.zig
      buffer.zig
      callback.zig
      seat.zig
      output.zig

    wayland/
      client.zig
      server.zig
      protocols.zig

  tests/
    c_abi_smoke.c
    state_tests.zig
    ops_tests.zig
    protocol_smoke_tests.zig

  docs/
    architecture.md
    dod.md
    protocol-landscape.md
    wsd-architecture.md
    c-abi-sketch.md
    roadmap.md
```

## Module Roles

`include/wayplug.h` is the stable public ABI. It should expose opaque handles,
versioned structs, plain C callbacks, and no Zig-specific types.

`src/c_api.zig` should be the only layer that directly implements exported C
symbols. It validates ABI structs, translates C handles into internal pointers,
and calls the internal server API.

`src/server.zig` owns the runtime object behind `wayplug_server`. It wires
together host callbacks, state, protocol setup, dispatch, flush, and teardown.

`src/host.zig` wraps the host-provided callback table. Internal code should use
this wrapper instead of reaching into the C ABI struct directly.

`src/types/` contains passive records only: ids, enums, flags, and data shapes.
No protocol forwarding or cleanup policy should live here.

`src/state/` owns storage, indexes, queries, iterators, snapshots, and invariant
checks. `state/engine.zig` should be the facade used by protocol and systems
code.

`src/ops/` owns cross-table mutation. If an action creates, destroys, or
relinks more than one kind of object, it belongs here.

`src/systems/` owns policy and behavior above protocol mechanics: lifecycle
cleanup, embed sizing, input coordinate translation, diagnostics, and future
popup/toplevel rules.

`src/protocol/` contains libwayland server/client delegate code. These modules
translate callbacks, validate ownership, forward simple requests, and call ops
for lifecycle changes.

`src/wayland/` is a thin binding/helper layer around generated Wayland
interfaces and C imports. It should not own Wayplug state.

## What Stays Direct

Individual Wayland protocol requests should be forwarded directly by the
delegate that owns the corresponding protocol object.

Examples:

```text
wl_surface.attach
  -> SurfaceDelegate
  -> lookup real wl_buffer
  -> call wl_surface_attach(real_surface, real_buffer, ...)
```

```text
wl_shm_pool.create_buffer
  -> ShmPoolDelegate
  -> call wl_shm_pool_create_buffer(real_pool, ...)
  -> create BufferDelegate
```

```text
wl_pointer.motion event
  -> PointerDelegate listener
  -> translate coordinates if needed
  -> wl_pointer_send_motion(plugin_pointer, ...)
```

These paths are high-frequency and already map naturally to Wayland's protocol
object model. Running every request through an Elm/TEA-style `Msg -> update ->
Cmd` loop would add indirection without making the protocol behavior clearer.

## What Gets Centralized

The central server state should own things that cross object boundaries or need
consistent cleanup.

```text
ServerState
  stopped
  running
  shutting_down
```

```text
ClientState
  connected
  closing
  dead
```

```text
EmbedState
  reserved
  parent_ready
  child_ready
  mapped
  destroyed
```

Central state should track:

- active clients
- plugin connection fds/displays
- host-provided parent surfaces
- plugin-created child surfaces
- parent/child embed relationships
- object ids and resource-to-proxy mappings
- pending resizes
- close/destroy ordering
- protocol errors that require client teardown
- host policy decisions

## Layer Boundary

Protocol delegates should be allowed to forward simple requests immediately.
They should notify central state when something changes the lifecycle model.

```text
Protocol delegate
  simple request?        -> forward directly
  creates object?        -> register object in central table
  destroys object?       -> unregister object and run cleanup
  changes embed state?   -> notify central state
  hits protocol error?   -> mark client closing/dead
```

Examples of central notifications:

```text
onClientConnected(client)
onClientClosed(client)
onSurfaceCreated(client, surface)
onSurfaceDestroyed(client, surface)
onParentSurfaceExported(embed, parent)
onSubsurfaceCreated(embed, child, parent)
onEmbedMapped(embed)
onEmbedResized(embed, width, height)
onProtocolError(client, error)
```

## Host Notifications

The host receives lifecycle events through the `wayplug_host_interface`
callback struct defined in [C ABI Sketch](c-abi-sketch.md). The engine calls
these callbacks synchronously from inside `wayplug_server_dispatch()`.

Rules:

- Callbacks return `void`. They report; they do not gate. Policy decisions
  belong in `src/systems/` and run before the notification fires.
- Callbacks must not call back into `wayplug`. Re-entrancy is undefined.
- A null function pointer in the host interface is a no-op.
- The engine drains its effect queue at the end of each dispatch tick, after
  every protocol callback for that tick has run.

## Event Flow

```text
Wayland fd readable
        |
        v
dispatch server/client events
        |
        v
protocol delegate callback
        |
        +-- direct protocol forwarding
        |
        +-- central state notification when lifecycle changes
```

`wayplug` does not own a dispatch loop. The server exposes its fd through
`wayplug_server_get_fd()`. The host adds that fd to its event loop and calls
`wayplug_server_dispatch()` when the fd becomes readable. The host calls
`wayplug_server_flush()` before blocking. `wayplug` never spawns threads or
polls on its own.

## Ownership Model

The central server should own all long-lived objects.

```text
WayplugServer
  clients[]
  embeds[]
  resources[]
  upstream globals
  allocator
  event queue / dispatch integration
```

Delegates should hold stable references or ids back into those tables rather
than becoming independent owners of cross-cutting state.

```text
SurfaceDelegate
  client_id
  resource_id
  upstream wl_surface *
```

```text
Embed
  host_parent_surface
  plugin_child_surface
  x
  y
  width
  height
  state
```

This keeps teardown deterministic. When a client closes, the server can walk
the owned tables and destroy resources in the correct order.

## Teardown Order

When a client disconnects, the engine walks owned objects in a fixed order:

1. embeds owned by the client (unmap subsurfaces first)
2. plugin-created child surfaces
3. buffers and pending frame callbacks
4. remaining resources
5. resource-by-\* indexes for this client
6. `wl_client` and `wl_display` handles
7. socket fds, server side first, then client side
8. the client row in the clients table

The client enters `ClientState.closing` at step 1 and reaches
`ClientState.dead` after step 8. This order matches
`waylandserver.cpp::closeClientConnection` in the C++ reference and keeps
Wayland's "destroy children before parent" rule intact.

## Policy Belongs Above Protocol

The protocol layer should avoid making host policy decisions.

Good protocol-layer responsibilities:

- forward `wl_surface` requests
- translate object references
- send protocol events
- validate resource ownership
- report protocol errors

Good central/policy responsibilities:

- decide whether a plugin may create a toplevel
- decide whether popups are allowed
- decide how large an embed may be
- decide how to handle plugin disconnects
- decide how to report errors to the host

## MVP Guidance

For the first implementation, keep the centralized state small:

```text
WayplugServer
WayplugClient
WayplugResource
WayplugEmbed
```

Start with direct delegates for:

- `wl_compositor`
- `wl_surface`
- `wl_subcompositor`
- `wl_subsurface`
- `wl_shm`
- `wl_shm_pool`
- `wl_buffer`
- `wl_callback`
- `wl_seat`
- `wl_pointer`
- `wl_keyboard`
- `wl_output`

Add `linux-dmabuf`, XDG shell, data device, text input, and other protocols only
after the lifecycle model is stable.

## Non-Goal

`wayplug` should not become a full Elm/TEA runtime.

The useful part is not the TEA pattern itself. The useful part is having
explicit state transitions for lifecycle-sensitive operations while preserving
Wayland's native object/request/event model for protocol forwarding.
