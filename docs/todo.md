# TODO

Current work toward the Phase 1 MVP and the embedded UI path from
[roadmap.md](roadmap.md). Items are roughly in dependency order; later
items assume earlier ones.

## Completed checkpoint

Phase 0, Phase 1 delegate flow, and the first engine-maturation pass are
complete:

- libwayland is linked through pkg-config.
- `server.zig` owns a real Wayland display and event loop.
- client open/close works through real Wayland client/display handles.
- `wayplug_client` is an opaque stable host handle.
- protocol delegates live under `src/protocol/`.
- registry/global binding validates versions and reports protocol errors.
- client teardown clears embeds, surfaces, buffers, resources, and indexes.
- Weston headless smoke covers create-surface, shm buffer, attach, commit,
  embed attach, and resize.
- `EntityManager` uses dense storage with sparse id lookup.
- effects drain from `wayplug_server_dispatch()`.
- `on_protocol_error` is exposed through the host interface.
- snapshots copy model records and expose C ABI table counts.
- relationship invariants check dense tables, indexes, and cross-table
  references.
- embed lifecycle callbacks are exposed as append-only host callbacks.
- embedded pointer enter/motion coordinates are translated through the host
  subsurface-offset callback.
- `wl_keyboard` forwards keymap, focus, key, modifier, and repeat-info
  events from host-provided seats.
- stable XDG shell delegates forward `xdg_wm_base`, `xdg_positioner`,
  `xdg_surface`, `xdg_toplevel`, and `xdg_popup`.

## Phase 2: Embedded UI working

### `wl_output`

Output metadata forwarding so plugins can scale correctly.

## Tests and CI

### Engine end-to-end smoke tests

Initial Weston headless coverage exists in `tests/protocol_smoke_tests.zig`.
Expand it into a compositor matrix (River, Mutter, KWin) once CI can provide
those environments.

### CI

GitHub Actions: pinned Zig version, `zig fmt --check` and `zig build test` on
Linux. Expand to a compositor matrix (Weston, Mutter, KWin, River) once smoke
tests need it.

### Fuzz and protocol-error tests

Per [roadmap.md](roadmap.md) Phase 4. Defer until lifecycle is stable.

## Later phases

### CLAP and LV2 adapters

Per [roadmap.md](roadmap.md) Phase 3. The core stays format-neutral; adapters
live in a separate module.

### Linux dmabuf

Per [roadmap.md](roadmap.md) Phase 4. Defer until the shm path is solid.

### `xdg_foreign` for floating editors

Out of MVP scope. Companion path for floating plugin windows.

## Doc backlog

These came up while writing other docs but did not fit the current scope.

- Pin the ABI-bump policy with a worked example the first time a real break
  happens. Rules live in [../CONTRIBUTING.md](../CONTRIBUTING.md); no example
  yet.
- Decide whether `docs/wsd-architecture.md` gets trimmed when Phase 1 lands
  and the reference value drops, or stays as a long-term anchor.
