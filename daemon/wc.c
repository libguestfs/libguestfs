/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

static int
wc (const char *flag, const char *path)
{
  char *out, *err;
  int fd, flags, r;

  CHROOT_IN;
  fd = open (path, O_RDONLY|O_CLOEXEC);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("wc %s: %s", flag, path);
    return -1;
  }

  flags = COMMAND_FLAG_CHROOT_COPY_FILE_TO_STDIN | fd;
  r = commandf (&out, &err, flags, "wc", flag, NULL);
  if (r == -1) {
    reply_with_error ("wc %s: %s", flag, err);
    free (out);
    free (err);
    return -1;
  }

  free (err);

#if 0
  /* Split it at the first whitespace. */
  len = strcspn (out, " \t\n");
  out[len] = '\0';
#endif

  /* Parse the number. */
  if (sscanf (out, "%d", &r) != 1) {
    reply_with_error ("cannot parse number: %s", out);
    free (out);
    return -1;
  }

  free (out);
  return r;
}

int
do_wc_l (const char *path)
{
  return wc ("-l", path);
}

int
do_wc_w (const char *path)
{
  return wc ("-w", path);
}

int
do_wc_c (const char *path)
{
  return wc ("-c", path);
}
