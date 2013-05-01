/* libguestfs
 * Copyright (C) 2009-2013 Red Hat Inc.
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
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <assert.h>

#include <pcre.h>

/* Warn about deprecated libguestfs functions, but only in this file,
 * not in 'tests.c' (because we want to test deprecated functions).
 */
#define GUESTFS_WARN_DEPRECATED 1

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#include "tests.h"

int
init_none (guestfs_h *g)
{
  /* XXX At some point in the distant past, InitNone and InitEmpty
   * became folded together as the same thing.  Really we should make
   * InitNone do nothing at all, but the tests may need to be checked
   * to make sure this is OK.
   */
  return init_empty (g);
}

int
init_empty (guestfs_h *g)
{
  if (guestfs_blockdev_setrw (g, "/dev/sda") == -1)
    return -1;

  if (guestfs_umount_all (g) == -1)
    return -1;

  if (guestfs_lvm_remove_all (g) == -1)
    return -1;

  return 0;
}

int
init_partition (guestfs_h *g)
{
  if (init_empty (g) == -1)
    return -1;

  if (guestfs_part_disk (g, "/dev/sda", "mbr") == -1)
    return -1;

  return 0;
}

int
init_gpt (guestfs_h *g)
{
  if (init_empty (g) == -1)
    return -1;

  if (guestfs_part_disk (g, "/dev/sda", "gpt") == -1)
    return -1;

  return 0;
}

int
init_basic_fs (guestfs_h *g)
{
  if (init_partition (g) == -1)
    return -1;

  if (guestfs_mkfs (g, "ext2", "/dev/sda1") == -1)
    return -1;

  if (guestfs_mount (g, "/dev/sda1", "/") == -1)
    return -1;

  return 0;
}

int
init_basic_fs_on_lvm (guestfs_h *g)
{
  const char *pvs[] = { "/dev/sda1", NULL };

  if (init_partition (g) == -1)
    return -1;

  if (guestfs_pvcreate (g, "/dev/sda1") == -1)
    return -1;

  if (guestfs_vgcreate (g, "VG", (char **) pvs) == -1)
    return -1;

  if (guestfs_lvcreate (g, "LV", "VG", 8) == -1)
    return -1;

  if (guestfs_mkfs (g, "ext2", "/dev/VG/LV") == -1)
    return -1;

  if (guestfs_mount (g, "/dev/VG/LV", "/") == -1)
    return -1;

  return 0;
}

int
init_iso_fs (guestfs_h *g)
{
  if (init_empty (g) == -1)
    return -1;

  if (guestfs_mount_ro (g, "/dev/sdd", "/") == -1)
    return -1;

  return 0;
}

int
init_scratch_fs (guestfs_h *g)
{
  if (init_empty (g) == -1)
    return -1;

  if (guestfs_mount (g, "/dev/sdb1", "/") == -1)
    return -1;

  return 0;
}

static void
print_strings (char *const *argv)
{
  size_t argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    printf ("\t%s\n", argv[argc]);
}

static int compare_lists (char **, char **, int (*) (const char *, const char *));

/* Compare 'ret' to the string list that follows. */
int
is_string_list (char **ret, size_t n, ...)
{
  CLEANUP_FREE /* sic */ char **expected = malloc ((n+1) * sizeof (char *));
  size_t i;
  va_list args;

  va_start (args, n);
  for (i = 0; i < n; ++i)
    expected[i] = va_arg (args, char *);
  expected[n] = NULL;
  va_end (args);
  return compare_lists (ret, expected, strcmp);
}

/* Compare 'ret' to the device list that follows. */
int
is_device_list (char **ret, size_t n, ...)
{
  CLEANUP_FREE /* sic */ char **expected = malloc ((n+1) * sizeof (char *));
  size_t i;
  va_list args;

  va_start (args, n);
  for (i = 0; i < n; ++i)
    expected[i] = va_arg (args, char *);
  expected[n] = NULL;
  va_end (args);
  return compare_lists (ret, expected, compare_devices);
}

static int
compare_lists (char **ret, char **expected,
               int (*compare) (const char *, const char *))
{
  size_t i;

  for (i = 0; ret[i] != NULL; ++i) {
    if (!expected[i]) {
      fprintf (stderr, "test failed: returned list is too long\n");
      goto fail;
    }
    if (compare (ret[i], expected[i]) != 0) {
      fprintf (stderr, "test failed: elements differ at position %zu\n", i);
      goto fail;
    }
  }
  if (expected[i]) {
    fprintf (stderr, "test failed: returned list is too short\n");
    goto fail;
  }

  return 1; /* test expecting true for OK */

 fail:
  fprintf (stderr, "returned list was:\n");
  print_strings (ret);
  fprintf (stderr, "expected list was:\n");
  print_strings (expected);
  return 0; /* test expecting false for failure */
}

/* Compare two device names, ignoring hd/sd/vd */
int
compare_devices (const char *dev1, const char *dev2)
{
  CLEANUP_FREE char *copy1 = NULL, *copy2 = NULL;

  assert (dev1 && dev2);
  if (strlen (dev1) < 6 || strlen (dev2) < 6)
    return -1;

  copy1 = strdup (dev1);
  copy2 = strdup (dev2);
  copy1[5] = 'h';
  copy2[5] = 'h';

  return strcmp (copy1, copy2);
}

/* Compare returned buffer with expected buffer.  Note the buffers have
 * a length and may contain ASCII NUL characters.
 */
int
compare_buffers (const char *b1, size_t s1, const char *b2, size_t s2)
{
  if (s1 != s2)
    return s1 - s2;
  return memcmp (b1, b2, s1);
}

/* Get md5sum of the named file. */
static void
md5sum (const char *filename, char *result)
{
  char cmd[256];
  snprintf (cmd, sizeof cmd, "md5sum %s", filename);
  FILE *pp = popen (cmd, "r");
  if (pp == NULL) {
    perror (cmd);
    exit (EXIT_FAILURE);
  }
  if (fread (result, 1, 32, pp) != 32) {
    perror ("md5sum: fread");
    exit (EXIT_FAILURE);
  }
  if (pclose (pp) != 0) {
    perror ("pclose");
    exit (EXIT_FAILURE);
  }
  result[32] = '\0';
}

/* Compare MD5 has to expected hash of a file. */
int
check_file_md5 (const char *ret, const char *filename)
{
  char expected[33];

  md5sum (filename, expected);
  if (STRNEQ (ret, expected)) {
    fprintf (stderr, "test failed: MD5 returned (%s) does not match MD5 of file %s (%s)\n",
             ret, filename, expected);
    return -1;
  }

  return 0;
}

/* Return the value for a key in a hashtable.
 * Note: the return value is part of the hash and should not be freed.
 */
const char *
get_key (char **hash, const char *key)
{
  size_t i;

  for (i = 0; hash[i] != NULL; i += 2) {
    if (STREQ (hash[i], key))
      return hash[i+1];
  }

  return NULL; /* key not found */
}

/* Compare hash key's value to expected value. */
int
check_hash (char **ret, const char *key, const char *expected)
{
  const char *value = get_key (ret, key);

  if (STRNEQ (value, expected)) {
    fprintf (stderr, "test failed: hash key %s = \"%s\" is not expected value \"%s\"\n",
             key, value, expected);
    return -1;
  }

  return 0;
}

/* Match string with a PCRE regular expression. */
int
match_re (const char *str, const char *pattern)
{
  const char *err;
  int offset;
  pcre *re;
  size_t len = strlen (str);
  int vec[30], r;

  re = pcre_compile (pattern, 0, &err, &offset, NULL);
  if (re == NULL) {
    fprintf (stderr, "tests: cannot compile regular expression '%s': %s\n",
             pattern, err);
    exit (EXIT_FAILURE);
  }
  r = pcre_exec (re, NULL, str, len, 0, 0, vec, sizeof vec / sizeof vec[0]);
  pcre_free (re);

  return r != PCRE_ERROR_NOMATCH;
}

/* Used for FileIn parameters in tests.  If the path starts with
 * "$srcdir" then replace that with the contents of the $srcdir
 * environment variable (this is set by automake and run time).  The
 * caller must free the returned string.
 */
char *
substitute_srcdir (const char *path)
{
  char *ret;

  if (STRPREFIX (path, "$srcdir")) {
    const char *srcdir;

    srcdir = getenv ("srcdir");
    if (!srcdir) {
      fprintf (stderr, "tests: environment variable $srcdir is not defined.\n"
               "Normally it is defined by automake.  If you are running the\n"
               "tests directly, set $srcdir to point to the source tests/c-api\n"
               "directory.\n");
      exit (EXIT_FAILURE);
    }

    if (asprintf (&ret, "%s%s", srcdir, path + 7) == -1) {
      perror ("asprintf");
      exit (EXIT_FAILURE);
    }
  }
  else {
    ret = strdup (path);
    if (!ret) {
      perror ("strdup");
      exit (EXIT_FAILURE);
    }
  }

  return ret;
}

static void
next_test (guestfs_h *g, size_t test_num, const char *test_name)
{
  if (guestfs_get_verbose (g))
    printf ("-------------------------------------------------------------------------------\n");
  printf ("%3zu/%3zu %s\n", test_num, nr_tests, test_name);
}

void
skipped (const char *test_name, const char *fs, ...)
{
  va_list args;
  CLEANUP_FREE char *reason = NULL;
  int len;

  va_start (args, fs);
  len = vasprintf (&reason, fs, args);
  va_end (args);
  assert (len >= 0);

  printf ("        %s skipped (reason: %s)\n",
          test_name, reason);
}

static void
delete_file (guestfs_h *g, void *filenamev,
             uint64_t event, int eh, int flags,
             const char *buf, size_t buf_len,
             const uint64_t *array, size_t array_len)
{
  char *filename = filenamev;

  unlink (filename);
  free (filename);
}

static void
add_disk (guestfs_h *g, const char *key, off_t size)
{
  CLEANUP_FREE char *tmpdir = guestfs_get_tmpdir (g);
  char *filename;
  int fd;

  if (asprintf (&filename, "%s/diskXXXXXX", tmpdir) == -1) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }

  fd = mkostemp (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_TRUNC|O_CLOEXEC);
  if (fd == -1) {
    perror ("mkstemp");
    exit (EXIT_FAILURE);
  }
  if (ftruncate (fd, size) == -1) {
    perror ("ftruncate");
    close (fd);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    exit (EXIT_FAILURE);
  }

  if (guestfs_add_drive (g, filename) == -1) {
    printf ("FAIL: guestfs_add_drive %s\n", filename);
    exit (EXIT_FAILURE);
  }

  if (guestfs_set_event_callback (g, delete_file,
                                  GUESTFS_EVENT_CLOSE, 0, filename) == -1) {
    printf ("FAIL: guestfs_set_event_callback (GUESTFS_EVENT_CLOSE)\n");
    exit (EXIT_FAILURE);
  }

  /* Record the real filename in the named private key.  Tests can
   * retrieve these names using the magic "GETKEY:<key>" String
   * parameter.
   */
  guestfs_set_private (g, key, filename);
}

/* Create the handle, with attached disks. */
static guestfs_h *
create_handle (void)
{
  guestfs_h *g;

  g = guestfs_create ();
  if (g == NULL) {
    printf ("FAIL: guestfs_create\n");
    exit (EXIT_FAILURE);
  }

  add_disk (g, "test1", 524288000);

  add_disk (g, "test2", 52428800);

  add_disk (g, "test3", 10485760);

  if (guestfs_add_drive_ro (g, "../data/test.iso") == -1) {
    printf ("FAIL: guestfs_add_drive_ro ../data/test.iso\n");
    exit (EXIT_FAILURE);
  }

  /* Set a timeout in case qemu hangs during launch (RHBZ#505329). */
  alarm (600);

  if (guestfs_launch (g) == -1) {
    printf ("FAIL: guestfs_launch\n");
    exit (EXIT_FAILURE);
  }

  /* Cancel previous alarm. */
  alarm (0);

  /* Create ext2 filesystem on /dev/sdb1 partition. */
  if (guestfs_part_disk (g, "/dev/sdb", "mbr") == -1) {
    printf ("FAIL: guestfs_part_disk\n");
    exit (EXIT_FAILURE);
  }
  if (guestfs_mkfs (g, "ext2", "/dev/sdb1") == -1) {
    printf ("FAIL: guestfs_mkfs (/dev/sdb1)\n");
    exit (EXIT_FAILURE);
  }

  return g;
}

static size_t
perform_tests (guestfs_h *g)
{
  size_t test_num;
  size_t nr_failed = 0;
  struct test *t;

  for (test_num = 0; test_num < nr_tests; ++test_num) {
    t = &tests[test_num];
    next_test (g, test_num, t->name);
    if (t->test_fn (g) == -1) {
      printf ("FAIL: %s\n", t->name);
      nr_failed++;
    }
  }

  return nr_failed;
}

int
main (int argc, char *argv[])
{
  size_t nr_failed;
  guestfs_h *g;

  setbuf (stdout, NULL);

  no_test_warnings ();

  g = create_handle ();

  nr_failed = perform_tests (g);

  guestfs_close (g);

  if (nr_failed > 0) {
    printf ("***** %zu / %zu tests FAILED *****\n", nr_failed, nr_tests);
    exit (EXIT_FAILURE);
  }

  exit (EXIT_SUCCESS);
}
