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
 *
 * glibc documents, but does not actually implement, a "getumask(3)"
 * call.
 *
 * We use C<Umask> from F</proc/self/status> for Linux E<ge> 4.7.
 * For older Linux and other Unix, this file implements an expensive
 * but thread-safe way to get the current process's umask.
 *
 * Thanks to: Josh Stone, Jiri Jaburek, Eric Blake.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"

static int get_umask_from_proc (guestfs_h *g);
static int get_umask_from_fork (guestfs_h *g);

/**
 * Returns the current process's umask.  On failure, returns C<-1> and
 * sets the error in the guestfs handle.
 */
int
guestfs_int_getumask (guestfs_h *g)
{
  int mask;

  mask = get_umask_from_proc (g);
  if (mask == -1)
    return -1;
  if (mask >= 0)
    return mask;

  return get_umask_from_fork (g);
}

/**
 * For Linux E<ge> 4.7 get the umask from F</proc/self/status>.
 *
 * On failure this returns C<-1>.  However if we could not open the
 * F</proc> file or find the C<Umask> entry in it, return C<-2> which
 * causes the fallback path to run.
 */
static int
get_umask_from_proc (guestfs_h *g)
{
  CLEANUP_FCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *line = NULL;
  size_t allocsize = 0;
  ssize_t len;
  unsigned int mask;
  bool found = false;

  fp = fopen ("/proc/self/status", "r");
  if (fp == NULL) {
    if (errno == ENOENT || errno == ENOTDIR)
      return -2;                /* fallback */
    perrorf (g, "open: /proc/self/status");
    return -1;
  }

  while ((len = getline (&line, &allocsize, fp)) != -1) {
    if (len > 0 && line[len-1] == '\n')
      line[--len] = '\0';

    /* Looking for: "Umask:  0022" */
    if (sscanf (line, "Umask: %o", &mask) == 1) {
      found = true;
      break;
    }
  }

  if (!found)
    return -2;                  /* fallback */

  return (int) mask;
}

/**
 * Fallback method of getting the umask using fork.
 */
static int
get_umask_from_fork (guestfs_h *g)
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
