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

#include "ignore-value.h"

#define MAX_ARGS 64

int
optgroup_selinuxrelabel_available (void)
{
  return prog_exists ("setfiles");
}

static int
setfiles_has_option (int *flag, char opt_char)
{
  CLEANUP_FREE char *err = NULL;

  if (*flag == -1) {
    char option[] = { '-', opt_char, '\0' };       /* "-X" */
    char err_opt[] = { '\'', opt_char, '\'', '\0'}; /* "'X'" */

    ignore_value (command (NULL, &err, "setfiles", option, NULL));
    *flag = err && strstr (err, /* "invalid option -- " */ err_opt) == NULL;
  }

  return *flag;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_selinux_relabel (const char *specfile, const char *path,
                    int force)
{
  static int flag_m = -1;
  static int flag_C = -1;
  const char *argv[MAX_ARGS];
  CLEANUP_FREE char *s_dev = NULL, *s_proc = NULL, *s_selinux = NULL,
    *s_sys = NULL, *s_specfile = NULL, *s_path = NULL;
  CLEANUP_FREE char *err = NULL;
  size_t i = 0;
  int setfiles_status;

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

  /* If setfiles takes an excessively long time to run (but still
   * completes) then removing .../contexts/files/file_contexts.bin
   * appears to help.  If you find any such cases, please add
   * observations to the bug report:
   * https://bugzilla.redhat.com/show_bug.cgi?id=1396297
   */
  ADD_ARG (argv, i, "setfiles");
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

  /* You have to use the -m option (where available) otherwise
   * setfiles puts all the mountpoints on the excludes list for no
   * useful reason (RHBZ#1433577).
   */
  if (setfiles_has_option (&flag_m, 'm'))
    ADD_ARG (argv, i, "-m");

  /* Not only do we want setfiles to trudge through individual relabeling
   * errors, we also want the setfiles exit status to differentiate a fatal
   * error from "relabeling errors only". See RHBZ#1794518.
   */
  if (setfiles_has_option (&flag_C, 'C'))
    ADD_ARG (argv, i, "-C");

  /* Relabelling in a chroot. */
  if (STRNEQ (sysroot, "/")) {
    ADD_ARG (argv, i, "-r");
    ADD_ARG (argv, i, sysroot);
  }

  if (verbose)
    ADD_ARG (argv, i, "-v");
  else
    /* Suppress non-error output. */
    ADD_ARG (argv, i, "-q");

  /* Add parameters. */
  ADD_ARG (argv, i, s_specfile);
  ADD_ARG (argv, i, s_path);
  ADD_ARG (argv, i, NULL);

  setfiles_status = commandrv (NULL, &err, argv);
  if ((setfiles_status == 0) || (setfiles_status == 1 && flag_C))
    return 0;

  reply_with_error ("%s", err);
  return -1;
}
