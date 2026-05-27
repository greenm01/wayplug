# Design Notes

## Problem

Linux audio plugin UIs historically use native window handles. On X11, a host
can pass a plugin an XID and the plugin can use XEmbed/reparenting-style
mechanisms to draw inside the host.

Wayland does not provide a direct equivalent to XEmbed. Wayland object IDs are
scoped to a client connection, so a raw `wl_surface *` from the host connection
is not automatically meaningful to a plugin using another connection.

## Embedded vs Floating

Embedded and floating plugin UIs should be treated as separate modes.

Embedded UI:

- plugin editor appears inside a host-owned panel, rack, graph node, or device
  slot
- plugin should draw into a child surface/subsurface
- host should control geometry and lifecycle
- this is the main `wayplug` target

Floating UI:

- plugin editor is a separate `xdg_toplevel`
- host and plugin need transient/parent relationship
- `xdg_foreign_unstable_v2` is the likely protocol-level fit
- this may be supported later as a companion path

## Delegated Wayland Connection

The likely architecture is a delegated or nested Wayland server:

1. Host connects to the real session compositor as a Wayland client.
2. Host starts an internal Wayland server.
3. Plugin connects to the host's internal server.
4. Host proxies selected globals and objects to the real compositor.
5. Host can expose a parent surface proxy to the plugin.
6. Plugin creates a subsurface using ordinary Wayland client APIs.

This avoids exposing host process internals as the primary ABI and gives the
plugin a normal Wayland connection to speak to.

## Prior Art

`wayland-server-delegate` implements this general idea in C++:

https://github.com/cclsoftware/wayland-server-delegate

It creates a nested delegating Wayland server and forwards common interfaces
such as `wl_compositor`, `wl_subcompositor`, `wl_surface`, `wl_shm`,
`wl_seat`, `xdg_wm_base`, and Linux dmabuf.

`wayplug` should learn from that design, but expose a C ABI and keep plugin
framework integration explicit.

## Structural Divergence

The C++ reference has no centralized ops layer: each protocol delegate mutates
its own state directly and the `WaylandServer` singleton just tracks per-client
resource lists. `wayplug` introduces an explicit `engine/` layer that owns all
cross-table mutation and the policy decisions above protocol mechanics, while
keeping hot-path forwarding direct in `protocol/`. The cost is one extra
indirection on lifecycle paths; the benefit is a single grep-able place to
find every state transition, which is where delegate libraries usually break.
See [architecture.md](architecture.md) for the layer breakdown.

## Public Boundary

The public API should be C:

- opaque handles
- versioned structs
- explicit ownership
- no C++ ABI
- no Zig/Rust/Nim/Odin-specific public types
- no exposed internal struct layouts unless permanently stable

The initial implementation is Zig. The delivered ABI remains C.
