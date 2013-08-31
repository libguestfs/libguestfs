/* libguestfs - guestfish and guestmount shared option parsing
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <libintl.h>

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

    free (drv->device);
    drv->device = NULL;

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
      if (drv->a.cachemode) {
        ad_optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_CACHEMODE_BITMASK;
        ad_optargs.cachemode = drv->a.cachemode;
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

#if COMPILING_GUESTFISH
    case drv_N:
      /* -N option is not affected by --ro */
      r = guestfs_add_drive_opts (g, drv->N.filename,
                                  GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                                  -1);
      if (r == -1)
        exit (EXIT_FAILURE);

      drv->nr_drives = 1;
      next_drive++;
      break;
#endif

    default: /* keep GCC happy */
      abort ();
    }
  }

  return next_drive;
}

static void display_mountpoints_on_failure (const char *mp_device, const char *user_supplied_options);

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

    if (mp->fstype)
      r = guestfs_mount_vfs (g, options, mp->fstype, mp->device,
                             mp->mountpoint);
    else
      r = guestfs_mount_options (g, options, mp->device,
                                 mp->mountpoint);
    if (r == -1) {
      display_mountpoints_on_failure (mp->device, mp->options);
      exit (EXIT_FAILURE);
    }
  }
}

/* If the -m option fails on any command, display a useful error
 * message listing the mountpoints.
 */
static void
display_mountpoints_on_failure (const char *mp_device,
                                const char *user_supplied_options)
{
  CLEANUP_FREE_STRING_LIST char **fses = guestfs_list_filesystems (g);
  size_t i;

  if (fses == NULL || fses[0] == NULL)
    return;

  fprintf (stderr, _("%s: '%s' could not be mounted.\n"),
           program_name, mp_device);

  if (user_supplied_options)
    fprintf (stderr, _("%s: Check mount(8) man page to ensure options '%s'\n"
                       "%s: are supported by the filesystem that is being mounted.\n"),
             program_name, user_supplied_options, program_name);

  fprintf (stderr, _("%s: Did you mean to mount one of these filesystems?\n"),
           program_name);

  for (i = 0; fses[i] != NULL; i += 2) {
    CLEANUP_FREE char *p = guestfs_canonical_device_name (g, fses[i]);
    fprintf (stderr, "%s: \t%s (%s)\n", program_name,
             p ? p : fses[i], fses[i+1]);
  }
}

void
free_drives (struct drv *drv)
{
  if (!drv) return;
  free_drives (drv->next);

  free (drv->device);

  switch (drv->type) {
  case drv_a:
    /* a.filename and a.format are optargs, don't free them */
    /* a.cachemode is a static string, so don't free it */
    break;
  case drv_d: /* d.filename is optarg, don't free it */ break;
#if COMPILING_GUESTFISH
  case drv_N:
    free (drv->N.filename);
    drv->N.data_free (drv->N.data);
    break;
#endif
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
