# wayembed

`wayembed` is a small Wayland delegated-server library for native plugin
editors. No X11. No XEmbed.

A host runs an internal Wayland server, gives the plugin its own connection to
that server, and embeds the plugin editor under a host-owned parent surface.
The public boundary is plain C, so hosts and plugins in any language can bind
to it.

The current target is audio plugin UI hosting for CLAP, LV2, and VST3. The
core stays format-neutral. Format glue belongs in the host or adapter layer.

Floating plugin windows are a separate job. Embedded editors use
`wl_subsurface`; floating editors and transient dialogs will need their own
track.

## Current Shape

The core can:

- open plugin-side Wayland connections by display or fd;
- proxy host-owned parent surfaces onto the plugin display;
- embed a role-less plugin child surface with `wayembed_embed_attach()`;
- adopt a plugin-created child subsurface with
  `wayembed_embed_adopt_subsurface()`;
- forward compositor, subcompositor, shm, seat, output, xdg shell, and dmabuf
  protocol objects;
- resize active embeds and report lifecycle callbacks through the C ABI.

The strict VST3 3.8 Wayland path is the strongest proof right now. A VST3 host
passes a parent `wl_surface` with `WaylandSurfaceID`; the plugin creates
`wl_subsurface(child, parent)`; the host adopts that relationship through
wayembed.

## Proof of Concept

[wayembed-sandbox](https://github.com/greenm01/wayembed-sandbox) is a minimal
Nim host used to exercise the C ABI outside this repository. It has smoke
coverage for CLAP, LV2, VST3, display and fd handoffs, C-created plugin
surfaces, and a live VST3 Wayland path using
[nilamp](https://github.com/greenm01/nilamp).

This is still proof work. `wayembed` does not load plugins, scan bundles,
instantiate VST3 components, build LV2 feature arrays, or call CLAP GUI entry
points. Real hosts own those jobs.

[nilrack](https://github.com/greenm01/nilrack) is the planned native Wayland
plugin host that will own that layer.

## Build

Build dependencies are Zig, pkg-config, libwayland client/server development
files, `wayland-scanner`, and `wayland-protocols`.

```sh
zig build
zig build test
```

The build reads `stable/xdg-shell/xdg-shell.xml` from
`/usr/share/wayland-protocols` by default. Override that location when needed:

```sh
zig build -Dwayland-protocols-dir=/path/to/wayland-protocols
```

## Documentation

Start with [docs/README.md](docs/README.md).

Useful entry points:

- [Host Integration](docs/host-integration.md) covers the C ABI flow.
- [Experimental Adapter Contract](docs/adapter-contract.md) covers CLAP, LV2,
  and VST3 handoff rules.
- [VST3 Wayland Notes](docs/vst3.md) covers the strict VST3 3.8 path.
- [TODO](docs/todo.md) is the active backlog.

## License

BSD-3-Clause.
