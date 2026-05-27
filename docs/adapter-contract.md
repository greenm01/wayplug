# Experimental Adapter Contract

Phase 3 keeps the core delegated Wayland server format-neutral. Plugin
format glue lives in the experimental adapter surface declared by
`include/wayembed_adapters.h`.

The adapter header intentionally has no CLAP or LV2 dependency. Hosts that
already speak those formats translate between format-native objects and the
small wayembed handoff structs.

## Shared Lifecycle

The host creates and owns a normal `wayembed_server`:

1. Call `wayembed_server_open_client_display()` when the plugin UI is about
   to be created.
2. Fill a `wayembed_adapter_handoff` with
   `wayembed_adapter_handoff_init()`.
3. Pass `handoff.display` and `handoff.format_token` through the plugin
   format's experimental Wayland UI path.
4. In `on_surface_created`, attach the plugin child surface with
   `wayembed_embed_attach()` and store the returned `wayembed_embed *`.
5. On host-side editor resize, validate the new size with
   `wayembed_adapter_resize_validate()` and call `wayembed_embed_resize()` on
   that embed handle.
6. Close the client display or destroy the server when the plugin UI exits.

The adapter structs are descriptive. They do not own the display, server,
client, or surfaces. Existing wayembed ownership rules stay in
`wayembed.h`.

The starter adapter handoff is display-oriented. Hosts that need a separate
plugin process should use `wayembed_server_open_client_fd()` in their
format-specific glue and pass the fd through that process contract.

## Proven Paths

The Phase 3 proof lives in
[wayembed-sandbox](https://github.com/greenm01/wayembed-sandbox). It is a
Nim host on purpose: it proves the C ABI from outside C and Zig.

The sandbox covers four paths:

- `abi-smoke` checks adapter handoff and resize validation from Nim.
- `embed-smoke` opens a live host surface, creates one plugin surface, and
  embeds it through `on_surface_created`.
- `clap-order-smoke` checks the CLAP-shaped display handoff order.
- `lv2-order-smoke` checks the LV2-shaped feature handoff order.

These are proof paths, not plugin loaders. Real CLAP and LV2 hosts still own
bundle loading, plugin instantiation, GUI callbacks, and process management.

## Host Responsibilities

wayembed does not load plugins, scan bundles, negotiate CLAP extensions, build
LV2 feature arrays, or call plugin UI entry points. The host already owns those
jobs.

The adapter contract gives that host a small Wayland payload: a display, a
format token or URI, and resize validation. The host decides when a plugin UI
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
  Wayland display payload in its experimental glue;
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
  host;
- keep the actual wayembed calls in host code, not in the core library.

## Carla Notes

For a Carla-style host, the adapter layer is thin:

- the Carla plugin-format layer chooses the CLAP token or LV2 URI;
- the existing host integration path creates the server and opens the
  client display;
- `on_surface_created` still calls `wayembed_embed_attach()` with Carla's
  editor parent surface and stores the returned embed handle;
- Carla window resize still updates host editor dimensions and calls
  `wayembed_embed_resize()` on that handle.

No adapter API in this first slice creates plugin instances, loads bundles,
or dispatches CLAP/LV2 callbacks. Those responsibilities remain in the host
or in a future format-specific helper.
