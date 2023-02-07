/* guestfish - guest filesystem shell
 * Copyright (C) 2009-2023 Red Hat Inc.
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

/**
 * This file implements the guestfish C<more> command.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <inttypes.h>
#include <libintl.h>

#include "fish.h"

int
run_more (const char *cmd, size_t argc, char *argv[])
{
  CLEANUP_FREE char *tmpdir = guestfs_get_tmpdir (g);
  CLEANUP_UNLINK_FREE char *filename = NULL;
  char buf[256];
  CLEANUP_FREE char *remote = NULL;
  const char *pager;
  int r, fd;

  if (argc != 1) {
    fprintf (stderr, _("use '%s filename' to page a file\n"), cmd);
    return -1;
  }

  /* Choose a pager. */
  if (STRCASEEQ (cmd, "less"))
    pager = "less";
  else {
    pager = getenv ("PAGER");
    if (pager == NULL)
      pager = "more";
  }

  /* Allow win:... prefix on remote. */
  remote = win_prefix (argv[0]);
  if (remote == NULL)
    return -1;

  /* Download the file and write it to a temporary. */
  if (asprintf (&filename, "%s/guestfishXXXXXX", tmpdir) == -1) {
    perror ("asprintf");
    return -1;
  }

  fd = mkstemp (filename);
  if (fd == -1) {
    perror ("mkstemp");
    return -1;
  }

  snprintf (buf, sizeof buf, "/dev/fd/%d", fd);

  if (guestfs_download (g, remote, buf) == -1) {
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    perror (filename);
    return -1;
  }

  /* View it. */
  /* XXX Safe? */
  snprintf (buf, sizeof buf, "%s %s", pager, filename);

  r = system (buf);
  if (r != 0) {
    perror (buf);
    return -1;
  }

  return 0;
}
