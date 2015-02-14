/* Test guestmount --fd option.
 * Copyright (C) 2014 Red Hat Inc.
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
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#define GUESTMOUNT_BINARY "./guestmount"
#define GUESTUNMOUNT_BINARY "./guestunmount"
#define TEST_IMAGE "../tests/guests/fedora.img"
#define MOUNTPOINT "test-guestmount-fd.d"
#define TEST_FILE MOUNTPOINT "/etc/fstab"

int
main (int argc, char *argv[])
{
  char *skip;
  int pipefd[2];
  pid_t pid;
  char c;
  int r, status;

  /* Allow the test to be skipped. */
  skip = getenv ("SKIP_TEST_GUESTMOUNT_FD");
  if (skip && guestfs_int_is_true (skip) > 0) {
    fprintf (stderr, "%s: test skipped because environment variable set.\n",
             guestfs_int_program_name);
    exit (77);
  }

  /* Skip the test if the test image can't be found. */
  if (access (TEST_IMAGE, R_OK) == -1) {
    perror (TEST_IMAGE);
    exit (77);
  }

  /* Skip the test if /dev/fuse is not writable, because guestmount
   * will fail.
   */
  if (access ("/dev/fuse", W_OK) == -1) {
    perror ("/dev/fuse");
    exit (77);
  }

  /* Create the pipe. */
  if (pipe (pipefd) == -1) {
    perror ("pipe");
    exit (EXIT_FAILURE);
  }

  /* Create the mount point. */
  ignore_value (rmdir (MOUNTPOINT));
  if (mkdir (MOUNTPOINT, 0700) == -1) {
    perror ("mkdir: " MOUNTPOINT);
    exit (EXIT_FAILURE);
  }

  /* Create the guestmount subprocess. */
  pid = fork ();
  if (pid == -1) {
    perror ("fork");
    exit (EXIT_FAILURE);
  }

  if (pid == 0) {               /* child - guestmount */
    char fd_str[64];

    close (pipefd[0]);

    snprintf (fd_str, sizeof fd_str, "%d", pipefd[1]);

    execlp (GUESTMOUNT_BINARY,
            "guestmount",
            "--fd", fd_str, "--no-fork",
            "--ro", "-a", TEST_IMAGE, "-i", MOUNTPOINT, NULL);
    perror ("execlp");
    _exit (EXIT_FAILURE);
  }

  /* Parent continues. */
  close (pipefd[1]);

  /* Wait for guestmount to start up. */
  r = read (pipefd[0], &c, 1);
  if (r == -1) {
    perror ("read (pipefd)");
    ignore_value (rmdir (MOUNTPOINT));
    exit (EXIT_FAILURE);
  }
  if (r == 0) {
    fprintf (stderr, "%s: unexpected end of file on pipe fd.\n",
             guestfs_int_program_name);
    ignore_value (rmdir (MOUNTPOINT));
    exit (EXIT_FAILURE);
  }

  /* Check that the test image was mounted. */
  if (access (TEST_FILE, R_OK) == -1) {
    fprintf (stderr, "%s: test failed because test image is not mounted and ready.",
             guestfs_int_program_name);
    ignore_value (rmdir (MOUNTPOINT));
    exit (EXIT_FAILURE);
  }

  /* Unmount it. */
  r = system (GUESTUNMOUNT_BINARY " " MOUNTPOINT);
  if (r != 0) {
    char status_string[80];

    fprintf (stderr, "%s: test failed: %s\n", guestfs_int_program_name,
             guestfs_int_exit_status_to_string (r, GUESTUNMOUNT_BINARY,
                                              status_string,
                                              sizeof status_string));
    ignore_value (rmdir (MOUNTPOINT));
    exit (EXIT_FAILURE);
  }

  close (pipefd[0]);

  /* Wait for guestmount to exit, and check it exits cleanly. */
  r = waitpid (pid, &status, 0);
  if (r == -1) {
    perror ("waitpid");
    ignore_value (rmdir (MOUNTPOINT));
    exit (EXIT_FAILURE);
  }
  if (!WIFEXITED (status) || WEXITSTATUS (status) != 0) {
    char status_string[80];

    fprintf (stderr, "%s: test failed: %s\n",
             guestfs_int_program_name,
             guestfs_int_exit_status_to_string (status, GUESTMOUNT_BINARY,
                                              status_string,
                                              sizeof status_string));
    ignore_value (rmdir (MOUNTPOINT));
    exit (EXIT_FAILURE);
  }

  ignore_value (rmdir (MOUNTPOINT));

  exit (EXIT_SUCCESS);
}
