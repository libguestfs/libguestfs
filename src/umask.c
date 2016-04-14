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

/**
 * Return current umask in a thread-safe way.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"

/**
 * glibc documents, but does not actually implement, a L<getumask(3)>
 * call.
 *
 * This function implements an expensive, but thread-safe way to get
 * the current process's umask.
 *
 * Returns the current process's umask.  On failure, returns C<-1> and
 * sets the error in the guestfs handle.
 *
 * Thanks to: Josh Stone, Jiri Jaburek, Eric Blake.
 */
int
guestfs_int_getumask (guestfs_h *g)
{
  pid_t pid;
  int fd[2], r;
  int mask;
  int status;

  r = pipe2 (fd, O_CLOEXEC);
  if (r == -1) {
    perrorf (g, "pipe2");
    return -1;
  }

  pid = fork ();
  if (pid == -1) {
    perrorf (g, "fork");
    close (fd[0]);
    close (fd[1]);
    return -1;
  }
  if (pid == 0) {
    /* The child process must ONLY call async-safe functions. */
    close (fd[0]);

    /* umask can't fail. */
    mask = umask (0);

    if (write (fd[1], &mask, sizeof mask) != sizeof mask)
      _exit (EXIT_FAILURE);
    if (close (fd[1]) == -1)
      _exit (EXIT_FAILURE);

    _exit (EXIT_SUCCESS);
  }

  /* Parent. */
  close (fd[1]);

  /* Read the umask. */
  if (read (fd[0], &mask, sizeof mask) != sizeof mask) {
    perrorf (g, "read");
    close (fd[0]);
    guestfs_int_waitpid_noerror (pid);
    return -1;
  }
  close (fd[0]);

  if (guestfs_int_waitpid (g, pid, &status, "umask") == -1)
    return -1;
  else if (!WIFEXITED (status) || WEXITSTATUS (status) != 0) {
    guestfs_int_external_command_failed (g, status, "umask", NULL);
    return -1;
  }

  return mask;
}
