/* libguestfs-test-tool-helper
 * Copyright (C) 2009 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

/* NB. This program is intended to run inside the appliance. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>

char buffer[10 * 1024];

int
main (void)
{
  int fd;

  fprintf (stderr, "This is the libguestfs-test-tool helper program.\n");

  /* This should fail immediately if we're not in the appliance. */
  if (mkdir ("/tmp", 0700) == -1) {
    perror ("mkdir");
    fprintf (stderr, "This program should not be run directly.  Use libguestfs-test-tool instead.\n");
    exit (EXIT_FAILURE);
  }

  if (geteuid () != 0) {
    fprintf (stderr, "helper: This program doesn't appear to be running as root.\n");
    exit (EXIT_FAILURE);
  }

  if (mkdir ("/tmp/helper", 0700) == -1) {
    perror ("/tmp/helper");
    exit (EXIT_FAILURE);
  }

  fd = open ("/tmp/helper/a", O_CREAT|O_EXCL|O_WRONLY, 0600);
  if (fd == -1) {
    perror ("create /tmp/helper/a");
    exit (EXIT_FAILURE);
  }
  if (write (fd, buffer, sizeof buffer) != sizeof buffer) {
    perror ("write");
    exit (EXIT_FAILURE);
  }
  if (close (fd) == -1) {
    perror ("close");
    exit (EXIT_FAILURE);
  }

  exit (EXIT_SUCCESS);
}
