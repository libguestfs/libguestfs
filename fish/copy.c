/* guestfish - guest filesystem shell
 * Copyright (C) 2010-2023 Red Hat Inc.
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
 * This file implements the guestfish commands C<copy-in> and
 * C<copy-out>.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libintl.h>
#include <errno.h>

#include "fish.h"

int
run_copy_in (const char *cmd, size_t argc, char *argv[])
{
  CLEANUP_FREE char *remote = NULL;

  if (argc < 2) {
    fprintf (stderr,
             _("use 'copy-in <local> [<local>...] <remotedir>' to copy files into the image\n"));
    return -1;
  }

  /* Remote directory is always the last arg.
   * Allow "win:" prefix on remote.
   */
  remote = win_prefix (argv[argc-1]);
  if (remote == NULL)
    return -1;

  const int nr_locals = argc-1;

  /* Upload each local one at a time using copy-in. */
  int i;
  for (i = 0; i < nr_locals; ++i) {
    int r = guestfs_copy_in (g, argv[i], remote);
    if (r == -1)
      return -1;
  }

  return 0;
}

int
run_copy_out (const char *cmd, size_t argc, char *argv[])
{
  if (argc < 2) {
    fprintf (stderr,
             _("use 'copy-out <remote> [<remote>...] <localdir>' to copy files out of the image\n"));
    return -1;
  }

  /* Local directory is always the last arg. */
  const char *local = argv[argc-1];
  const int nr_remotes = argc-1;

  /* Download each remote one at a time using copy-out. */
  int i, r;
  for (i = 0; i < nr_remotes; ++i) {
    CLEANUP_FREE char *remote = NULL;

    /* Allow win:... prefix on remotes. */
    remote = win_prefix (argv[i]);
    if (remote == NULL)
      return -1;

    r = guestfs_copy_out (g, remote, local);
    if (r == -1)
      return -1;
  }

  return 0;
}
