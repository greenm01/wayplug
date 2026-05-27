# Experimental Adapter Contract

Phase 3 keeps the core delegated Wayland server format-neutral. Plugin
format glue lives in the experimental adapter surface declared by
`include/wayembed_adapters.h`.

The adapter header intentionally has no CLAP, LV2, or VST3 dependency. Hosts that
already speak those formats translate between format-native objects and the
small wayembed handoff structs.

## Shared Lifecycle

The host creates and owns a normal `wayembed_server`:

1. Call `wayembed_server_open_client_display()` for an in-process plugin UI,
   or `wayembed_server_open_client_fd()` for a plugin UI that connects through
   a process or IPC boundary.
2. Fill a `wayembed_adapter_handoff` with
   `wayembed_adapter_handoff_init()`, or fill a
   `wayembed_adapter_fd_handoff` with `wayembed_adapter_fd_handoff_init()`.
3. Pass `handoff.display` or `handoff.client_fd`, plus
   `handoff.format_token`, through the plugin format's experimental Wayland UI
   path.
4. In `on_surface_created`, attach the plugin child surface with
   `wayembed_embed_attach()` and store the returned `wayembed_embed *`.
5. On host-side editor resize, validate the new size with
   `wayembed_adapter_resize_validate()` and call `wayembed_embed_resize()` on
   that embed handle.
6. Close the client display or destroy the server when the plugin UI exits.

The adapter structs are descriptive. They do not own the display, server,
client, or surfaces. Existing wayembed ownership rules stay in
`wayembed.h`.

The display handoff is for plugins that run in the host process and can accept
a `wl_display *`. The fd handoff is for plugins that must connect from another
process or through IPC. In both cases the host owns the format glue.

`wayembed_adapter_fd_handoff` carries `server`, `client`, and `client_fd` so
host glue can keep the handoff tied to a live wayembed client. Only the fd is a
process payload. Do not marshal `server` or `client` into another process.

## Proven Paths

The Phase 3 proof lives in
[wayembed-sandbox](https://github.com/greenm01/wayembed-sandbox). It is a
Nim host on purpose: it proves the C ABI from outside C and Zig.

The sandbox covers ten paths:

- `abi-smoke` checks adapter handoff and resize validation from Nim.
- `embed-smoke` opens a live host surface, creates one plugin surface, and
  embeds it through `on_surface_created`.
- `fd-embed-smoke` opens a raw client fd, connects a plugin-side display to
  that fd, and embeds the plugin-created surface.
- `clap-order-smoke` checks the CLAP-shaped display handoff order.
- `clap-c-plugin-smoke` passes the CLAP display handoff into a tiny C Wayland
  plugin fixture and embeds the fixture-created surface.
- `lv2-order-smoke` checks the LV2-shaped feature handoff order.
- `lv2-c-plugin-smoke` passes the LV2 display handoff into the C Wayland
  plugin fixture and embeds the fixture-created surface.
- `vst3-order-smoke` checks the VST3-shaped Wayland host connection and
  `WaylandSurfaceID` handoff order.
- `vst3-c-plugin-smoke` passes the VST3 display handoff into the C Wayland
  plugin fixture and embeds the fixture-created surface.
- `adapter-fd-c-plugin-smoke` repeats the C fixture path through fd-backed
  CLAP, LV2, and VST3 handoffs.

Element carries the first opt-in real-host CLAP proof. Its wayembed spike is
off by default, leaves the XEmbed path intact, and checks that the experimental
CLAP token can carry a live wayembed display through the host GUI path. The
visible embedding path is gated separately with `ELEMENT_WAYEMBED_CLAP_EMBED=1`;
stock JUCE 8.0.12 on Linux still reports the missing host parent `wl_surface`
instead of pretending an X11 window can be used. Element can also be built
against the `greenm01/JUCE` `wayland-juce8` fork, which exposes the Wayland
peer state needed for the visible path.

These are proof paths, not plugin loaders. Real CLAP, LV2, and VST3 hosts still own
bundle loading, plugin instantiation, GUI callbacks, and process management.

## Host Responsibilities

wayembed does not load plugins, scan bundles, negotiate CLAP extensions, build
LV2 feature arrays, instantiate VST3 components, or call plugin UI entry points.
The host already owns those jobs.

The adapter contract gives that host a small Wayland payload: a display or fd,
a format token or URI, and resize validation. The host decides when a plugin UI
starts, how the format-native object carries the payload, and when teardown
begins.

Keep all format policy in host glue. Keep wayembed calls in the embedding
layer: create the server, open the plugin display or fd, attach the first
role-less surface the host wants to embed, resize the active embed, and close
the client when the editor ends.

## CLAP Mapping

Use `WAYEMBED_ADAPTER_CLAP_EXPERIMENTAL_API` as the experimental API token.
The token is not a replacement for upstream `CLAP_WINDOW_API_WAYLAND`.

Upstream CLAP currently defines `CLAP_WINDOW_API_WAYLAND`, but its
[`gui.h`](https://github.com/free-audio/clap/blob/main/include/clap/ext/gui.h)
header says Wayland embedding is not supported and floating windows should be
used. The wayembed CLAP mapping is therefore an opt-in experiment between hosts
and plugins that understand the wayembed token.

A CLAP-shaped host should:

- open a wayembed client display before `clap_plugin_gui.create()`;
- pass `handoff.format_token` as the API name and `handoff.display` as the
  Wayland display payload in its experimental glue, or pass
  `fd_handoff.client_fd` through host-owned IPC for out-of-process UIs;
- map plugin resize requests to `wayembed_adapter_resize` plus
  `wayembed_embed_resize()` on the active embed handle.

## LV2 Mapping

Use `WAYEMBED_ADAPTER_LV2_EXPERIMENTAL_URI` as the experimental feature or
UI URI prefix for LV2 glue.

The standard
[LV2 UI extension](https://lv2plug.in/ns/extensions/ui) defines UI classes
such as `ui:X11UI`, toolkit UIs, and feature passing, but it does not define
a standard Wayland UI class. The wayembed LV2 mapping is therefore an external
extension contract, not a standard LV2 UI class.

An LV2-shaped host should:

- advertise the wayembed URI only to UIs that explicitly opt in;
- pass the wayembed display through an LV2 feature payload owned by the
  host, or pass the fd through the host's process boundary;
- keep the actual wayembed calls in host code, not in the core library.

## VST3 Mapping

Use `WAYEMBED_ADAPTER_VST3_PLATFORM_TYPE_WAYLAND_SURFACE_ID` as the VST3
platform type. It maps to the VST3 3.8 Wayland `WaylandSurfaceID` path.

A VST3-shaped host should:

- expose its wayembed display or fd through a host-side Wayland connection
  object;
- pass the host parent `wl_surface` through `IPlugView::attached()` with
  `WaylandSurfaceID`;
- map VST3 resize requests to `wayembed_adapter_resize` plus
  `wayembed_embed_resize()` on the active embed handle.

The wayembed adapter proof does not link the VST3 SDK. Real VST3 hosts still
own component creation, `IPlugView`, `IPlugFrame`, `IWaylandHost`, and
`IWaylandFrame` integration.

## Carla Notes

For a Carla-style host, the adapter layer is thin:

- the Carla plugin-format layer chooses the CLAP token, LV2 URI, or VST3
  platform type;
- the existing host integration path creates the server and opens the
  client display or fd;
- `on_surface_created` still calls `wayembed_embed_attach()` with Carla's
  editor parent surface and stores the returned embed handle;
- Carla window resize still updates host editor dimensions and calls
  `wayembed_embed_resize()` on that handle.

No adapter API in this first slice creates plugin instances, loads bundles,
or dispatches CLAP/LV2/VST3 callbacks. Those responsibilities remain in the
host or in a future format-specific helper.
