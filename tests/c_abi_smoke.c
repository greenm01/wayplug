#include "wayplug.h"

#include <stddef.h>

int main(void)
{
    if (wayplug_abi_version() != WAYPLUG_ABI_VERSION) {
        return 1;
    }

    wayplug_host_interface host;
    host.size = sizeof(host);
    host.version = WAYPLUG_ABI_VERSION;
    host.userdata = NULL;
    host.get_compositor = NULL;
    host.get_subcompositor = NULL;
    host.get_shm = NULL;
    host.get_seat = NULL;
    host.get_xdg_wm_base = NULL;
    host.get_dmabuf = NULL;
    host.get_subsurface_offset = NULL;
    host.on_client_connected = NULL;
    host.on_surface_created = NULL;
    host.on_client_closed = NULL;

    wayplug_server *server = wayplug_server_create(&host, NULL);
    if (server == NULL) {
        return 2;
    }

    if (wayplug_server_get_fd(server) != -1) {
        wayplug_server_destroy(server);
        return 3;
    }

    /* open/close cycle. Stubbed today; returns NULL/false. The point is
     * to exercise the symbols and confirm balanced calls are tolerated. */
    struct wl_display *display = wayplug_server_open_client_display(server);
    (void)wayplug_server_close_client_display(server, display);

    /* Embed operations accept null client opaquely. */
    (void)wayplug_embed_attach(NULL, NULL, NULL);
    (void)wayplug_embed_resize(NULL, 0, 0);

    wayplug_server_destroy(server);
    return 0;
}
