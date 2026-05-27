# TODO

Current work after the Phase 1 MVP and embedded UI path from
[roadmap.md](roadmap.md). The immediate implementation backlog is small;
most remaining work is blocked on external compositor support or belongs to
later roadmap phases.

## Current checkpoint

Phase 0, Phase 1 delegate flow, the first engine-maturation pass, and the
current Phase 2 embedded UI path are complete:

- libwayland is linked through pkg-config.
- `server.zig` owns a real Wayland display and event loop.
- client open/close works through real Wayland client/display handles.
- `wayembed_client` is an opaque stable host handle.
- protocol delegates live under `src/protocol/`.
- registry/global binding validates versions and reports protocol errors.
- client teardown clears embeds, surfaces, buffers, resources, and indexes.
- Weston, River, Mutter, Niri, and KWin smoke cover create-surface, shm
  buffer, attach, commit, embed attach, and resize through a shared
  compositor harness.
- `EntityManager` uses dense storage with sparse id lookup.
- effects drain from `wayembed_server_dispatch()`.
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
- `wl_output` forwards a host-provided output metadata snapshot so plugins
  can receive scale and mode information.
- `wl_touch` forwards multi-touch streams from host-provided seats, including
  embedded-surface coordinate translation.
- the embedded editor session lifecycle is formalized around explicit
  `wayembed_embed *` handles, with attach allowed from `on_surface_created`.
- Phase 3 has a dependency-free experimental adapter contract for CLAP/LV2/VST3
  handoff tokens and validated display/resize structs.
- `wayembed-sandbox` proves the Phase 3 C ABI from Nim with CLAP-shaped,
  LV2-shaped, and VST3-shaped handoff order smokes, C fixture handoff smokes,
  and a live embed smoke for both in-process display and raw-fd client handoff.
- Element has an opt-in CLAP spike that keeps XEmbed as the default and proves
  the adapter token/display handoff path without mapping pixels.
- Element now has a second opt-in visible-embed gate
  (`ELEMENT_WAYEMBED_CLAP_EMBED=1`). Stock JUCE 8.0.12 still exposes an X11
  native window on Linux, but the `greenm01/JUCE` `wayland-juce8` branch now
  exposes the parent `wl_surface` and globals Element needs to call
  `wayembed_embed_attach()`.
- GitHub Actions runs the pinned Zig formatter, default test suite, and a
  required Weston smoke path on Linux.

## Tests and CI

### Engine end-to-end smoke tests

Weston, River, Mutter, and KWin headless or virtual coverage exists in
`tests/protocol_smoke_tests.zig`; Niri nested coverage exists when a parent
display is available.

Add Hyprland coverage only after a reliable headless or nested test
invocation is available.

Hyprland 0.55.2 is installed on the CachyOS dev machine, but is not yet
usable as a smoke target: isolated headless startup fails before creating a
Wayland socket because Aquamarine cannot open a backend/allocator, and nested
startup currently fails against tested parent compositors due to missing or
incompatible parent protocols. Keep the crash reports and compositor logs as
diagnostics for the next investigation pass.

### CI

Baseline GitHub Actions coverage exists with a pinned Zig version,
`zig fmt --check`, `zig build test`, and a required Weston smoke run on
Linux. Expand to a broader compositor matrix (River, Mutter, Niri, KWin,
Hyprland) once CI can provide those environments.

### Fuzz and protocol-error tests

Per [roadmap.md](roadmap.md) Phase 4. Defer until lifecycle is stable.

## Later phases

### CLAP, LV2, and VST3 adapters

Per [roadmap.md](roadmap.md) Phase 3. The core stays format-neutral; the
first experimental handoff contract lives in `include/wayembed_adapters.h`
and [adapter-contract.md](adapter-contract.md). `wayembed-sandbox` is the
current proof harness. It now checks CLAP, LV2, and VST3 handoffs against a
tiny C Wayland plugin fixture, so the display handoff is proven outside Nim too.
Host-facing notes describe the Carla/Element-shaped glue path. Element now
carries the first opt-in real-host CLAP spike: it accepts the wayembed token,
passes the display handoff through `clap_plugin_gui.set_parent()`, and leaves
XEmbed as the default. The visible-embed path is now gated separately and can
consume the Wayland peer handles exposed by the `wayland-juce8` JUCE fork.
Full CLAP/LV2/VST3 runtime helpers, stock-JUCE support, and wider host-toolkit
APIs remain future work.

### Linux dmabuf

Per [roadmap.md](roadmap.md) Phase 4. Defer until the shm path is solid.

### `xdg_foreign` for floating editors

Out of MVP scope. Companion path for floating plugin windows.

## Doc backlog

These came up while writing other docs but did not fit the current scope.

- Keep [wsd-architecture.md](wsd-architecture.md) as a prior-art reference.
  It is not a contract for wayembed, but it remains useful context for the
  delegated-server model and protocol coverage decisions.
