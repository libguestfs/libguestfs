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
 * This file implements the guestfish C<alloc> and C<sparse> commands.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <inttypes.h>
#include <errno.h>
#include <libintl.h>

#include "xstrtol.h"

#include "fish.h"

int
run_alloc (const char *cmd, size_t argc, char *argv[])
{
  if (argc != 2) {
    fprintf (stderr, _("use 'alloc file size' to create an image\n"));
    return -1;
  }

  if (alloc_disk (argv[0], argv[1], 1, 0) == -1)
    return -1;

  return 0;
}

int
run_sparse (const char *cmd, size_t argc, char *argv[])
{
  if (argc != 2) {
    fprintf (stderr, _("use 'sparse file size' to create a sparse image\n"));
    return -1;
  }

  if (alloc_disk (argv[0], argv[1], 1, 1) == -1)
    return -1;

  return 0;
}

/**
 * This is the underlying allocation function.  It's called from
 * a few other places in guestfish.
 */
int
alloc_disk (const char *filename, const char *size_str, int add, int sparse)
{
  off_t size;
  const char *prealloc = sparse ? "sparse" : "full";

  if (parse_size (size_str, &size) == -1)
    return -1;

  if (guestfs_disk_create (g, filename, "raw", (int64_t) size,
                           GUESTFS_DISK_CREATE_PREALLOCATION, prealloc,
                           -1) == -1)
    return -1;

  if (add) {
    if (guestfs_add_drive_opts (g, filename,
                                GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                                -1) == -1) {
      unlink (filename);
      return -1;
    }
  }

  return 0;
}

int
parse_size (const char *str, off_t *size_rtn)
{
  unsigned long long size;
  strtol_error xerr;

  xerr = xstrtoull (str, NULL, 0, &size, "0kKMGTPEZY");
  if (xerr != LONGINT_OK) {
    fprintf (stderr,
             _("%s: invalid integer parameter (%s returned %u)\n"),
             "parse_size", "xstrtoull", xerr);
    return -1;
  }

  /* XXX 32 bit file offsets, if anyone uses them?  GCC should give
   * a warning here anyhow.
   */
  *size_rtn = size;

  return 0;
}
