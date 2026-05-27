# wayplug

A small Wayland delegated-server library for hosting plugin UIs without X11
or XEmbed.

`wayplug` lets a host program run an internal Wayland server, hand a plugin
its own connection to that server, and embed the plugin's surface as a
subsurface of a host-owned parent. The public boundary is plain C, so hosts
and plugins in any language can bind to it.

The current target is embedded editors for audio plugin formats such as CLAP
and LV2. Floating plugin windows are a separate problem and are not in
scope yet.

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

See [docs/README.md](docs/README.md).

## License

BSD-3-Clause.
