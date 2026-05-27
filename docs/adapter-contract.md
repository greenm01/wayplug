# Experimental Adapter Contract

Phase 3 keeps the core delegated Wayland server format-neutral. Plugin
format glue lives in the experimental adapter surface declared by
`include/wayplug_adapters.h`.

The adapter header intentionally has no CLAP or LV2 dependency. Hosts that
already speak those formats translate between format-native objects and the
small wayplug handoff structs.

## Shared Lifecycle

The host creates and owns a normal `wayplug_server`:

1. Call `wayplug_server_open_client_display()` when the plugin UI is about
   to be created.
2. Fill a `wayplug_adapter_handoff` with
   `wayplug_adapter_handoff_init()`.
3. Pass `handoff.display` and `handoff.format_token` through the plugin
   format's experimental Wayland UI path.
4. In `on_surface_created`, attach the plugin child surface with
   `wayplug_embed_attach()`.
5. On host-side editor resize, validate the new size with
   `wayplug_adapter_resize_validate()` and call `wayplug_embed_resize()`.
6. Close the client display or destroy the server when the plugin UI exits.

The adapter structs are descriptive. They do not own the display, server,
client, or surfaces. Existing wayplug ownership rules stay in
`wayplug.h`.

## CLAP Mapping

Use `WAYPLUG_ADAPTER_CLAP_EXPERIMENTAL_API` as the experimental API token.
The token is not a replacement for upstream `CLAP_WINDOW_API_WAYLAND`.

Upstream CLAP currently defines `CLAP_WINDOW_API_WAYLAND`, but its
[`gui.h`](https://github.com/free-audio/clap/blob/main/include/clap/ext/gui.h)
header says Wayland embedding is not supported and floating windows should be
used. The wayplug CLAP mapping is therefore an opt-in experiment between hosts
and plugins that understand the wayplug token.

A CLAP-shaped host should:

- open a wayplug client display before `clap_plugin_gui.create()`;
- pass `handoff.format_token` as the API name and `handoff.display` as the
  Wayland display payload in its experimental glue;
- map plugin resize requests to `wayplug_adapter_resize` plus
  `wayplug_embed_resize()`.

## LV2 Mapping

Use `WAYPLUG_ADAPTER_LV2_EXPERIMENTAL_URI` as the experimental feature or
UI URI prefix for LV2 glue.

The standard
[LV2 UI extension](https://lv2plug.in/ns/extensions/ui) defines UI classes
such as `ui:X11UI`, toolkit UIs, and feature passing, but it does not define
a standard Wayland UI class. The wayplug LV2 mapping is therefore an external
extension contract, not a standard LV2 UI class.

An LV2-shaped host should:

- advertise the wayplug URI only to UIs that explicitly opt in;
- pass the wayplug display through an LV2 feature payload owned by the
  host;
- keep the actual wayplug calls in host code, not in the core library.

## Carla Notes

For a Carla-style host, the adapter layer is thin:

- the Carla plugin-format layer chooses the CLAP token or LV2 URI;
- the existing host integration path creates the server and opens the
  client display;
- `on_surface_created` still calls `wayplug_embed_attach()` with Carla's
  editor parent surface;
- Carla window resize still updates host editor dimensions and calls
  `wayplug_embed_resize()`.

No adapter API in this first slice creates plugin instances, loads bundles,
or dispatches CLAP/LV2 callbacks. Those responsibilities remain in the host
or in a future format-specific helper.
