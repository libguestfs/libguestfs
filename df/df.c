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

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#include "progname.h"

#include "guestfs.h"
#include "options.h"
#include "virt-df.h"

static void try_df (const char *name, const char *uuid, const char *dev, int offset);
static int find_dev_in_devices (const char *dev, char **devices);

/* Since we want this function to be robust against very bad failure
 * cases (hello, https://bugzilla.kernel.org/show_bug.cgi?id=18792) it
 * won't exit on guestfs failures.
 */
int
df_on_handle (const char *name, const char *uuid, char **devices, int offset)
{
  int ret = -1;
  size_t i;
  char **fses = NULL;
  int free_devices = 0, is_lv;

  if (verbose) {
    fprintf (stderr, "df_on_handle %s devices=", name);
    if (devices) {
      fputc ('[', stderr);
      for (i = 0; devices[i] != NULL; ++i) {
        if (i > 0)
          fputc (' ', stderr);
        fputs (devices[i], stderr);
      }
      fputc (']', stderr);
    }
    else
      fprintf (stderr, "null");
    fputc ('\n', stderr);
  }

  if (devices == NULL) {
    devices = guestfs_list_devices (g);
    if (devices == NULL)
      goto cleanup;
    free_devices = 1;
  } else {
    /* Mask LVM for just the devices in the set. */
    if (guestfs_lvm_set_filter (g, devices) == -1)
      goto cleanup;
  }

  /* list-filesystems will return filesystems on every device ... */
  fses = guestfs_list_filesystems (g);
  if (fses == NULL)
    goto cleanup;

  /* ... so we need to filter out only the devices we are interested in. */
  for (i = 0; fses[i] != NULL; i += 2) {
    if (STRNEQ (fses[i+1], "") &&
        STRNEQ (fses[i+1], "swap") &&
        STRNEQ (fses[i+1], "unknown")) {
      is_lv = guestfs_is_lv (g, fses[i]);
      if (is_lv > 0)        /* LVs are OK because of the LVM filter */
        try_df (name, uuid, fses[i], -1);
      else if (is_lv == 0) {
        if (find_dev_in_devices (fses[i], devices))
          try_df (name, uuid, fses[i], offset);
      }
    }
  }

  ret = 0;

 cleanup:
  if (fses) {
    for (i = 0; fses[i] != NULL; ++i)
      free (fses[i]);
    free (fses);
  }

  if (free_devices) {
    for (i = 0; devices[i] != NULL; ++i)
      free (devices[i]);
    free (devices);
  }

  return ret;
}

static int
find_dev_in_devices (const char *dev, char **devices)
{
  size_t i;

  for (i = 0; devices[i] != NULL; ++i) {
    if (STRPREFIX (dev, devices[i]))
      return 1;
  }

  return 0;
}

static void
try_df (const char *name, const char *uuid,
        const char *dev, int offset)
{
  struct guestfs_statvfs *stat = NULL;
  guestfs_error_handler_cb old_error_cb;
  void *old_error_data;

  if (verbose)
    fprintf (stderr, "try_df %s %s %d\n", name, dev, offset);

  /* Try mounting and stating the device.  This might reasonably fail,
   * so don't show errors.
   */
  old_error_cb = guestfs_get_error_handler (g, &old_error_data);
  guestfs_set_error_handler (g, NULL, NULL);

  if (guestfs_mount_ro (g, dev, "/") == 0) {
    stat = guestfs_statvfs (g, "/");
    guestfs_umount_all (g);
  }

  guestfs_set_error_handler (g, old_error_cb, old_error_data);

  if (stat) {
    print_stat (name, uuid, dev, offset, stat);
    guestfs_free_statvfs (stat);
  }
}
