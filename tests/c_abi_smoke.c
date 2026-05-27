#include "wayplug.h"

#include <stddef.h>
#include <wayland-client.h>

static int connected_count = 0;
static int closed_count = 0;
static wayplug_client *last_client = NULL;

static void on_client_connected(void *userdata, wayplug_client *client)
{
    (void)userdata;
    if (client != NULL) {
        connected_count += 1;
        last_client = client;
    }
}

static void on_client_closed(void *userdata, wayplug_client *client)
{
    (void)userdata;
    if (client != NULL) {
        closed_count += 1;
    }
}

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
    host.on_client_connected = on_client_connected;
    host.on_surface_created = NULL;
    host.on_client_closed = on_client_closed;

    wayplug_server *server = wayplug_server_create(&host, NULL);
    if (server == NULL) {
        return 2;
    }

    if (wayplug_server_get_fd(server) < 0) {
        wayplug_server_destroy(server);
        return 3;
    }

    /* open/close cycle. */
    struct wl_display *display = wayplug_server_open_client_display(server);
    if (display == NULL) {
        wayplug_server_destroy(server);
        return 4;
    }
    if (wl_display_get_fd(display) < 0) {
        wayplug_server_destroy(server);
        return 5;
    }
    wayplug_server_dispatch(server);
    if (connected_count != 1 || last_client == NULL) {
        wayplug_server_destroy(server);
        return 6;
    }
    if (!wayplug_server_close_client_display(server, display)) {
        wayplug_server_destroy(server);
        return 7;
    }
    wayplug_server_dispatch(server);
    if (closed_count != 1) {
        wayplug_server_destroy(server);
        return 8;
    }

    /* Embed operations accept null client opaquely. */
    (void)wayplug_embed_attach(NULL, NULL, NULL);
    (void)wayplug_embed_resize(NULL, 0, 0);

    wayplug_server_destroy(server);
    return 0;
}
