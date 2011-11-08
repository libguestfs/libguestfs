/* guestfish - the filesystem interactive shell
 * Copyright (C) 2009-2011 Red Hat Inc.
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
#include <inttypes.h>

#include "fish.h"

int
run_more (const char *cmd, size_t argc, char *argv[])
{
  TMP_TEMPLATE_ON_STACK (filename);
  char buf[256];
  char *remote;
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

  remote = argv[0];

  /* Allow win:... prefix on remote. */
  remote = win_prefix (remote);
  if (remote == NULL)
    return -1;

  /* Download the file and write it to a temporary. */
  fd = mkstemp (filename);
  if (fd == -1) {
    perror ("mkstemp");
    free (remote);
    return -1;
  }

  snprintf (buf, sizeof buf, "/dev/fd/%d", fd);

  if (guestfs_download (g, remote, buf) == -1) {
    close (fd);
    unlink (filename);
    free (remote);
    return -1;
  }

  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    free (remote);
    return -1;
  }

  /* View it. */
  /* XXX Safe? */
  snprintf (buf, sizeof buf, "%s %s", pager, filename);

  r = system (buf);
  unlink (filename);
  if (r != 0) {
    perror (buf);
    free (remote);
    return -1;
  }

  free (remote);
  return 0;
}
