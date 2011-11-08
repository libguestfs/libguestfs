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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

struct write_cb_data {
  int fd;                       /* file descriptor */
  uint64_t written;             /* bytes written so far */
};

static int
write_cb (void *data_vp, const void *buf, size_t len)
{
  struct write_cb_data *data = data_vp;
  int r;

  r = xwrite (data->fd, buf, len);
  if (r == -1)
    return -1;

  data->written += len;

  if (progress_hint > 0)
    notify_progress (data->written, progress_hint);

  return 0;
}

/* Has one FileIn parameter. */
static int
upload (const char *filename, int flags, int64_t offset)
{
  struct write_cb_data data = { .written = 0 };
  int err, r, is_dev;

  is_dev = STRPREFIX (filename, "/dev/");

  if (!is_dev) CHROOT_IN;
  data.fd = open (filename, flags, 0666);
  if (!is_dev) CHROOT_OUT;
  if (data.fd == -1) {
    err = errno;
    r = cancel_receive ();
    errno = err;
    reply_with_perror ("%s", filename);
    return -1;
  }

  if (offset) {
    if (lseek (data.fd, offset, SEEK_SET) == -1) {
      err = errno;
      r = cancel_receive ();
      errno = err;
      reply_with_perror ("lseek: %s", filename);
      return -1;
    }
  }

  r = receive_file (write_cb, &data.fd);
  if (r == -1) {		/* write error */
    err = errno;
    r = cancel_receive ();
    errno = err;
    reply_with_error ("write error: %s", filename);
    close (data.fd);
    return -1;
  }
  if (r == -2) {		/* cancellation from library */
    /* This error is ignored by the library since it initiated the
     * cancel.  Nevertheless we must send an error reply here.
     */
    reply_with_error ("file upload cancelled");
    close (data.fd);
    return -1;
  }

  if (close (data.fd) == -1) {
    reply_with_perror ("close: %s", filename);
    return -1;
  }

  return 0;
}

/* Has one FileIn parameter. */
int
do_upload (const char *filename)
{
  return upload (filename, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY, 0);
}

/* Has one FileIn parameter. */
int
do_upload_offset (const char *filename, int64_t offset)
{
  if (offset < 0) {
    reply_with_perror ("%s: offset in file is negative", filename);
    return -1;
  }

  return upload (filename, O_WRONLY|O_CREAT|O_NOCTTY, offset);
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

  /* Calculate the size of the file or device for notification messages. */
  uint64_t total, sent = 0;
  if (!is_dev) {
    struct stat statbuf;
    if (fstat (fd, &statbuf) == -1) {
      reply_with_perror ("%s", filename);
      close (fd);
      return -1;
    }
    total = statbuf.st_size;
  } else {
    int64_t size = do_blockdev_getsize64 (filename);
    if (size == -1) {
      /* do_blockdev_getsize64 has already sent a reply. */
      close (fd);
      return -1;
    }
    total = (uint64_t) size;
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

    sent += r;
    notify_progress (sent, total);
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

/* Has one FileOut parameter. */
int
do_download_offset (const char *filename, int64_t offset, int64_t size)
{
  int fd, r, is_dev;
  char buf[GUESTFS_MAX_CHUNK_SIZE];

  if (offset < 0) {
    reply_with_perror ("%s: offset in file is negative", filename);
    return -1;
  }

  if (size < 0) {
    reply_with_perror ("%s: size is negative", filename);
    return -1;
  }
  uint64_t usize = (uint64_t) size;

  is_dev = STRPREFIX (filename, "/dev/");

  if (!is_dev) CHROOT_IN;
  fd = open (filename, O_RDONLY);
  if (!is_dev) CHROOT_OUT;
  if (fd == -1) {
    reply_with_perror ("%s", filename);
    return -1;
  }

  if (offset) {
    if (lseek (fd, offset, SEEK_SET) == -1) {
      reply_with_perror ("lseek: %s", filename);
      return -1;
    }
  }

  uint64_t total = usize, sent = 0;

  /* Now we must send the reply message, before the file contents.  After
   * this there is no opportunity in the protocol to send any error
   * message back.  Instead we can only cancel the transfer.
   */
  reply (NULL, NULL);

  while (usize > 0) {
    r = read (fd, buf, usize > sizeof buf ? sizeof buf : usize);
    if (r == -1) {
      perror (filename);
      send_file_end (1);        /* Cancel. */
      close (fd);
      return -1;
    }

    if (r == 0)
      /* The documentation leaves this case undefined.  Currently we
       * just read fewer bytes than requested.
       */
      break;

    if (send_file_write (buf, r) < 0) {
      close (fd);
      return -1;
    }

    sent += r;
    usize -= r;
    notify_progress (sent, total);
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
