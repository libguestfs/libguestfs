/* libguestfs - guestfish and guestmount shared option parsing
 * Copyright (C) 2010-2011 Red Hat Inc.
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

#include "c-ctype.h"

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

    if (asprintf (&drv->device, "/dev/sd%c", next_drive) == -1) {
      perror ("asprintf");
      exit (EXIT_FAILURE);
    }

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

      drv->nr_drives = 1;
      next_drive++;
      break;

    case drv_d:
      r = add_libvirt_drives (drv->d.guest);
      if (r == -1)
        exit (EXIT_FAILURE);

      drv->nr_drives = r;
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

      drv->nr_drives = 1;
      next_drive++;
      break;

    default: /* keep GCC happy */
      abort ();
    }
  }

  return next_drive;
}

static void display_mountpoints_on_failure (const char *mp_device);
static void canonical_device_name (char *dev);

/* List is built in reverse order, so mount them in reverse order. */
void
mount_mps (struct mp *mp)
{
  int r;

  if (mp) {
    mount_mps (mp->next);

    const char *options;
    if (mp->options)
      options = mp->options;
    else if (read_only)
      options = "ro";
    else
      options = "";

    /* Don't use guestfs_mount here because that will default to mount
     * options -o sync,noatime.  For more information, see guestfs(3)
     * section "LIBGUESTFS GOTCHAS".
     */
    r = guestfs_mount_options (g, options, mp->device, mp->mountpoint);
    if (r == -1) {
      display_mountpoints_on_failure (mp->device);
      exit (EXIT_FAILURE);
    }
  }
}

/* If the -m option fails on any command, display a useful error
 * message listing the mountpoints.
 */
static void
display_mountpoints_on_failure (const char *mp_device)
{
  char **fses;
  size_t i;

  fses = guestfs_list_filesystems (g);
  if (fses == NULL)
    return;
  if (fses[0] == NULL) {
    free (fses);
    return;
  }

  fprintf (stderr,
           _("%s: '%s' could not be mounted.  Did you mean one of these?\n"),
           program_name, mp_device);

  for (i = 0; fses[i] != NULL; i += 2) {
    canonical_device_name (fses[i]);
    fprintf (stderr, "\t%s (%s)\n", fses[i], fses[i+1]);
    free (fses[i]);
    free (fses[i+1]);
  }

  free (fses);
}

static void
canonical_device_name (char *dev)
{
  if (STRPREFIX (dev, "/dev/") &&
      (dev[5] == 'h' || dev[5] == 'v') &&
      dev[6] == 'd' &&
      c_isalpha (dev[7]) &&
      (c_isdigit (dev[8]) || dev[8] == '\0'))
    dev[5] = 's';
}

void
free_drives (struct drv *drv)
{
  if (!drv) return;
  free_drives (drv->next);

  free (drv->device);

  switch (drv->type) {
  case drv_a: /* a.filename and a.format are optargs, don't free them */ break;
  case drv_d: /* d.filename is optarg, don't free it */ break;
  case drv_N:
    free (drv->N.filename);
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
