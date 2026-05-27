# Roadmap

## Phase 0: Research

- Document prior art.
- Use Zig for the initial implementation.
- Keep public API C from the first commit.
- Build a tiny C test harness to enforce ABI cleanliness.

### Test Harness Wiring

`tests/c_abi_smoke.c` is the C-side ABI smoke test. `build.zig` adds it as
a `b.addExecutable` step compiled via `zig cc`, linked against the static
`wayembed` library and `include/wayembed.h`. `zig build test` runs it
alongside the Zig unit tests.

Initial smoke coverage:

- `wayembed_abi_version()` returns the version `WAYEMBED_ABI_VERSION`
  declares.
- Opaque handles round-trip through create/destroy without dereferencing.
- `wayembed_server_create` / `wayembed_server_destroy` is balanced under a
  leak-detecting allocator wired through the Zig test wrapper.
- One `wayembed_server_open_client_display` /
  `wayembed_server_close_client_display` cycle completes without
  outstanding resources.
- One `wayembed_server_open_client_fd` / `wayembed_server_close_client`
  cycle completes without leaking server state or fd ownership.

## Phase 1: Minimal Delegated Server

- Create/destroy server.
- Open/close plugin client display.
- Open/close plugin client fd for out-of-process handoff.
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

- Experimental CLAP extension mapping: starter contract exists in
  `include/wayembed_adapters.h`; `wayembed-sandbox` covers the handoff order.
- Experimental LV2 extension mapping: starter contract exists in
  `include/wayembed_adapters.h`; `wayembed-sandbox` covers the feature handoff
  order.
- Tiny host/plugin examples: `wayembed-sandbox` opens a live host surface and
  embeds one plugin-created surface through the C ABI.
- C plugin fixture proof: `wayembed-sandbox` passes a CLAP handoff display into
  C code, then embeds the C-created surface.
- Carla- and Element-oriented integration notes for host-owned plugin glue.
- Element CLAP proof: opt-in host spike proves the adapter token and display
  handoff while XEmbed remains the default. Visible embedding has its own
  runtime gate and now reports the JUCE 8.0.12 blocker: no parent `wl_surface`
  is exposed to Element.

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
