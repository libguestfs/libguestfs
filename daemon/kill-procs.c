/* libguestfs - the guestfsd daemon
 * Copyright (C) 2026 Red Hat Inc.
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
#include <dirent.h>
#include <signal.h>
#include <unistd.h>
#include <limits.h>

#include "daemon.h"
#include "actions.h"

int
do_kill_procs (void)
{
  DIR *dir;
  struct dirent *d;

  if (sysroot_len == 0)
    return 0;

  dir = opendir ("/proc");
  if (dir == NULL)
    return 0;

  while ((d = readdir (dir)) != NULL) {
    char *endptr;
    long pid;
    char root_link[256];
    char root_target[PATH_MAX];
    ssize_t len;

    pid = strtol (d->d_name, &endptr, 10);
    if (*endptr != '\0' || pid <= 1)
      continue;

    if (pid == (long) getpid ())
      continue;

    snprintf (root_link, sizeof root_link, "/proc/%ld/root", pid);
    len = readlink (root_link, root_target, sizeof root_target - 1);
    if (len == -1)
      continue;
    root_target[len] = '\0';

    if (STREQ (root_target, sysroot)) {
      if (verbose)
        fprintf (stderr, "kill_procs: killing pid %ld (root=%s)\n",
                 pid, root_target);
      kill ((pid_t) pid, SIGKILL);
    }
  }

  closedir (dir);
  return 0;
}
