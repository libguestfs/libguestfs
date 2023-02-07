/* Test libguestfs with large/maximum number of disks.
 * Copyright (C) 2012-2023 Red Hat Inc.
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
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <getopt.h>
#include <errno.h>
#include <error.h>
#include <pwd.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <assert.h>

#include <guestfs.h>
#include "guestfs-utils.h"

#include "getprogname.h"

static ssize_t get_max_disks (guestfs_h *g);
static void do_test (guestfs_h *g, size_t ndisks, bool just_add);
static void make_disks (const char *tmpdir);
static void rm_disks (void);

static size_t ndisks;
static char **disks;

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, "Try ‘%s --help’ for more information.\n",
             getprogname ());
  else {
    printf ("Test libguestfs with large/maximum number of disks.\n"
            "\n"
            "Usage:\n"
            "  %s -n NR_DISKS\n"
            "          Do a full test with NR_DISKS.\n"
            "  %s --max\n"
            "          Do a full test with the max number of disks *.\n"
            "  %s --just-add [-n N | --max]\n"
            "          Don't do a full test, only add the disks and exit.\n"
            "\n"
            "Options:\n"
            "  --help             Display this help and exit.\n"
            "  --just-add         Only add the disks and exit if successful.\n"
            "  --max              Test max disks possible *.\n"
            "  -n NR_DISKS        Test NR_DISKS.\n"
            "  -v | --verbose     Enable libguestfs debugging.\n"
            "  -x | --trace       Enable libguestfs tracing.\n"
            "\n"
            "* Note that the max number of disks depends on the backend and\n"
            "  limit on the number of open file descriptors (ulimit -n).\n",
            getprogname (), getprogname (), getprogname ());
  }
  exit (status);
}

int
main (int argc, char *argv[])
{
  enum { HELP_OPTION = CHAR_MAX + 1 };
  static const char options[] = "amn:vVx";
  static const struct option long_options[] = {
    { "help", 0, 0, HELP_OPTION },
    { "just-add", 0, 0, 0 },
    { "max", 0, 0, 'm' },
    { "trace", 0, 0, 'x' },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  int c;
  int option_index;
  bool just_add = false;
  guestfs_h *g;
  char *tmpdir;
  ssize_t n = -1; /* -1: not set  0: max  > 0: specific value */

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "just-add"))
        just_add = true;
      else
        error (EXIT_FAILURE, 0,
               "unknown long option: %s (%d)",
               long_options[option_index].name, option_index);
      break;

    case 'm':
      n = 0;
      break;

    case 'n':
      if (sscanf (optarg, "%zd", &n) != 1 || n <= 0)
        error (EXIT_FAILURE, 0, "cannot parse -n option");
      break;

    case 'x':
      guestfs_set_trace (g, 1);
      break;

    case 'v':
      guestfs_set_verbose (g, 1);
      break;

    case 'V':
      printf ("%s %s\n",
              getprogname (),
              PACKAGE_VERSION_FULL);
      exit (EXIT_SUCCESS);

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  if (n == -1)
    error (EXIT_FAILURE, 0, "either -n NR_DISKS or --max must be specified");

  if (n == 0) {
    n = get_max_disks (g);
    if (n == -1)
      error (EXIT_FAILURE, 0, "cannot calculate --max disks");
  }
  ndisks = n;

  tmpdir = guestfs_get_cachedir (g);
  if (tmpdir == NULL)
    exit (EXIT_FAILURE);
  make_disks (tmpdir);
  free (tmpdir);
  atexit (rm_disks);

  do_test (g, ndisks, just_add);

  if (guestfs_shutdown (g) == -1)
    exit (EXIT_FAILURE);
  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

/**
 * Work out the maximum number of disks that could be added to the
 * libguestfs appliance, based on these factors:
 *
 * =over 4
 *
 * =item the current backend
 *
 * =item the max number of open file descriptors (RLIMIT_NOFILE)
 *
 * =back
 */
static ssize_t
get_max_disks (guestfs_h *g)
{
  ssize_t ret;
  struct rlimit rlim;
  /* We reserve a little bit of "headroom" because qemu uses more
   * file descriptors than just the disk files.
   */
  const unsigned fd_headroom = 32;

  ret = guestfs_max_disks (g);
  if (ret == -1)
    return -1;

  if (getrlimit (RLIMIT_NOFILE, &rlim) == -1) {
    perror ("getrlimit: RLIMIT_NOFILE");
    return -1;
  }
  if (rlim.rlim_cur > fd_headroom) {
    if ((size_t) ret > rlim.rlim_cur - fd_headroom) {
      if (rlim.rlim_max > rlim.rlim_cur)
        fprintf (stderr,
                 "%s: warning: to get more complete testing, increase\n"
                 "file limit up to hard limit:\n"
                 "\n"
                 "$ ulimit -Hn %lu\n"
                 "\n",
                 getprogname (), (unsigned long) rlim.rlim_max);
      else {
        struct passwd *pw;
        unsigned long suggested_limit = ret + fd_headroom;

        pw = getpwuid (geteuid ());
        fprintf (stderr,
                 "%s: warning: to get more complete testing, increase\n"
                 "file descriptor limit to >= %lu.\n"
                 "\n"
                 "To do this, add this line to /etc/security/limits.conf:\n"
                 "\n"
                 "%s  hard  nofile  %lu\n"
                 "\n",
                 getprogname (), suggested_limit,
                 pw ? pw->pw_name : "your_username",
                 suggested_limit);
      }

      ret = rlim.rlim_cur - fd_headroom;
    }
  }

  printf ("max_disks = %zd\n", ret);
  return ret;
}

static void
do_test (guestfs_h *g, size_t ndisks, bool just_add)
{
  size_t i, j, k, n;
  unsigned errors;
  CLEANUP_FREE_STRING_LIST char **devices = NULL;
  CLEANUP_FREE_STRING_LIST char **partitions = NULL;

  for (i = 0; i < ndisks; ++i) {
    if (guestfs_add_drive_opts (g, disks[i],
                                GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                                GUESTFS_ADD_DRIVE_OPTS_CACHEMODE, "unsafe",
                                -1) == -1)
      exit (EXIT_FAILURE);
  }

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Check the disks were added. */
  devices = guestfs_list_devices (g);
  if (devices == NULL)
    exit (EXIT_FAILURE);
  n = guestfs_int_count_strings (devices);
  if (n != ndisks) {
    fprintf (stderr, "%s: incorrect number of devices returned by guestfs_list_devices:\n",
             getprogname ());
    fprintf (stderr, "counted %zu, expecting %zu\n", n, ndisks);
    fprintf (stderr, "devices:\n");
    for (i = 0; i < n; ++i)
      fprintf (stderr, "\t%s\n", devices[i]);
    exit (EXIT_FAILURE);
  }

  /* If the --just-add option was given, we're done. */
  if (just_add)
    return;

  /* Check each device has the expected drive name, eg. /dev/sda,
   * /dev/sdb, ..., /dev/sdaa, ...
   */
  for (i = 0; i < ndisks; ++i) {
    char expected[64];

    guestfs_int_drive_name (i, expected);
    if (!STRSUFFIX (devices[i], expected)) {
      fprintf (stderr,
               "%s: incorrect device name at index %zu: "
               "%s (expected suffix %s)\n",
               getprogname (), i, devices[i], expected);
      exit (EXIT_FAILURE);
    }
  }

  /* Check drive index. */
  for (i = 0; i < ndisks; ++i) {
    int idx;

    idx = guestfs_device_index (g, devices[i]);
    if (idx == -1)
      exit (EXIT_FAILURE);
    if ((int) i != idx) {
      fprintf (stderr,
               "%s: incorrect device index for %s: "
               "expected %zu by got %d\n",
               getprogname (), devices[i], i, idx);
      exit (EXIT_FAILURE);
    }
  }

  /* Check the disk index written at the start of each disk.  This
   * ensures that disks are added to the appliance in the same order
   * that we called guestfs_add_drive.
   */
  errors = 0;
  for (i = 0; i < ndisks; ++i) {
    CLEANUP_FREE char *buf = NULL;
    size_t j, r;

    buf = guestfs_pread_device (g, devices[i], sizeof j, 0, &r);
    if (buf == NULL)
      exit (EXIT_FAILURE);
    if (r != sizeof j)
      error (EXIT_FAILURE, 0, "pread_device read incorrect number of bytes");
    memcpy (&j, buf, r);
    if (i != j) {
      if (errors == 0)
        fprintf (stderr, "%s: incorrect device enumeration\n",
                 getprogname ());
      errors++;
      fprintf (stderr, "%s at device index %zu was added with index %zu\n",
               devices[i], i, j);
    }
  }
  if (errors > 0)
    exit (EXIT_FAILURE);

  /* Put some data on each disk to check they are writable and
   * mountable.
   */
  for (i = 0; i < ndisks; ++i) {
    CLEANUP_FREE char *mp = NULL;
    CLEANUP_FREE char *part = NULL;
    CLEANUP_FREE char *file = NULL;
    CLEANUP_FREE char *data = NULL;

    if (asprintf (&mp, "/mp%zu", i) == -1)
      error (EXIT_FAILURE, errno, "asprintf");

    if (guestfs_mkmountpoint (g, mp) == -1)
      exit (EXIT_FAILURE);

    /* To save time in the test, add 15 partitions to the first disk
     * and last disks only, and 1 partition to every other disk.  Note
     * that 15 partitions is the max allowed by virtio-blk.
     */
    if (i == 0 || i == ndisks-1) {
      if (guestfs_part_init (g, devices[i], "gpt") == -1)
        exit (EXIT_FAILURE);
      for (j = 1; j <= 14; ++j) {
        if (guestfs_part_add (g, devices[i], "p", 64*j, 64*j+63) == -1)
          exit (EXIT_FAILURE);
      }
      if (guestfs_part_add (g, devices[i], "p", 64*15, -64) == -1)
        exit (EXIT_FAILURE);
      if (asprintf (&part, "%s15", devices[i]) == -1)
        error (EXIT_FAILURE, errno, "asprintf");
    }
    else {
      if (guestfs_part_disk (g, devices[i], "mbr") == -1)
        exit (EXIT_FAILURE);
      if (asprintf (&part, "%s1", devices[i]) == -1)
        error (EXIT_FAILURE, errno, "asprintf");
    }

    if (guestfs_mkfs (g, "ext2", part) == -1)
      exit (EXIT_FAILURE);
    if (guestfs_mount (g, part, mp) == -1)
      exit (EXIT_FAILURE);

    if (asprintf (&file, "%s/disk%zu", mp, i) == -1)
      error (EXIT_FAILURE, errno, "asprintf");
    if (asprintf (&data, "This is disk %zu.", i) == -1)
      error (EXIT_FAILURE, errno, "asprintf");

    if (guestfs_write (g, file, data, strlen (data)) == -1)
      exit (EXIT_FAILURE);
  }

  for (i = 0; i < ndisks; ++i) {
    CLEANUP_FREE char *file = NULL, *expected = NULL, *actual = NULL;

    if (asprintf (&file, "/mp%zu/disk%zu", i, i) == -1)
      error (EXIT_FAILURE, errno, "asprintf");
    if (asprintf (&expected, "This is disk %zu.", i) == -1)
      error (EXIT_FAILURE, errno, "asprintf");

    actual = guestfs_cat (g, file);
    if (actual == NULL)
      exit (EXIT_FAILURE);

    if (STRNEQ (expected, actual)) {
      fprintf (stderr,
               "%s: unexpected content in file %s: "
               "expected \"%s\", actual \"%s\"\n",
               getprogname (), file,
               expected, actual);
      exit (EXIT_FAILURE);
    }
  }

  /* Finally check the partition list. */
  partitions = guestfs_list_partitions (g);
  if (partitions == NULL)
    exit (EXIT_FAILURE);

  k = 0;
  for (i = 0; i < ndisks; ++i) {
    char dev[64];

    guestfs_int_drive_name (i, dev);

    if (i == 0 || i == ndisks-1) {
      for (j = 1; j <= 15; ++j) {
        CLEANUP_FREE char *expected = NULL;
        const char *p;

        if (asprintf (&expected, "%s%zu", dev, j) == -1)
          error (EXIT_FAILURE, errno, "asprintf");
        p = partitions[k++];
        if (!STRSUFFIX (p, expected)) {
          fprintf (stderr,
                   "%s: incorrect partition name at index %zu, %zu: "
                   "%s (expected suffix %s)\n",
                   getprogname (), i, j, p, expected);
          exit (EXIT_FAILURE);
        }
      }
    }
    else {
      CLEANUP_FREE char *expected = NULL;
      const char *p;

      if (asprintf (&expected, "%s1", dev) == -1)
        error (EXIT_FAILURE, errno, "asprintf");
      p = partitions[k++];
      if (!STRSUFFIX (p, expected)) {
        fprintf (stderr,
                 "%s: incorrect partition name at index %zu: "
                 "%s (expected suffix %s)\n",
                 getprogname (), i, p, expected);
        exit (EXIT_FAILURE);
      }
    }
  }
}

static void
make_disks (const char *tmpdir)
{
  size_t i;
  int fd;

  assert (ndisks > 0);

  disks = calloc (ndisks, sizeof (char *));
  if (disks == NULL)
    error (EXIT_FAILURE, errno, "calloc");

  for (i = 0; i < ndisks; ++i) {
    if (asprintf (&disks[i], "%s/testdiskXXXXXX", tmpdir) == -1)
      error (EXIT_FAILURE, errno, "asprintf");
    fd = mkstemp (disks[i]);
    if (fd == -1)
      error (EXIT_FAILURE, errno, "mkstemp: %s", disks[i]);

    /* Create a raw format 1MB disk, and write the disk number at the
     * start of the disk, so that we can later check that disks are
     * added in the right order to the appliance.
     *
     * Note that we write the disk number in whatever is the current
     * endian/integer size, which is fine because we'll only check it
     * from the same program.
     */
    if (ftruncate (fd, 1024*1024) == -1)
      error (EXIT_FAILURE, errno, "ftruncate: %s", disks[i]);
    if (write (fd, &i, sizeof i) != sizeof i)
      error (EXIT_FAILURE, errno, "write: %s", disks[i]);
    if (close (fd) == -1)
      error (EXIT_FAILURE, errno, "close: %s", disks[i]);
  }
}

/* Called by an atexit handler. */
static void
rm_disks (void)
{
  size_t i;

  if (disks == NULL)
    return;

  for (i = 0; i < ndisks; ++i) {
    unlink (disks[i]);
    free (disks[i]);
  }

  free (disks);
  disks = NULL;
}
