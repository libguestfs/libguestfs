/* libguestfs
 * Copyright (C) 2009-2016 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>  /* sockaddr_un */
#include <string.h>
#include <libintl.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs_protocol.h"

/* Alternate backend: instead of launching the appliance,
 * connect to an existing unix socket.
 */

static int
launch_unix (guestfs_h *g, void *datav, const char *sockpath)
{
  error (g,
	 "launch: In RHEL, only the 'libvirt' or 'direct' method is supported.\n"
	 "In particular, \"libguestfs live\" is not supported.");
  return -1;

#if 0
  int r, daemon_sock = -1;
  struct sockaddr_un addr;
  uint32_t size;
  void *buf = NULL;

  if (g->hv_params) {
    error (g, _("cannot set hv parameters with the 'unix:' backend"));
    return -1;
  }

  if (strlen (sockpath) > UNIX_PATH_MAX-1) {
    error (g, _("socket filename too long (more than %d characters): %s"),
           UNIX_PATH_MAX-1, sockpath);
    return -1;
  }

  if (g->verbose)
    guestfs_int_print_timestamped_message (g, "connecting to %s", sockpath);

  daemon_sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (daemon_sock == -1) {
    perrorf (g, "socket");
    return -1;
  }

  addr.sun_family = AF_UNIX;
  strncpy (addr.sun_path, sockpath, UNIX_PATH_MAX);
  addr.sun_path[UNIX_PATH_MAX-1] = '\0';

  g->state = LAUNCHING;

  if (connect (daemon_sock, (struct sockaddr *) &addr, sizeof addr) == -1) {
    perrorf (g, "bind");
    goto cleanup;
  }

  g->conn = guestfs_int_new_conn_socket_connected (g, daemon_sock, -1);
  if (!g->conn)
    goto cleanup;

  /* g->conn now owns this socket. */
  daemon_sock = -1;

  r = guestfs_int_recv_from_daemon (g, &size, &buf);
  free (buf);

  if (r == -1) goto cleanup;

  if (size != GUESTFS_LAUNCH_FLAG) {
    error (g, _("guestfs_launch failed, unexpected initial message from guestfsd"));
    goto cleanup;
  }

  if (g->verbose)
    guestfs_int_print_timestamped_message (g, "connected");

  if (g->state != READY) {
    error (g, _("contacted guestfsd, but state != READY"));
    goto cleanup;
  }

  return 0;

 cleanup:
  if (daemon_sock >= 0)
    close (daemon_sock);
  if (g->conn) {
    g->conn->ops->free_connection (g, g->conn);
    g->conn = NULL;
  }
  return -1;
#endif
}

static int
shutdown_unix (guestfs_h *g, void *datav, int check_for_errors)
{
  /* Merely closing g->daemon_sock is sufficient and that is already done
   * in the calling code.
   */
  return 0;
}

static struct backend_ops backend_unix_ops = {
  .data_size = 0,
  .launch = launch_unix,
  .shutdown = shutdown_unix,
};

void
guestfs_int_init_unix_backend (void)
{
  guestfs_int_register_backend ("unix", &backend_unix_ops);
}
