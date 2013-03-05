/* libguestfs
 * Copyright (C) 2013 Red Hat Inc.
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

/* Test the guestunmount --fd flag.  Note this is done without
 * requiring libguestfs or guestmount.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

static void display_exit_status (int status, FILE *fp);

int
main (int argc, char *argv[])
{
  int pipefd[2];
  pid_t pid;
  int r, status;

  /* Create the pipe. */
  if (pipe (pipefd) == -1) {
    perror ("pipe");
    exit (EXIT_FAILURE);
  }

  /* Create the guestunmount subprocess. */
  pid = fork ();
  if (pid == -1) {
    perror ("fork");
    exit (EXIT_FAILURE);
  }

  if (pid == 0) {               /* child - guestunmount */
    char fd_str[64];

    close (pipefd[1]);

    snprintf (fd_str, sizeof fd_str, "%d", pipefd[0]);

    execlp ("./guestunmount", "guestunmount", "--fd", fd_str, "/", NULL);
    perror ("execlp");
    _exit (EXIT_FAILURE);
  }

  /* Parent continues. */
  close (pipefd[0]);
  ignore_value (fcntl (pipefd[1], F_SETFD, FD_CLOEXEC));

  /* Sleep a bit and test that the guestunmount process is still running. */
  sleep (2);

  r = waitpid (pid, &status, WNOHANG);
  if (r == -1) {
    perror ("waitpid");
    exit (EXIT_FAILURE);
  }
  if (r != 0) {
    fprintf (stderr, "%s: test failed: guestunmount unexpectedly ", argv[0]);
    display_exit_status (status, stderr);
    fputc ('\n', stderr);
    exit (EXIT_FAILURE);
  }

  /* Close the write side of the pipe.  This should cause guestunmount
   * to exit.  It should exit with status code _2_ because we gave it
   * a mountpoint which isn't a FUSE mountpoint.
   */
  close (pipefd[1]);

  r = waitpid (pid, &status, 0);
  if (r == -1) {
    perror ("waitpid");
    exit (EXIT_FAILURE);
  }
  if (!WIFEXITED (status) || WEXITSTATUS (status) != 2) {
    fprintf (stderr, "%s: test failed: guestunmount didn't return status code 2; instead it ", argv[0]);
    display_exit_status (status, stderr);
    fputc ('\n', stderr);
    exit (EXIT_FAILURE);
  }

  exit (EXIT_SUCCESS);
}

static void
display_exit_status (int status, FILE *fp)
{
  if (WIFEXITED (status))
    fprintf (fp, "exited with status code %d", WEXITSTATUS (status));
  else if (WIFSIGNALED (status)) {
    fprintf (fp, "exited on signal %d", WTERMSIG (status));
    if (WCOREDUMP (status))
      fprintf (fp, " and dumped core");
  }
  else if (WIFSTOPPED (status))
    fprintf (fp, "stopped on signal %d", WSTOPSIG (status));
  else
    fprintf (fp, "<< unknown status %d >>", status);
}
