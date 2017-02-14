/* libguestfs
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

/* Test the speed of various qemu features.  Currently tested are:
 *   - virtio-serial upload
 *   - virtio-serial download
 *   - block device read
 *   - block device write
 * More to come in future.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <errno.h>
#include <error.h>
#include <getopt.h>
#include <unistd.h>
#include <signal.h>
#include <assert.h>
#include <sys/time.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#include "getprogname.h"

static void test_virtio_serial (void);
static void test_block_device (void);

/* Which tests are enabled? -- All by default. */
static int virtio_serial_upload = 1;
static int virtio_serial_download = 1;
static int block_device_write = 1;
static int block_device_read = 1;

static int max_time_override = 0;

static void
reset_default_tests (int *flag)
{
  if (*flag) {
    virtio_serial_upload = 0;
    virtio_serial_download = 0;
    block_device_write = 0;
    block_device_read = 0;
    *flag = 0;
  }
}

static void __attribute__((noreturn))
usage (int exitcode)
{
  fprintf (stderr,
           "qemu-speed-test: Test the speed of qemu features.\n"
           "\n"
           "To run all tests (recommended), do:\n"
           "  qemu-speed-test\n"
           "\n"
           "To run only specific tests, do:\n"
           "  qemu-speed-test --option [--option ...]\n"
           "where the test options are:\n"
           "  --virtio-serial-upload\n"
           "  --virtio-serial-download\n"
           "  --block-device-write\n"
           "  --block-device-read\n"
           "\n"
           "Other options:\n"
           "  --help                       Display help output and exit\n"
           "  -t <SECS> | --time=<SECS>    Set max length of test in seconds\n"
           );
  exit (exitcode);
}

int
main (int argc, char *argv[])
{
  enum { HELP_OPTION = CHAR_MAX + 1 };
  static const char options[] = "t:";
  static const struct option long_options[] = {
    { "help", 0, 0, HELP_OPTION },
    { "time", 1, 0, 't' },

    /* Tests. */
    { "virtio-serial-upload", 0, 0, 0 },
    { "virtio-serial-download", 0, 0, 0 },
    { "block-device-write", 0, 0, 0 },
    { "block-device-read", 0, 0, 0 },

    { 0, 0, 0, 0 }
  };
  int c, option_index;
  int reset_flag = 1;

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:
      /* Options which are long only. */
      if (STREQ (long_options[option_index].name, "virtio-serial-upload")) {
        reset_default_tests (&reset_flag);
        virtio_serial_upload = 1;
      }
      else if (STREQ (long_options[option_index].name, "virtio-serial-download")) {
        reset_default_tests (&reset_flag);
        virtio_serial_download = 1;
      }
      else if (STREQ (long_options[option_index].name, "block-device-write")) {
        reset_default_tests (&reset_flag);
        block_device_write = 1;
      }
      else if (STREQ (long_options[option_index].name, "block-device-read")) {
        reset_default_tests (&reset_flag);
        block_device_read = 1;
      }
      else {
        fprintf (stderr, "%s: unknown long option: %s (%d)\n",
                 getprogname (), long_options[option_index].name, option_index);
        exit (EXIT_FAILURE);
      }
      break;

    case 't':
      if (sscanf (optarg, "%d", &max_time_override) != 1 ||
          max_time_override < 0) {
        fprintf (stderr, "%s: -t: argument is not a positive integer\n",
                 getprogname ());
        exit (EXIT_FAILURE);
      }
      break;

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  if (optind != argc) {
    fprintf (stderr, "%s: extra arguments found on the command line\n",
             getprogname ());
    exit (EXIT_FAILURE);
  }

  test_virtio_serial ();
  test_block_device ();

  exit (EXIT_SUCCESS);
}

static void
print_rate (const char *msg, int64_t rate)
{
  printf ("%-40s %" PRIi64 " bytes/sec (%" PRIi64 " Mbytes/sec)\n",
          msg, rate, rate / 1024 / 1024);
  fflush (stdout);
}

/* The maximum time we will spend running the test (seconds). */
#define TEST_SERIAL_MAX_TIME 30

/* The maximum amount of data to copy.  You can safely make this very
 * large because it's only making sparse files.
 */
#define TEST_SERIAL_MAX_SIZE						\
  (INT64_C(1024) * INT64_C(1024) * INT64_C(1024) * INT64_C(1024))

static guestfs_h *g;
static struct timeval start;
static const char *operation;
static int64_t rate;

static void
stop_transfer (int sig)
{
  guestfs_user_cancel (g);
}

/* Compute Y - X and return the result in milliseconds.
 * Approximately the same as this code:
 * http://www.mpp.mpg.de/~huber/util/timevaldiff.c
 */
static int64_t
timeval_diff (const struct timeval *x, const struct timeval *y)
{
  int64_t msec;

  msec = (y->tv_sec - x->tv_sec) * 1000;
  msec += (y->tv_usec - x->tv_usec) / 1000;
  return msec;
}

static void
progress_cb (guestfs_h *g, void *vp, uint64_t event,
             int eh, int flags,
             const char *buf, size_t buflen,
             const uint64_t *array, size_t arraylen)
{
  uint64_t transferred;
  struct timeval now;
  int64_t millis;

  assert (event == GUESTFS_EVENT_PROGRESS);
  assert (arraylen >= 4);

  gettimeofday (&now, NULL);

  /* Bytes transferred. */
  transferred = array[2];

  /* Calculate the speed of the upload or download. */
  millis = timeval_diff (&start, &now);
  assert (millis >= 0);

  if (millis != 0) {
    rate = 1000 * transferred / millis;
    printf ("%s: %" PRIi64 " bytes/sec          \r",
            operation, rate);
    fflush (stdout);
  }
}

static void
test_virtio_serial (void)
{
  int fd, r, eh;
  char tmpfile[] = "/tmp/speedtestXXXXXX";
  struct sigaction sa, old_sa;

  if (!virtio_serial_upload && !virtio_serial_download)
    return;

  /* Create a sparse file.  We could upload from /dev/zero, but we
   * won't get progress messages because libguestfs tests if the
   * source file is a regular file.
   */
  fd = mkstemp (tmpfile);
  if (fd == -1)
    error (EXIT_FAILURE, errno, "mkstemp: %s", tmpfile);
  if (ftruncate (fd, TEST_SERIAL_MAX_SIZE) == -1)
    error (EXIT_FAILURE, errno, "ftruncate");
  if (close (fd) == -1)
    error (EXIT_FAILURE, errno, "close");

  g = guestfs_create ();
  if (!g)
    error (EXIT_FAILURE, errno, "guestfs_create");

  if (guestfs_add_drive_scratch (g, INT64_C (100*1024*1024), -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Make and mount a filesystem which will be used by the download test. */
  if (guestfs_mkfs (g, "ext4", "/dev/sda") == -1)
    exit (EXIT_FAILURE);
  if (guestfs_mount (g, "/dev/sda", "/") == -1)
    exit (EXIT_FAILURE);

  /* Time out the upload after TEST_SERIAL_MAX_TIME seconds have passed. */
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = stop_transfer;
  sa.sa_flags = SA_RESTART;
  sigaction (SIGALRM, &sa, &old_sa);

  /* Get progress messages, which will tell us how much data has been
   * transferred.
   */
  eh = guestfs_set_event_callback (g, progress_cb, GUESTFS_EVENT_PROGRESS,
                                   0, NULL);
  if (eh == -1)
    exit (EXIT_FAILURE);

  if (virtio_serial_upload) {
    gettimeofday (&start, NULL);
    rate = -1;
    operation = "upload";
    alarm (max_time_override > 0 ? max_time_override : TEST_SERIAL_MAX_TIME);

    /* For the upload test, upload the sparse file to /dev/null in the
     * appliance.  Hopefully this is mostly testing just virtio-serial.
     */
    guestfs_push_error_handler (g, NULL, NULL);
    r = guestfs_upload (g, tmpfile, "/dev/null");
    alarm (0);
    unlink (tmpfile);
    guestfs_pop_error_handler (g);

    /* It's possible that the upload will finish before the alarm fires,
     * or that the upload will be stopped by the alarm.
     */
    if (r == -1 && guestfs_last_errno (g) != EINTR) {
      fprintf (stderr,
               "%s: expecting upload command to return EINTR\n%s\n",
               getprogname (), guestfs_last_error (g));
      exit (EXIT_FAILURE);
    }

    if (rate == -1) {
    rate_error:
      fprintf (stderr, "%s: internal error: progress callback was not called! (r=%d, errno=%d)\n",
               getprogname (),
               r, guestfs_last_errno (g));
      exit (EXIT_FAILURE);
    }

    print_rate ("virtio-serial upload rate:", rate);
  }

  if (virtio_serial_download) {
    /* For the download test, download a sparse file within the
     * appliance to /dev/null on the host.
     */
    if (guestfs_touch (g, "/sparse") == -1)
      exit (EXIT_FAILURE);
    if (guestfs_truncate_size (g, "/sparse", TEST_SERIAL_MAX_SIZE) == -1)
      exit (EXIT_FAILURE);

    gettimeofday (&start, NULL);
    rate = -1;
    operation = "download";
    alarm (max_time_override > 0 ? max_time_override : TEST_SERIAL_MAX_TIME);
    guestfs_push_error_handler (g, NULL, NULL);
    r = guestfs_download (g, "/sparse", "/dev/null");
    alarm (0);
    guestfs_pop_error_handler (g);

    if (r == -1 && guestfs_last_errno (g) != EINTR) {
      fprintf (stderr,
               "%s: expecting download command to return EINTR\n%s\n",
               getprogname (), guestfs_last_error (g));
      exit (EXIT_FAILURE);
    }

    if (rate == -1)
      goto rate_error;

    print_rate ("virtio-serial download rate:", rate);
  }

  if (guestfs_shutdown (g) == -1)
    exit (EXIT_FAILURE);

  guestfs_close (g);

  /* Restore SIGALRM signal handler. */
  sigaction (SIGALRM, &old_sa, NULL);
}

/* The time we will spend running the test (seconds). */
#define TEST_BLOCK_DEVICE_TIME 30

static void
test_block_device (void)
{
  int fd;
  char tmpfile[] = "/tmp/speedtestXXXXXX";
  CLEANUP_FREE char **devices = NULL;
  char *r;
  const char *argv[4];
  const int t =
    max_time_override > 0 ? max_time_override : TEST_BLOCK_DEVICE_TIME;
  char tbuf[64];
  int64_t bytes_written, bytes_read;

  if (!block_device_write && !block_device_read)
    return;

  snprintf (tbuf, sizeof tbuf, "%d", t);

  g = guestfs_create ();
  if (!g)
    error (EXIT_FAILURE, errno, "guestfs_create");

  /* Create a fully allocated backing file.  Note we are not testing
   * the speed of allocation on the host.
   */
  fd = mkstemp (tmpfile);
  if (fd == -1)
    error (EXIT_FAILURE, errno, "mkstemp: %s", tmpfile);
  close (fd);

  if (guestfs_disk_create (g, tmpfile, "raw",
                           INT64_C (1024*1024*1024),
                           GUESTFS_DISK_CREATE_PREALLOCATION, "full",
                           -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_add_drive (g, tmpfile) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  devices = guestfs_list_devices (g);
  if (devices == NULL)
    exit (EXIT_FAILURE);
  if (devices[0] == NULL) {
    fprintf (stderr, "%s: expected guestfs_list_devices to return at least 1 device\n",
             getprogname ());
    exit (EXIT_FAILURE);
  }

  if (block_device_write) {
    /* Test write speed. */
    argv[0] = devices[0];
    argv[1] = "w";
    argv[2] = tbuf;
    argv[3] = NULL;
    r = guestfs_debug (g, "device_speed", (char **) argv);
    if (r == NULL)
      exit (EXIT_FAILURE);

    if (sscanf (r, "%" SCNi64, &bytes_written) != 1) {
      fprintf (stderr, "%s: could not parse device_speed output\n",
               getprogname ());
      exit (EXIT_FAILURE);
    }

    print_rate ("block device writes:", bytes_written / t);
  }

  if (block_device_read) {
    /* Test read speed. */
    argv[0] = devices[0];
    argv[1] = "r";
    argv[2] = tbuf;
    argv[3] = NULL;
    r = guestfs_debug (g, "device_speed", (char **) argv);
    if (r == NULL)
      exit (EXIT_FAILURE);

    if (sscanf (r, "%" SCNi64, &bytes_read) != 1) {
      fprintf (stderr, "%s: could not parse device_speed output\n",
               getprogname ());
      exit (EXIT_FAILURE);
    }

    print_rate ("block device reads:", bytes_read / t);
  }

  if (guestfs_shutdown (g) == -1)
    exit (EXIT_FAILURE);

  guestfs_close (g);

  /* Remove temporary file. */
  unlink (tmpfile);
}
