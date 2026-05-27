# Architecture

`wayembed` should use a hybrid architecture.

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
| wayembed server              |
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
wayembed/
  build.zig
  include/
    wayembed.h
  src/
    wayembed.zig

    c_api.zig
    server.zig
    host.zig
    errors.zig

    data/
      types.zig         records, ids, enums, flags
      model.zig         EntityManagers, indexes, id counters
      snapshot.zig      generic snapshot walker
      invariants.zig    generic invariant walker

    engine/
      engine.zig        facade used by protocol and c_api
      client.zig        ops, queries, policy for clients
      resource.zig
      surface.zig
      buffer.zig
      embed.zig
      output.zig
      effects.zig       per-dispatch effect queue

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
    data_tests.zig
    engine_tests.zig
    protocol_smoke_tests.zig

  docs/
    architecture.md
    dod.md
    style-guide.md
    host-integration.md
    protocol-landscape.md
    wsd-architecture.md
    c-abi-sketch.md
    roadmap.md
```

Each `engine/<domain>.zig` owns mutation, queries, and policy for that
domain. Splitting `ops` and `systems` across separate top-level trees would
spread one domain's behavior across two directories without making the
mutation/policy distinction any clearer at call sites; keeping a domain in
one file lets the boundary live in function names instead.

## Module Roles

`include/wayembed.h` is the stable public ABI. It should expose opaque handles,
versioned structs, plain C callbacks, and no Zig-specific types.

`src/c_api.zig` should be the only layer that directly implements exported C
symbols. It validates ABI structs, translates C handles into internal pointers,
and calls the internal server API.

`src/server.zig` owns the runtime object behind `wayembed_server`. It wires
together host callbacks, state, protocol setup, dispatch, flush, and teardown.

`src/host.zig` wraps the host-provided callback table. Internal code should use
this wrapper instead of reaching into the C ABI struct directly.

`src/data/` holds the model. `types.zig` defines passive records, ids,
enums, and flags. `model.zig` holds the `EntityManager` tables, indexes,
and id counters. `snapshot.zig` and `invariants.zig` are comptime-generic
walkers — adding a record type to `model.zig` gives it snapshot output and
per-table invariant coverage without per-domain plumbing.

`src/engine/` holds the code that operates on the model. `engine.zig` is
the facade used by `protocol/` and `c_api.zig`. Each `<domain>.zig`
(client, surface, embed, etc.) owns mutation, queries, and policy for that
domain. `effects.zig` owns the per-dispatch effect queue. Hot-path
forwarding stays in `protocol/`; the engine handles lifecycle.

`src/protocol/` contains libwayland server/client delegate code. These
modules translate callbacks, validate ownership, forward simple requests,
and call into `engine/` for lifecycle changes.

`src/wayland/` is a thin binding/helper layer around generated Wayland
interfaces and C imports. It should not own Wayembed state.

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

The host receives lifecycle events through the `wayembed_host_interface`
callback struct declared in [../include/wayembed.h](../include/wayembed.h).
The engine calls these callbacks synchronously from inside
`wayembed_server_dispatch()`.

Rules:

- Callbacks return `void`. They report; they do not gate. Policy decisions
  belong in `src/engine/` and run before the notification fires.
- Only `on_surface_created` may call back into the same `wayembed_server`
  instance, and only to attach the new embed. Other callbacks may issue
  Wayland calls on the host's own upstream connection.
- A null function pointer in the host interface is a no-op.
- Most host notifications come from the effect queue at the end of each
  dispatch tick. `on_surface_created` fires inline during
  `wl_compositor.create_surface` so the host can attach before later batched
  surface requests run.

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

`wayembed` does not own a dispatch loop. The server exposes its fd through
`wayembed_server_get_fd()`. The host adds that fd to its event loop and calls
`wayembed_server_dispatch()` when the fd becomes readable. The host calls
`wayembed_server_flush()` before blocking. `wayembed` never spawns threads or
polls on its own.

## Ownership Model

The central server should own all long-lived objects.

```text
WayembedServer
  clients[]
  embeds[]
  resources[]
  upstream globals
  allocator
  event queue / dispatch integration
```

Delegates should hold stable references or ids back into those tables instead
of becoming independent owners of cross-cutting state.

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

The public ownership contract lives in [Lifetime Rules](lifetime.md). Keep
that page in sync with every public handle or callback change.

## Teardown Order

When a client disconnects, the engine walks owned objects in a fixed order:

1. embeds owned by the client (unmap subsurfaces first)
2. plugin-created child surfaces
3. buffers and pending frame callbacks
4. remaining resources
5. resource-by-\* indexes for this client
6. `wl_client` and optional `wl_display` handles
7. socket fds, except raw fds already handed to the host
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
WayembedServer
WayembedClient
WayembedResource
WayembedEmbed
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

`wayembed` should not become a full Elm/TEA runtime.

The useful part is not the TEA pattern itself. The useful part is having
explicit state transitions for lifecycle-sensitive operations while preserving
Wayland's native object/request/event model for protocol forwarding.
