/* libguestfs
 * Copyright (C) 2009-2013 Red Hat Inc.
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
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

/* In RHEL 6, libguestfs live is not supported. */
static int
launch_unix (guestfs_h *g, const char *sockpath)
{
  error (g,
        "launch: In RHEL 6, \"libguestfs live\" is not supported.");
  return -1;
}

#if 0
/* Alternate attach method: instead of launching the appliance,
 * connect to an existing unix socket.
 */
static int
launch_unix (guestfs_h *g, const char *sockpath)
{
  int r;
  struct sockaddr_un addr;
  uint32_t size;
  void *buf = NULL;

  if (g->qemu_params) {
    error (g, _("cannot set qemu parameters with the 'unix:' attach method"));
    return -1;
  }

  /* Set these to nothing so we don't try to read from random file
   * descriptors.
   */
  g->fd[0] = -1;
  g->fd[1] = -1;

  if (g->verbose)
    guestfs___print_timestamped_message (g, "connecting to %s", sockpath);

  g->sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (g->sock == -1) {
    perrorf (g, "socket");
    return -1;
  }

  addr.sun_family = AF_UNIX;
  strncpy (addr.sun_path, sockpath, UNIX_PATH_MAX);
  addr.sun_path[UNIX_PATH_MAX-1] = '\0';

  g->state = LAUNCHING;

  if (connect (g->sock, &addr, sizeof addr) == -1) {
    perrorf (g, "bind");
    goto cleanup;
  }

  if (fcntl (g->sock, F_SETFL, O_NONBLOCK) == -1) {
    perrorf (g, "fcntl");
    goto cleanup;
  }

  r = guestfs___recv_from_daemon (g, &size, &buf);
  free (buf);

  if (r == -1) return -1;

  if (size != GUESTFS_LAUNCH_FLAG) {
    error (g, _("guestfs_launch failed, unexpected initial message from guestfsd"));
    goto cleanup;
  }

  if (g->verbose)
    guestfs___print_timestamped_message (g, "connected");

  if (g->state != READY) {
    error (g, _("contacted guestfsd, but state != READY"));
    goto cleanup;
  }

  return 0;

 cleanup:
  close (g->sock);
  return -1;
}
#endif

static int
shutdown_unix (guestfs_h *g, int check_for_errors)
{
  /* Merely closing g->sock is sufficient and that is already done
   * in the calling code.
   */
  return 0;
}

struct attach_ops attach_ops_unix = {
  .launch = launch_unix,
  .shutdown = shutdown_unix,
};
