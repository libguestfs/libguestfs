/* libguestfs
 * Copyright (C) 2016 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/wait.h>

#include "guestfs.h"
#include "guestfs-internal.h"

/**
 * A safe version of L<waitpid(3)> which retries if C<EINTR> is
 * returned.
 *
 * I<Note:> this only needs to be used in the library, or in programs
 * that install a non-restartable C<SIGCHLD> handler (which is not the
 * case for any current libguestfs virt tools).
 *
 * If the main program installs a SIGCHLD handler and sets it to be
 * non-restartable, then what can happen is the library is waiting in
 * a wait syscall, the child exits, C<SIGCHLD> is sent to the process,
 * and the wait syscall returns C<EINTR>.  Since the library cannot
 * control the signal handler, we have to instead restart the wait
 * syscall, which is the purpose of this wrapper.
 */
int
guestfs_int_waitpid (guestfs_h *g, pid_t pid, int *status, const char *errmsg)
{
 again:
  if (waitpid (pid, status, 0) == -1) {
    if (errno == EINTR)
      goto again;
    perrorf (g, "%s: waitpid", errmsg);
    return -1;
  }
  return 0;
}

/**
 * Like C<guestfs_int_waitpid>, but ignore errors.
 */
void
guestfs_int_waitpid_noerror (pid_t pid)
{
  while (waitpid (pid, NULL, 0) == -1 && errno == EINTR)
    ;
}

/**
 * A safe version of L<wait4(2)> which retries if C<EINTR> is
 * returned.
 */
int
guestfs_int_wait4 (guestfs_h *g, pid_t pid, int *status,
                   struct rusage *rusage, const char *errmsg)
{
 again:
  if (wait4 (pid, status, 0, rusage) == -1) {
    if (errno == EINTR)
      goto again;
    perrorf (g, "%s: wait4", errmsg);
    return -1;
  }
  return 0;
}
