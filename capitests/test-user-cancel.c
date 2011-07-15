/* libguestfs
 * Copyright (C) 2011 Red Hat Inc.
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

/* Test user cancellation.
 *
 * We perform the test using two threads.  The main thread issues
 * guestfs commands to download and upload large files.  Uploads and
 * downloads are done to/from a pipe which is connected back to the
 * current process.  The second test thread sits on the other end of
 * the pipe, feeding or consuming data slowly, and injecting the user
 * cancel events at a particular place in the transfer.
 *
 * It is important to test both download and upload separately, since
 * these exercise different code paths in the library.  However this
 * adds complexity here because these tests are symmetric-but-opposite
 * cases.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/time.h>

#include <pthread.h>

#include "guestfs.h"

static const char *filename = "test.img";
static const off_t filesize = 1024*1024*1024;

static void remove_test_img (void);
static void *start_test_thread (void *);

struct test_thread_data {
  guestfs_h *g;                /* handle */
  int direction;               /* direction of transfer */
#define DIRECTION_UP 1         /* upload (test thread is writing) */
#define DIRECTION_DOWN 2       /* download (test thread is reading) */
  int fd;                      /* pipe to read/write */
  off_t cancel_posn;           /* position at which to cancel */
  off_t transfer_size;         /* how much data thread wrote/read */
};

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  int fd;
  char c = 0;
  pthread_t test_thread;
  struct test_thread_data data;
  int fds[2], r, op_error, op_errno, errors = 0;
  char dev_fd[64];

  srandom (time (NULL));

  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, "failed to create handle\n");
    exit (EXIT_FAILURE);
  }

  /* Create a test image and test data. */
  fd = open (filename, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY, 0666);
  if (fd == -1) {
    perror (filename);
    exit (EXIT_FAILURE);
  }

  atexit (remove_test_img);

  if (lseek (fd, filesize - 1, SEEK_SET) == (off_t) -1) {
    perror ("lseek");
    close (fd);
    exit (EXIT_FAILURE);
  }

  if (write (fd, &c, 1) != 1) {
    perror ("write");
    close (fd);
    exit (EXIT_FAILURE);
  }

  if (close (fd) == -1) {
    perror ("test.img");
    exit (EXIT_FAILURE);
  }

  if (guestfs_add_drive_opts (g, filename,
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                              -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_part_disk (g, "/dev/sda", "mbr") == -1)
    exit (EXIT_FAILURE);

  if (guestfs_mkfs (g, "ext2", "/dev/sda1") == -1)
    exit (EXIT_FAILURE);

  if (guestfs_mount_options (g, "", "/dev/sda1", "/") == -1)
    exit (EXIT_FAILURE);

  /*----- Upload cancellation test -----*/

  data.g = g;
  data.direction = DIRECTION_UP;

  if (pipe (fds) == -1) {
    perror ("pipe");
    exit (EXIT_FAILURE);
  }

  data.fd = fds[1];
  snprintf (dev_fd, sizeof dev_fd, "/dev/fd/%d", fds[0]);

  data.cancel_posn = random () % (filesize/4);

  /* Create the test thread. */
  r = pthread_create (&test_thread, NULL, start_test_thread, &data);
  if (r != 0) {
    fprintf (stderr, "pthread_create: %s", strerror (r));
    exit (EXIT_FAILURE);
  }

  /* Do the upload. */
  op_error = guestfs_upload (g, dev_fd, "/upload");
  op_errno = guestfs_last_errno (g);

  /* Kill the test thread and clean up. */
  r = pthread_cancel (test_thread);
  if (r != 0) {
    fprintf (stderr, "pthread_cancel: %s", strerror (r));
    exit (EXIT_FAILURE);
  }
  r = pthread_join (test_thread, NULL);
  if (r != 0) {
    fprintf (stderr, "pthread_join: %s", strerror (r));
    exit (EXIT_FAILURE);
  }

  close (fds[0]);
  close (fds[1]);

  /* We expect to get an error, with errno == EINTR. */
  if (op_error == -1 && op_errno == EINTR)
    printf ("test-user-cancel: upload cancellation test passed (%ld/%ld)\n",
            (long) data.cancel_posn, (long) data.transfer_size);
  else {
    fprintf (stderr, "test-user-cancel: upload cancellation test FAILED\n");
    fprintf (stderr, "cancel_posn %ld, upload returned %d, errno = %d (%s)\n",
             (long) data.cancel_posn, op_error, op_errno, strerror (op_errno));
    errors++;
  }

  if (guestfs_rm (g, "/upload") == -1)
    exit (EXIT_FAILURE);

  /*----- Download cancellation test -----*/

  if (guestfs_touch (g, "/download") == -1)
    exit (EXIT_FAILURE);

  if (guestfs_truncate_size (g, "/download", filesize/4) == -1)
    exit (EXIT_FAILURE);

  data.g = g;
  data.direction = DIRECTION_DOWN;

  if (pipe (fds) == -1) {
    perror ("pipe");
    exit (EXIT_FAILURE);
  }

  data.fd = fds[0];
  snprintf (dev_fd, sizeof dev_fd, "/dev/fd/%d", fds[1]);

  data.cancel_posn = random () % (filesize/4);

  /* Create the test thread. */
  r = pthread_create (&test_thread, NULL, start_test_thread, &data);
  if (r != 0) {
    fprintf (stderr, "pthread_create: %s", strerror (r));
    exit (EXIT_FAILURE);
  }

  /* Do the download. */
  op_error = guestfs_download (g, "/download", dev_fd);
  op_errno = guestfs_last_errno (g);

  /* Kill the test thread and clean up. */
  r = pthread_cancel (test_thread);
  if (r != 0) {
    fprintf (stderr, "pthread_cancel: %s", strerror (r));
    exit (EXIT_FAILURE);
  }
  r = pthread_join (test_thread, NULL);
  if (r != 0) {
    fprintf (stderr, "pthread_join: %s", strerror (r));
    exit (EXIT_FAILURE);
  }

  close (fds[0]);
  close (fds[1]);

  /* We expect to get an error, with errno == EINTR. */
  if (op_error == -1 && op_errno == EINTR)
    printf ("test-user-cancel: download cancellation test passed (%ld/%ld)\n",
            (long) data.cancel_posn, (long) data.transfer_size);
  else {
    fprintf (stderr, "test-user-cancel: download cancellation test FAILED\n");
    fprintf (stderr, "cancel_posn %ld, upload returned %d, errno = %d (%s)\n",
             (long) data.cancel_posn, op_error, op_errno, strerror (op_errno));
    errors++;
  }

  exit (errors == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

static void
remove_test_img (void)
{
  unlink (filename);
}

static char buffer[BUFSIZ];

#ifndef MIN
#define MIN(a,b) ((a)<(b)?(a):(b))
#endif

static void *
start_test_thread (void *datav)
{
  struct test_thread_data *data = datav;
  ssize_t r;
  size_t n;

  data->transfer_size = 0;

  if (data->direction == DIRECTION_UP) { /* thread is writing */
    /* Feed data in, up to the cancellation point. */
    while (data->transfer_size < data->cancel_posn) {
      n = MIN (sizeof buffer,
               (size_t) (data->cancel_posn - data->transfer_size));
      r = write (data->fd, buffer, n);
      if (r == -1) {
        perror ("test thread: write to pipe before user cancel");
        exit (EXIT_FAILURE);
      }
      data->transfer_size += r;
    }

    /* Do user cancellation. */
    guestfs_user_cancel (data->g);

    /* Keep feeding data after the cancellation point for as long as
     * the main thread wants it.
     */
    while (1) {
      r = write (data->fd, buffer, sizeof buffer);
      if (r == -1) {
        perror ("test thread: write to pipe after user cancel");
        exit (EXIT_FAILURE);
      }
      data->transfer_size += r;
    }
  } else {                      /* thread is reading */
    /* Sink data, up to the cancellation point. */
    while (data->transfer_size < data->cancel_posn) {
      n = MIN (sizeof buffer,
               (size_t) (data->cancel_posn - data->transfer_size));
      r = read (data->fd, buffer, n);
      if (r == -1) {
        perror ("test thread: read from pipe before user cancel");
        exit (EXIT_FAILURE);
      }
      if (r == 0) {
        perror ("test thread: unexpected end of file before user cancel");
        exit (EXIT_FAILURE);
      }
      data->transfer_size += r;
    }

    /* Do user cancellation. */
    guestfs_user_cancel (data->g);

    /* Keep sinking data as long as the main thread is writing. */
    while (1) {
      r = read (data->fd, buffer, sizeof buffer);
      if (r == -1) {
        perror ("test thread: read from pipe after user cancel");
        exit (EXIT_FAILURE);
      }
      if (r == 0)
        break;
      data->transfer_size += r;
    }

    while (1)
      pause ();
  }

  return NULL;
}
