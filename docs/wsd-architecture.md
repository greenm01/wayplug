# wayland-server-delegate Architecture

> *Reference document. Describes the C++ `wayland-server-delegate` prior
> art for context. Not a contract for wayplug; see
> [architecture.md](architecture.md) and [roadmap.md](roadmap.md) for
> what wayplug itself does.*

This note describes the architecture of `wayland-server-delegate` as prior art
for `wayplug`.

`wayland-server-delegate` is not a general nested compositor. It is a selective
Wayland protocol delegator. The host application connects to the real session
compositor, starts an internal Wayland server, and lets plugins or child
processes connect to that internal server.

## High-Level Shape

```text
Plugin UI / child process
        |
        | Wayland client connection
        v
+----------------------------+
| wayland-server-delegate    |
|                            |
| local wl_display           |
| local wl_client            |
| plugin-visible wl_resource |
| resource -> proxy mapping  |
+----------------------------+
        |
        | Wayland client requests on host connection
        v
Host application's real Wayland connection
        |
        v
Session compositor
```

The plugin sees a normal `wl_display *`. Internally, that display is connected
to the host's local server, not directly to the session compositor.

## Host Responsibilities

The host provides an implementation of `IWaylandClientContext`. This context is
the bridge to the host's real Wayland connection.

```text
IWaylandClientContext
  getCompositor()      -> real wl_compositor
  getSubCompositor()   -> real wl_subcompositor
  getSharedMemory()    -> real wl_shm
  getSeat()            -> real wl_seat
  getWindowManager()   -> real xdg_wm_base
  getDmaBuffer()       -> real zwp_linux_dmabuf_v1
  getOutput(index)     -> real wl_output metadata
  getSubSurfaceOffset  -> host-specific surface geometry lookup
```

The delegate library does not discover and own the host's whole Wayland state.
The host is responsible for tracking the real compositor globals and exposing
them through this context interface.

## Startup Flow

```text
Host
  |
  | startup(context)
  v
WaylandServer
  |
  | wl_display_create()
  | wl_display_get_event_loop()
  v
RegistryDelegate
  |
  | wl_global_create(...) for selected globals
  v
Internal server fd returned to host event loop
```

The host must poll the returned server fd and call:

- `dispatch()` when the fd is readable
- `flush()` regularly to send pending events to plugin clients

## Plugin Connection Flow

```text
Host calls openClientConnection()
        |
        v
socketpair(AF_UNIX, SOCK_STREAM)
        |
        +-- fd[0] -> wl_client_create(local_server_display, fd[0])
        |
        +-- fd[1] -> wl_display_connect_to_fd(fd[1])
                         |
                         v
                    returned to plugin as wl_display *
```

The current C++ API returns `wl_display *` directly. For an out-of-process ABI,
a future design would likely expose a connection fd instead.

## Registry Delegation

The internal server advertises globals only if the host context has a matching
real upstream object.

```text
Plugin binds wl_registry global
        |
        v
RegistryDelegate bind<T>()
        |
        v
Create plugin-visible wl_resource
        |
        v
Attach delegate implementation
        |
        v
Delegate stores matching upstream wl_proxy
```

Advertised globals include:

- `wl_compositor`
- `wl_subcompositor`
- `wl_shm`
- `wl_seat`
- `wl_output`
- `xdg_wm_base`
- `zwp_linux_dmabuf_v1`

Notably, the project does not currently implement `xdg_foreign`.

## Resource Mapping

Each delegated object has two sides:

```text
Plugin-visible side              Real compositor side
-------------------              --------------------
wl_resource *        maps to      wl_proxy *
wl_surface resource  maps to      real wl_surface proxy
wl_buffer resource   maps to      real wl_buffer proxy
wl_seat resource     maps to      real wl_seat proxy
```

`WaylandResource` is the common base object that stores this mapping.

```text
WaylandResource
  waylandInterface
  implementation table
  resourceHandle   plugin-visible wl_resource
  clientHandle     local wl_client
  originalProxy    real upstream wl_proxy
  proxyWrapper     optional wl_proxy wrapper for event queue assignment
```

The per-client connection owns a list of these resources:

```text
ClientConnection
  fds[2]
  wl_client *clientHandle
  wl_display *clientDisplay
  resources[]
```

## Request Forwarding

Plugin requests are received by the local server and forwarded to the real
session compositor through the stored upstream proxy.

Example: surface drawing.

```text
Plugin
  wl_surface_attach(plugin_surface, plugin_buffer, x, y)
        |
        v
SurfaceDelegate::onAttach
        |
        | lookup plugin_buffer -> real wl_buffer
        | lookup plugin_surface -> real wl_surface
        v
Host upstream connection
  wl_surface_attach(real_surface, real_buffer, x, y)
        |
        v
Session compositor
```

Example: shared memory buffer creation.

```text
Plugin
  wl_shm_create_pool(fd, size)
        |
        v
SharedMemoryDelegate
  wl_shm_create_pool(real_wl_shm, fd, size)
        |
        v
SharedMemoryPoolDelegate
  wl_shm_pool_create_buffer(...)
        |
        v
BufferDelegate maps plugin wl_buffer to real wl_buffer
```

Example: dmabuf buffer creation.

```text
Plugin
  zwp_linux_dmabuf_v1.create_params()
        |
        v
DmaBufferDelegate
  zwp_linux_dmabuf_v1_create_params(real_dmabuf)
        |
        v
DmaBufferParamsDelegate
  add(fd, plane, offset, stride, modifier)
  create/create_immed(...)
        |
        v
BufferDelegate maps plugin wl_buffer to real wl_buffer
```

## Event Forwarding

Events flow in the opposite direction. Delegate objects attach listeners to real
upstream proxies, then send matching events to plugin-visible resources.

```text
Session compositor
        |
        | event on real wl_proxy
        v
Delegate listener callback
        |
        | translate real object references to plugin resources
        v
wl_*_send_* event on plugin-visible wl_resource
        |
        v
Plugin
```

Examples:

- `wl_buffer.release` is forwarded by `BufferDelegate`
- `wl_callback.done` is forwarded by `CallbackDelegate`
- `wl_surface.enter/leave` is forwarded by `SurfaceDelegate`
- pointer, keyboard, and touch events are forwarded by seat delegates
- `xdg_surface.configure`, `xdg_toplevel.configure`, and popup events are
  forwarded by XDG delegates

## Embedded Surface Flow

Embedding is the most relevant part for plugin UIs.

```text
Host owns real parent wl_surface
        |
        | createProxy(plugin_display, parent_surface, SurfaceDelegate)
        v
Plugin receives plugin-visible parent wl_surface proxy
        |
        | plugin creates child wl_surface
        v
Plugin calls wl_subcompositor_get_subsurface(child, parent)
        |
        v
SubCompositorDelegate
        |
        | child resource -> real child wl_surface
        | parent resource -> real parent wl_surface
        v
wl_subcompositor_get_subsurface(real_child, real_parent)
        |
        v
Session compositor embeds child under host parent
```

This is the key distinction from `xdg_foreign`. `xdg_foreign` can relate
toplevel windows across clients, but it does not create an embedded subsurface.
The delegated server makes both parent and child surfaces meaningful inside one
controlled resource namespace.

## Input Flow

Seat handling creates plugin-visible pointer, keyboard, and touch resources
backed by real upstream seat objects.

```text
Plugin binds wl_seat
        |
        v
SeatDelegate sends capabilities/name
        |
        +-- get_pointer()  -> PointerDelegate
        +-- get_keyboard() -> KeyboardDelegate
        +-- get_touch()    -> TouchDelegate
```

Pointer focus requires extra care for embedded subsurfaces:

```text
Compositor pointer enter on real surface
        |
        v
PointerDelegate finds plugin resource for focused surface
        |
        | if focus is an embedded child:
        |   ask host context for child offset
        v
Send wl_pointer.enter/motion with translated coordinates
```

The host-specific `getSubSurfaceOffset()` hook is what lets the delegate adjust
coordinates when the compositor reports input relative to a parent or sibling
surface relationship.

## XDG Shell Flow

The library also delegates `xdg_wm_base`, `xdg_surface`, `xdg_toplevel`,
`xdg_popup`, and `xdg_positioner`.

This supports normal Wayland toolkit behavior for popups and toplevels, but it
does not by itself solve embedded plugin hosting. The embedded path still goes
through `wl_subsurface`.

```text
Plugin creates wl_surface
        |
        v
xdg_wm_base.get_xdg_surface(surface)
        |
        v
XdgWindowManagerDelegate creates real xdg_surface
        |
        +-- get_toplevel() -> real xdg_toplevel
        |
        +-- get_popup()    -> real xdg_popup
```

For plugin hosting, XDG shell is useful for menus, popups, dialogs, or floating
editors. It is not the primitive that embeds a plugin editor into a host panel.

## Important Limitations

- The public API is C++, not a stable C ABI.
- It exposes abstract classes, virtual methods, inheritance, and singleton
  access.
- It does not provide a complete fd-oriented out-of-process API.
- It implements a selected subset of protocols, not arbitrary Wayland protocol
  forwarding.
- `xdg_foreign` is not implemented.
- Several useful desktop protocols are only mentioned as future candidates:
  data device, decorations, activation, viewporter, keyboard shortcuts inhibit,
  tablet, and text input.

## Lessons For Wayplug

The architecture worth carrying forward:

- host-managed delegated Wayland server
- plugin receives a normal Wayland connection
- per-client table mapping `wl_resource` to upstream `wl_proxy`
- explicit protocol delegates for each supported global/interface
- parent surface proxy for embedded subsurface creation
- event forwarding from upstream listeners to plugin resources
- host callback for geometry/input-coordinate translation

The parts `wayplug` should change:

- expose a stable C ABI instead of a C++ ABI
- use opaque handles and versioned structs
- support fd handoff for out-of-process plugins
- make lifecycle and threading rules explicit
- keep plugin-format adapters separate from the core delegator
- start with a smaller MVP: compositor, subcompositor, surface, shm, buffer,
  callback, seat, and output before dmabuf/XDG expansion
