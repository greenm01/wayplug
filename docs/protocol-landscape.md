# Protocol Landscape

## Core Wayland Pieces

Embedded plugin UIs likely need at least:

- `wl_compositor`
- `wl_subcompositor`
- `wl_surface`
- `wl_subsurface`
- `wl_region`
- `wl_callback`
- `wl_shm`
- `wl_seat`
- `wl_pointer`
- `wl_keyboard`
- `wl_touch`
- `wl_output`
- `xdg_wm_base`
- `xdg_surface`
- `xdg_popup`
- `linux-dmabuf` eventually

The MVP should start with shared-memory rendering before dmabuf.

## xdg_foreign_unstable_v2

`xdg_foreign_unstable_v2` lets one client export a toplevel surface as an
opaque string handle and another client import that handle. The importing
client can set its own toplevel as a child/transient of the imported toplevel.

This is useful for floating plugin editors and out-of-process dialogs.

It is not sufficient for embedded plugin UIs because it does not let a plugin
draw inside a host surface.

## Subsurfaces

`wl_subsurface` is the natural Wayland primitive for embedded UI composition.
The plugin should create a child `wl_surface` and attach it as a subsurface of a
host-provided parent surface.

The difficult part is making the parent surface meaningful to the plugin in a
way that fits plugin ABI constraints. A delegated Wayland server/proxy can
solve this by giving the plugin a host-controlled Wayland connection.

## Plugin Formats

CLAP currently defines `CLAP_WINDOW_API_WAYLAND`, but does not define the
meaning of the Wayland window pointer or a complete embedding contract.

LV2 has `LV2_UI__parent` and UI classes such as `ui:X11UI`, but no widely
adopted `WaylandUI` standard.

VST3 has preliminary Wayland support through `IWaylandFrame`, reportedly using
a proxy/nested-compositor style approach.

`wayembed` should be format-neutral at the core and provide CLAP/LV2 adapters as
separate layers.
