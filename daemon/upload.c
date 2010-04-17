/* libguestfs - the guestfsd daemon
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

static int
write_cb (void *fd_ptr, const void *buf, size_t len)
{
  int fd = *(int *)fd_ptr;
  return xwrite (fd, buf, len);
}

/* Has one FileIn parameter. */
int
do_upload (const char *filename)
{
  int err, fd, r, is_dev;

  is_dev = STRPREFIX (filename, "/dev/");

  if (!is_dev) CHROOT_IN;
  fd = open (filename, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY, 0666);
  if (!is_dev) CHROOT_OUT;
  if (fd == -1) {
    err = errno;
    cancel_receive ();
    errno = err;
    reply_with_perror ("%s", filename);
    return -1;
  }

  r = receive_file (write_cb, &fd);
  if (r == -1) {		/* write error */
    err = errno;
    cancel_receive ();
    errno = err;
    reply_with_error ("write error: %s", filename);
    close (fd);
    return -1;
  }
  if (r == -2) {		/* cancellation from library */
    close (fd);
    /* Do NOT send any error. */
    return -1;
  }

  if (close (fd) == -1) {
    err = errno;
    if (r == -1)                /* if r == 0, file transfer ended already */
      cancel_receive ();
    errno = err;
    reply_with_perror ("close: %s", filename);
    return -1;
  }

  return 0;
}

/* Has one FileOut parameter. */
int
do_download (const char *filename)
{
  int fd, r, is_dev;
  char buf[GUESTFS_MAX_CHUNK_SIZE];

  is_dev = STRPREFIX (filename, "/dev/");

  if (!is_dev) CHROOT_IN;
  fd = open (filename, O_RDONLY);
  if (!is_dev) CHROOT_OUT;
  if (fd == -1) {
    reply_with_perror ("%s", filename);
    return -1;
  }

  /* Now we must send the reply message, before the file contents.  After
   * this there is no opportunity in the protocol to send any error
   * message back.  Instead we can only cancel the transfer.
   */
  reply (NULL, NULL);

  while ((r = read (fd, buf, sizeof buf)) > 0) {
    if (send_file_write (buf, r) < 0) {
      close (fd);
      return -1;
    }
  }

  if (r == -1) {
    perror (filename);
    send_file_end (1);		/* Cancel. */
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    perror (filename);
    send_file_end (1);		/* Cancel. */
    return -1;
  }

  if (send_file_end (0))	/* Normal end of file. */
    return -1;

  return 0;
}
