# TODO

Work between the current stub scaffold and the Phase 1 MVP from
[roadmap.md](roadmap.md). Items are roughly in dependency order; later
items assume earlier ones. Cross off as work lands.

## Phase 0 wrap-up

### Link libwayland

`src/wayland/` declares opaque types only. Phase 1 needs
`libwayland-server` and `libwayland-client` discoverable through
`build.zig`. Use pkg-config via `b.dependency` or system paths. The
header forward-declarations in `include/wayplug.h` stay; only Zig-side
code reaches real symbols.

### Real `wl_display` in `server.zig`

Replace the `getFd() -> -1` stub with `wl_display_create()` +
`wl_display_get_event_loop()` + `wl_event_loop_get_fd()`. Wire
`dispatch()` to `wl_display_dispatch()` and `flush()` to
`wl_display_flush_clients()`. Update `tests/c_abi_smoke.c` to expect a
real fd back from `wayplug_server_get_fd`.

### Real client open/close

`wayplug_server_open_client_display` returns null today. Implement via
`socketpair(AF_UNIX, SOCK_STREAM)` → `wl_client_create(display, fd[0])`
→ `wl_display_connect_to_fd(fd[1])`. The matching
`engine.client.clientCreate` call lands the new client in the model. The
`on_client_connected` callback fires from the effect drain after
dispatch.

### `wayplug_client` opaque handle

The opaque type exists but no function returns one. Allocate a stable
`ClientHandle` struct per client (separate from the EntityManager) and
hand `*ClientHandle` out through the lifecycle callbacks and
`wayplug_embed_*` functions. The handle wraps a `ClientId` for engine
lookup so the table can reallocate without invalidating the host's
pointer.

## Phase 1: First real delegate flow

### `wl_registry` bind dispatch

The first protocol that does real work. Advertises only the globals the
host supplies through `wayplug_host_interface`. The C++ reference's
`registrydelegate.cpp` is 663 lines; a comptime dispatch table in Zig
should land it considerably tighter.

### `wl_compositor` and `wl_surface`

First end-to-end flow. The plugin binds `wl_compositor`, calls
`create_surface`, the delegate forwards to the host's upstream
`wl_compositor`, registers the new `Resource` and `Surface` in the
model, and fires `on_surface_created`. Direct forwarding for attach,
damage, and commit per [architecture.md](architecture.md) § What Stays
Direct.

### `wl_subcompositor` and `wl_subsurface`

The embed primitive. The delegate triggers
`engine.embed.embedAttachChild`. Implements `wayplug_embed_attach` on
the C ABI side. With this and the surface delegate in place,
[host-integration.md](host-integration.md) runs end-to-end against a
real compositor.

### `wl_shm`, `wl_shm_pool`, `wl_buffer`

Required to render anything. Fd handoff is the load-bearing part in
`wl_shm_pool` — that's where the `upstream_proxy` lookups in
`engine/resource.zig` get exercised.

### `wl_callback` and `wl_region`

Small, finish out Phase 1 protocol coverage.

## Engine maturation

### Dense `EntityManager` storage

Replace the `AutoArrayHashMapUnmanaged` backing with a dense
`ArrayList(V)` plus a sparse id → index map. Logical ids stay stable;
delete uses swap-and-pop per [dod.md](dod.md) § Entity Manager. Land
this after the first delegates work; doing it earlier optimizes a path
that no benchmark has yet pointed at.

### Effect queue drain in `dispatch()`

`server.dispatch()` currently does nothing. After protocol delegates
fire for a tick, drain the effect queue and translate each `Effect`
into the matching `wayplug_host_interface` callback. Confirm the
ordering matches [architecture.md](architecture.md) § Host
Notifications.

### `on_protocol_error` host callback

The `protocol_error` effect exists in `engine/effects.zig` but has no
matching callback in `wayplug_host_interface`. Add the field to
`include/wayplug.h` and wire it through the effect drain. The callback
receives the `wayplug_client *` handle and the Wayland error code. Update
`tests/c_abi_smoke.c` to cover the new field. See
[logging.md](logging.md) § Planned Diagnostics Expansion.

### Real snapshot copy and relationship invariants

`data/snapshot.zig` counts records today; should copy them. The
comptime walker scaffold is already in place — fill in the field-copy
body. `data/invariants.zig` is no-op; add the cross-table relationship
checks called out in [dod.md](dod.md) § Invariants (every
`Resource.client_id` exists, every embed's surface ids exist, no
destroyed records in indexes).

### Snapshot C ABI

Once the snapshot copy is real, expose it through the public header:
`wayplug_server_snapshot(server)` returns a caller-owned
`wayplug_snapshot *`; `wayplug_snapshot_free(snapshot)` releases it.
The snapshot is a point-in-time copy; subsequent ops do not invalidate
it. Add to `include/wayplug.h` and cover the round-trip in
`tests/c_abi_smoke.c`. See [logging.md](logging.md) § Planned
Diagnostics Expansion.

## Phase 2: Embedded UI working

### Embed lifecycle callbacks

The `embed_mapped`, `embed_resized`, and `embed_destroyed` effects exist
in `engine/effects.zig` but have no matching callbacks in
`wayplug_host_interface`. Add `on_embed_mapped`, `on_embed_resized`, and
`on_embed_destroyed` to `include/wayplug.h`. Each receives a stable embed
id (`uint32_t`, not reused within a server's lifetime) so the host can
correlate events across the embed's lifecycle. Wire through the effect
drain. Update `tests/c_abi_smoke.c`. See [logging.md](logging.md) §
Planned Diagnostics Expansion.

### Embed input coordinate translation

`protocol/pointer.zig` listener uses `host.getSubsurfaceOffset()` to
translate compositor-space pointer coordinates into plugin-surface
coordinates. The C++ reference's seat handling is the prior-art map.
Without this, plugins under nested embedding receive pointer events in
the wrong frame.

### `wl_seat`, `wl_pointer`, `wl_keyboard`

Pointer first, keyboard second. Touch can wait. Per
[protocol-landscape.md](protocol-landscape.md).

### `xdg_wm_base`, `xdg_surface`, `xdg_toplevel`, `xdg_popup`

Popup support for plugins that want native menus. Less load-bearing
than the embed path but a standard expectation of plugin UIs.

### `wl_output`

Output metadata forwarding so plugins can scale correctly.

## Tests and CI

### Engine end-to-end smoke tests

With real delegates in place, `tests/protocol_smoke_tests.zig` can spin
up a headless compositor (Weston `--backend=headless` or River with no
seat) on a unix socket, connect a wayplug-driven test client, drive a
`create_surface` → attach buffer → embed → resize → destroy sequence,
and assert the upstream calls landed. Blocked on Phase 1 delegates.

### CI

GitHub Actions: pinned Zig version, `zig fmt --check` and `zig build
test` on Linux. Expand to a compositor matrix (Weston, Mutter, KWin,
River) once smoke tests need it.

### Fuzz and protocol-error tests

Per [roadmap.md](roadmap.md) Phase 4. Defer until lifecycle is stable.

## Later phases

### CLAP and LV2 adapters

Per [roadmap.md](roadmap.md) Phase 3. The core stays format-neutral;
adapters live in a separate module.

### Linux dmabuf

Per [roadmap.md](roadmap.md) Phase 4. Defer until the shm path is
solid.

### `xdg_foreign` for floating editors

Out of MVP scope. Companion path for floating plugin windows.

## Doc backlog

These came up while writing other docs but did not fit the current
scope.

- Pin the ABI-bump policy with a worked example the first time a real
  break happens. Rules live in [../CONTRIBUTING.md](../CONTRIBUTING.md);
  no example yet.
- Decide whether `docs/wsd-architecture.md` gets trimmed when Phase 1
  lands and the reference value drops, or stays as a long-term anchor.
