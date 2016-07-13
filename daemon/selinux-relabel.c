/* libguestfs - the guestfsd daemon
 * Copyright (C) 2016 Red Hat Inc.
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

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

GUESTFSD_EXT_CMD(str_setfiles, setfiles);

#define MAX_ARGS 64

int
optgroup_selinuxrelabel_available (void)
{
  return prog_exists (str_setfiles);
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_selinux_relabel (const char *specfile, const char *path,
                    int force)
{
  const char *argv[MAX_ARGS];
  CLEANUP_FREE char *s_dev = NULL, *s_proc = NULL, *s_selinux = NULL,
    *s_sys = NULL, *s_specfile = NULL, *s_path = NULL;
  CLEANUP_FREE char *err = NULL;
  size_t i = 0;

  s_dev = sysroot_path ("/dev");
  if (!s_dev) {
  malloc_error:
    reply_with_perror ("malloc");
    return -1;
  }
  s_proc = sysroot_path ("/proc");       if (!s_proc) goto malloc_error;
  s_selinux = sysroot_path ("/selinux"); if (!s_selinux) goto malloc_error;
  s_sys = sysroot_path ("/sys");         if (!s_sys) goto malloc_error;
  s_specfile = sysroot_path (specfile);  if (!s_specfile) goto malloc_error;
  s_path = sysroot_path (path);          if (!s_path) goto malloc_error;

  /* Default settings if not selected. */
  if (!(optargs_bitmask & GUESTFS_SELINUX_RELABEL_FORCE_BITMASK))
    force = 0;

  ADD_ARG (argv, i, str_setfiles);
  if (force)
    ADD_ARG (argv, i, "-F");

  /* Exclude some directories that should never be relabelled in
   * ordinary Linux guests.  These won't be mounted anyway.  We have
   * to prefix all these with the sysroot path.
   */
  ADD_ARG (argv, i, "-e"); ADD_ARG (argv, i, s_dev);
  ADD_ARG (argv, i, "-e"); ADD_ARG (argv, i, s_proc);
  ADD_ARG (argv, i, "-e"); ADD_ARG (argv, i, s_selinux);
  ADD_ARG (argv, i, "-e"); ADD_ARG (argv, i, s_sys);

  /* Relabelling in a chroot. */
  if (STRNEQ (sysroot, "/")) {
    ADD_ARG (argv, i, "-r");
    ADD_ARG (argv, i, sysroot);
  }

  /* Suppress non-error output. */
  ADD_ARG (argv, i, "-q");

  /* Add parameters. */
  ADD_ARG (argv, i, s_specfile);
  ADD_ARG (argv, i, s_path);
  ADD_ARG (argv, i, NULL);

  if (commandv (NULL, &err, argv) == -1) {
    reply_with_perror ("%s", err);
    return -1;
  }

  return 0;
}
