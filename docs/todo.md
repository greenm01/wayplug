# TODO

Work between the current stub scaffold and the Phase 1 MVP from
[roadmap.md](roadmap.md). Items are roughly in dependency order; later
items assume earlier ones. Cross off as work lands.

## Phase 0 wrap-up

Phase 0 runtime scaffolding landed in `86a2307`. The public ABI stayed at
version 1; Zig-side code now links real Wayland symbols while the public
header keeps forward declarations.

### ~~Link libwayland~~

Done: `build.zig` links `libwayland-server` and `libwayland-client`
through pkg-config, and `src/wayland/` imports the real client/server
headers.

### ~~Real `wl_display` in `server.zig`~~

Done: `server.zig` owns a real `wl_display` and event loop, `get_fd`
returns the Wayland event-loop fd, `dispatch()` drives the loop, and
`flush()` calls `wl_display_flush_clients()`.

### ~~Real client open/close~~

Done: `wayplug_server_open_client_display` uses `socketpair` plus
`wl_client_create`/`wl_display_connect_to_fd`, indexes the client in the
model, and lifecycle callbacks fire from the effect drain.

### ~~`wayplug_client` opaque handle~~

Done: the server allocates stable `ClientHandle` records and passes them
through lifecycle callbacks and `wayplug_embed_*`.

## Phase 1: First real delegate flow

The first inline delegate pass landed in `server.zig`: `wl_compositor`,
`wl_surface`, `wl_subcompositor`, `wl_subsurface`, `wl_shm`,
`wl_shm_pool`, `wl_buffer`, `wl_callback`, and `wl_region` now have
initial forwarding. Remaining Phase 1 work should make this maintainable
and prove the flow against a compositor.

### ~~Split inline delegates into `src/protocol/`~~

Done: the delegate implementations moved into the existing
`src/protocol/*.zig` modules, with shared runtime casts/resource cleanup
in `src/protocol/runtime.zig`. `server.zig` remains the display/client
owner and registration coordinator, and lifecycle mutation still flows
through the engine facade.

### ~~Strengthen registry/global behavior~~

Done: registry bind handling now validates requested versions instead of
silently downgrading them, invalid binds queue `protocol_error`
diagnostics, and tests cover version selection plus host-supplied global
registration.

### ~~Complete embed teardown~~

Done: client teardown now clears owned embeds, surfaces, buffers,
resources, and relationship indexes before `client_closed` effects fire.
Regression tests cover full embed graph cleanup and multi-client
preservation.

### ~~End-to-end compositor smoke~~

Done: `zig build test` now includes a Weston headless smoke that drives
create-surface → shm buffer → attach → commit → embed resize through the
delegated server and asserts model state plus Wayland error-free delivery.

## Engine maturation

### ~~Dense `EntityManager` storage~~

Done: `EntityManager` now uses dense record storage plus a sparse
id-to-index map. Logical ids stay stable, insert replacement preserves
counts, and delete uses swap-and-pop while updating moved-record lookup.

### ~~Effect queue drain in `dispatch()`~~

Done for current callbacks: client connect/close and surface-created
effects drain synchronously from `wayplug_server_dispatch()`.

### ~~`on_protocol_error` host callback~~

Done: `wayplug_host_interface` has an append-only
`on_protocol_error` callback, the effect drain wires `protocol_error`
effects through it, and ABI normalization accepts older callback-table
sizes.

### ~~Real snapshot copy and relationship invariants~~

Done: `data/snapshot.zig` now returns caller-owned copies of model
records, and `data/invariants.zig` checks dense table consistency,
relationship indexes, cross-table references, and stale/dead indexed
resources.

### ~~Snapshot C ABI~~

Done: `wayplug_server_snapshot(server)` returns a caller-owned opaque
snapshot, `wayplug_snapshot_get_counts()` exposes versioned table counts,
and `wayplug_snapshot_free()` releases the copy. The C ABI smoke covers
null handling, size/version validation, and point-in-time count behavior.

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

Initial Weston headless coverage exists in `tests/protocol_smoke_tests.zig`.
Expand it into a compositor matrix (River, Mutter, KWin) once CI can
provide those environments.

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
