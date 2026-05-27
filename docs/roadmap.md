# Roadmap

## Phase 0: Research

- Document prior art.
- Use Zig for the initial implementation.
- Keep public API C from the first commit.
- Build a tiny C test harness to enforce ABI cleanliness.

### Test Harness Wiring

`tests/c_abi_smoke.c` is the C-side ABI smoke test. `build.zig` adds it as
a `b.addExecutable` step compiled via `zig cc`, linked against the static
`wayplug` library and `include/wayplug.h`. `zig build test` runs it
alongside the Zig unit tests.

Initial smoke coverage:

- `wayplug_abi_version()` returns the version `WAYPLUG_ABI_VERSION`
  declares.
- Opaque handles round-trip through create/destroy without dereferencing.
- `wayplug_server_create` / `wayplug_server_destroy` is balanced under a
  leak-detecting allocator wired through the Zig test wrapper.
- One `wayplug_server_open_client_display` /
  `wayplug_server_close_client_display` cycle completes without
  outstanding resources.

## Phase 1: Minimal Delegated Server

- Create/destroy server.
- Open/close plugin client display.
- Register core globals:
  - `wl_compositor`
  - `wl_subcompositor`
  - `wl_shm`
- Forward:
  - `wl_surface`
  - `wl_subsurface`
  - `wl_region`
  - `wl_callback`
- Render a test client into a host-controlled subsurface using shm.

## Phase 2: Usable Embedded UI

- Add `xdg_wm_base`, `xdg_surface`, `xdg_popup`.
- Add `wl_seat`, pointer, keyboard, and touch forwarding.
- Add output metadata.
- Define resize and lifecycle helpers.
- Test under River, Weston, Mutter, and KWin.

## Phase 3: Plugin Format Adapters

- Experimental CLAP extension mapping.
- Experimental LV2 extension mapping.
- Tiny host/plugin examples.
- Carla-oriented integration notes.

## Phase 4: Performance and Completeness

- Add Linux dmabuf.
- Add fractional scale and viewporter if needed.
- Add stronger lifecycle validation.
- Add fuzz/protocol error tests where practical.

## Non-Goals For MVP

- Full compositor implementation.
- X11/XWayland compatibility.
- Stable public CLAP/LV2 extension before proof of concept.
- Floating-window transient support via `xdg_foreign_unstable_v2`.
