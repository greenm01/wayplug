# Plugin UI Fallbacks

Native Wayland is the preferred path. It keeps the plugin editor inside the
host's Wayland scene, lets `wayembed` own the delegated server, and avoids a
second windowing stack.

Many plugins will not take that path soon. Some expose parameters but no native
Wayland editor. Some ship an X11 editor. Some ship a toolkit editor that works
only in a floating window. A host still has to show something useful.

This document sets the fallback boundary. The host owns fallback policy.
`wayembed` stays the native Wayland embed layer.

## Decision Order

A host should choose the editor path in this order:

1. Native Wayland plugin UI through `wayembed`.
2. Host-owned generated controls.
3. Host-owned XWayland containment for legacy editors.
4. No editor, with a clear host-side error or disabled editor action.

The order matters. Generated controls are boring, but they are predictable.
XWayland can save a legacy editor, but it brings focus, scaling, lifetime, and
window-management problems that do not belong in `wayembed` core.

## Generated Controls

Generated controls are a host UI built from plugin metadata. They are not a
plugin's native editor.

For CLAP, the host can read parameter metadata through CLAP parameter
extensions. For LV2, it can read ports, ranges, units, groups, and related RDF
data. For VST3, it can query parameters from the edit controller. Each format
has its own rules. The host already knows those rules because it loads and runs
the plugin.

`wayembed` should not become a parameter UI toolkit. It should not render
sliders, menus, meters, preset browsers, or automation lanes. It should not
learn CLAP, LV2, or VST3 parameter models. That work lives in the host.

The adapter layer can still help with the choice. A host can use
`wayembed_get_features()`, `wayembed_adapter_handoff_validate()`,
`wayembed_adapter_fd_handoff_validate()`, and
`wayembed_adapter_resize_validate()` to decide whether a native path is ready.
If the plugin does not opt in, the host falls back to generated controls.

Generated controls should use host widgets and host state. They should not open
a wayembed client connection. No plugin surface exists in this path, so there
is nothing to attach with `wayembed_embed_attach()`.

## XWayland Containment

XWayland containment is a host strategy for old plugin editors. It is not part
of the `wayembed` delegated server.

The host may run an X11 plugin editor under XWayland, find or create the editor
window, and place that window inside a host-owned container. The details depend
on the host toolkit, compositor, and plugin process model. Some hosts can embed
an X11 child window. Some can only manage a floating tool window. Some should
refuse the editor and show generated controls instead.

`wayembed` should not proxy X11. It should not speak XEmbed. It should not map
X11 windows into Wayland surfaces. It should not add X11 lifetime rules to the
core data model.

The host can still run `wayembed` beside an XWayland fallback. A native
Wayland-capable plugin uses the delegated server. A legacy plugin uses the
host's XWayland path. The adapter code decides which route to take before it
opens the editor.

## Failure Rules

Fallbacks need clean failure behavior.

If native Wayland setup fails before a plugin connects, close the wayembed
client display or fd and show generated controls. If a plugin connects but
never creates a usable surface, close that client and show generated controls.
If XWayland containment cannot find or hold the editor window, tear it down and
show generated controls. Do not leave a hidden plugin UI process running.

When the host does show generated controls, it should say so in host logs. The
plugin did not use the native UI path. That is useful evidence when a real
plugin later claims Wayland support.

## API Boundary

The current adapter helpers cover shared setup and validation:

- initialize and validate display handoffs;
- initialize and validate fd handoffs;
- validate embed resize requests;
- name the CLAP, LV2, and VST3 handoff tokens.

Do not add new helper APIs for generated controls until a real host repeats the
same code across formats. Do not add XWayland helper APIs to `wayembed` core.
If a host needs XWayland helpers, put them in host glue or a separate legacy UI
library.
