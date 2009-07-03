/* guestfish - the filesystem interactive shell
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
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
do_more (const char *cmd, int argc, char *argv[])
{
  char filename[] = "/tmp/guestfishXXXXXX";
  char buf[256];
  const char *pager;
  char *content;
  int r, fd;

  if (argc != 1) {
    fprintf (stderr, _("use '%s filename' to page a file\n"), cmd);
    return -1;
  }

  /* Choose a pager. */
  if (strcasecmp (cmd, "less") == 0)
    pager = "less";
  else {
    pager = getenv ("PAGER");
    if (pager == NULL)
      pager = "more";
  }

  /* Download the file and write it to a temporary. */
  fd = mkstemp (filename);
  if (fd == -1) {
    perror ("mkstemp");
    return -1;
  }

  if ((content = guestfs_cat (g, argv[0])) == NULL) {
    close (fd);
    unlink (filename);
    return -1;
  }

  if (xwrite (fd, content, strlen (content)) == -1) {
    close (fd);
    unlink (filename);
    free (content);
    return -1;
  }

  free (content);

  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    return -1;
  }

  /* View it. */
  /* XXX Safe? */
  snprintf (buf, sizeof buf, "%s %s", pager, filename);

  r = system (buf);
  unlink (filename);
  if (r != 0) {
    perror (buf);
    return -1;
  }

  return 0;
}
