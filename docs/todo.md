# TODO

Active work after the embedded UI path from [roadmap.md](roadmap.md). Keep this
file short. It is a backlog, not a release log.

## Phase 3: Plugin Format Adapters

The experimental CLAP, LV2, and VST3 handoff contract lives in
`include/wayembed_adapters.h` and [adapter-contract.md](adapter-contract.md).
`wayembed-sandbox` is the proof harness.

Next work:

- Build a real-host VST3 spike against the VST3 3.8 Wayland path.
- Document a host-owned generated-control fallback for plugins without native
  Wayland UIs.
- Document the XWayland containment story if generated controls are not enough
  for common legacy plugins.
- Add adapter helper APIs only when real host glue shows repeated code that the
  core can own without taking over plugin loading.
- Keep Element and Carla notes focused on host integration shape, not local
  troubleshooting history.

## Tests and CI

- Expand CI beyond the required Weston smoke when the runner can provide stable
  River, Mutter, Niri, or KWin environments.
- Add Hyprland smoke coverage only after a reliable nested or headless command
  exists.
- Keep compositor-specific crash logs and protocol traces outside this file
  unless they point to an active fix.

## Phase 4: Performance and Completeness

- Add Linux dmabuf after the shm path and embed lifecycle stay stable.
- Add fractional scale and viewporter support if real plugin UIs need them.
- Add stronger lifecycle validation around partially-created and closing
  clients.
- Add fuzz and protocol-error tests where they catch real delegate mistakes.

## Deferred

- `xdg_foreign` for floating editors and transient dialogs.
- Stable public CLAP/LV2/VST3 extensions before more real host proof exists.
- Full X11/XWayland compatibility inside the core delegated server.
