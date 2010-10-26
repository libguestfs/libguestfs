/* libguestfs - guestfish and guestmount shared option parsing
 * Copyright (C) 2010 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>

#include "guestfs.h"

#include "options.h"

char
add_drives (struct drv *drv, char next_drive)
{
  int r;
  struct guestfs_add_drive_opts_argv ad_optargs;

  if (next_drive > 'z') {
    fprintf (stderr,
             _("%s: too many drives added on the command line\n"),
             program_name);
    exit (EXIT_FAILURE);
  }

  if (drv) {
    next_drive = add_drives (drv->next, next_drive);

    switch (drv->type) {
    case drv_a:
      ad_optargs.bitmask = 0;
      if (read_only) {
        ad_optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK;
        ad_optargs.readonly = 1;
      }
      if (drv->a.format) {
        ad_optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK;
        ad_optargs.format = drv->a.format;
      }
      r = guestfs_add_drive_opts_argv (g, drv->a.filename, &ad_optargs);
      if (r == -1)
        exit (EXIT_FAILURE);

      next_drive++;
      break;

    case drv_d:
      r = add_libvirt_drives (drv->d.guest);
      if (r == -1)
        exit (EXIT_FAILURE);

      next_drive += r;
      break;

    case drv_N:
      /* guestfs_add_drive (ie. autodetecting) should be safe here
       * since we have just created the prepared disk.  At the moment
       * it will always be "raw" but in a theoretical future we might
       * create other formats.
       */
      /* -N option is not affected by --ro */
      r = guestfs_add_drive (g, drv->N.filename);
      if (r == -1)
        exit (EXIT_FAILURE);

      if (asprintf (&drv->N.device, "/dev/sd%c", next_drive) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }

      next_drive++;
      break;

    default: /* keep GCC happy */
      abort ();
    }
  }

  return next_drive;
}

/* List is built in reverse order, so mount them in reverse order. */
void
mount_mps (struct mp *mp)
{
  int r;

  if (mp) {
    mount_mps (mp->next);

    /* Don't use guestfs_mount here because that will default to mount
     * options -o sync,noatime.  For more information, see guestfs(3)
     * section "LIBGUESTFS GOTCHAS".
     */
    const char *options = read_only ? "ro" : "";
    r = guestfs_mount_options (g, options, mp->device, mp->mountpoint);
    if (r == -1) {
      /* Display possible mountpoints before exiting. */
      char **fses = guestfs_list_filesystems (g);
      if (fses == NULL || fses[0] == NULL)
        goto out;
      fprintf (stderr,
               _("%s: '%s' could not be mounted.  Did you mean one of these?\n"),
               program_name, mp->device);
      size_t i;
      for (i = 0; fses[i] != NULL; i += 2)
        fprintf (stderr, "\t%s (%s)\n", fses[i], fses[i+1]);

    out:
      exit (EXIT_FAILURE);
    }
  }
}

void
free_drives (struct drv *drv)
{
  if (!drv) return;
  free_drives (drv->next);

  switch (drv->type) {
  case drv_a: /* a.filename and a.format are optargs, don't free them */ break;
  case drv_d: /* d.filename is optarg, don't free it */ break;
  case drv_N:
    free (drv->N.filename);
    free (drv->N.device);
    drv->N.data_free (drv->N.data);
    break;
  default: ;                    /* keep GCC happy */
  }
  free (drv);
}

void
free_mps (struct mp *mp)
{
  if (!mp) return;
  free_mps (mp->next);

  /* The drive and mountpoint fields are not allocated
   * from the heap, so we should not free them here.
   */

  free (mp);
}
