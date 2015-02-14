/* virt-df
 * Copyright (C) 2010-2012 Red Hat Inc.
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
#include <stdint.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>

#include "guestfs.h"
#include "options.h"
#include "domains.h"
#include "virt-df.h"

/* Since we want this function to be robust against very bad failure
 * cases (hello, https://bugzilla.kernel.org/show_bug.cgi?id=18792) it
 * won't exit on guestfs failures.
 */
int
df_on_handle (guestfs_h *g, const char *name, const char *uuid, FILE *fp)
{
  size_t i;
  CLEANUP_FREE_STRING_LIST char **devices = NULL;
  CLEANUP_FREE_STRING_LIST char **fses = NULL;

  if (verbose)
    fprintf (stderr, "df_on_handle: %s\n", name);

  devices = guestfs_list_devices (g);
  if (devices == NULL)
    return -1;

  fses = guestfs_list_filesystems (g);
  if (fses == NULL)
    return -1;

  for (i = 0; fses[i] != NULL; i += 2) {
    if (STRNEQ (fses[i+1], "") &&
        STRNEQ (fses[i+1], "swap") &&
        STRNEQ (fses[i+1], "unknown")) {
      const char *dev = fses[i];
      CLEANUP_FREE_STATVFS struct guestfs_statvfs *stat = NULL;

      if (verbose)
        fprintf (stderr, "df_on_handle: %s dev %s\n", name, dev);

      /* Try mounting and stating the device.  This might reasonably
       * fail, so don't show errors.
       */
      guestfs_push_error_handler (g, NULL, NULL);

      if (guestfs_mount_ro (g, dev, "/") == 0) {
        stat = guestfs_statvfs (g, "/");
        guestfs_umount_all (g);
      }

      guestfs_pop_error_handler (g);

      if (stat)
        print_stat (fp, name, uuid, dev, stat);
    }
  }

  return 0;
}

#if defined(HAVE_LIBVIRT)

/* The multi-threaded version.  This callback is called from the code
 * in "parallel.c".
 */

int
df_work (guestfs_h *g, size_t i, FILE *fp)
{
  struct guestfs_int_add_libvirt_dom_argv optargs;

  optargs.bitmask =
    GUESTFS___ADD_LIBVIRT_DOM_READONLY_BITMASK |
    GUESTFS___ADD_LIBVIRT_DOM_READONLYDISK_BITMASK;
  optargs.readonly = 1;
  optargs.readonlydisk = "read";

  /* Traditionally we have ignored errors from adding disks in virt-df. */
  if (guestfs_int_add_libvirt_dom (g, domains[i].dom, &optargs) == -1)
    return 0;

  if (guestfs_launch (g) == -1)
    return -1;

  return df_on_handle (g, domains[i].name, domains[i].uuid, fp);
}

#endif /* HAVE_LIBVIRT */
