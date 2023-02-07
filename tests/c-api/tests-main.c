/* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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
#include <errno.h>
#include <error.h>
#include <fcntl.h>
#include <assert.h>
#include <sys/utsname.h>

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include "guestfs.h"
#include "guestfs-utils.h"
#include "structs-cleanups.h"

#include "tests.h"

static int is_cross_appliance;

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

/* Compare two device names, ignoring hd/sd/ubd/vd */
int
compare_devices (const char *a, const char *b)
{
  size_t alen, blen;

  /* Skip /dev/ prefix if present. */
  if (STRPREFIX (a, "/dev/"))
    a += 5;
  if (STRPREFIX (b, "/dev/"))
    b += 5;

  /* Skip sd/hd/ubd/vd. */
  alen = strcspn (a, "d");
  blen = strcspn (b, "d");
  assert (alen > 0 && alen <= 2);
  assert (blen > 0 && blen <= 2);
  a += alen + 1;
  b += blen + 1;

  return strcmp (a, b);
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
  if (pp == NULL)
    error (EXIT_FAILURE, errno, "popen: %s", cmd);
  if (fread (result, 1, 32, pp) != 32)
    error (EXIT_FAILURE, errno, "md5sum: fread");
  if (pclose (pp) != 0)
    error (EXIT_FAILURE, errno, "pclose");
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

  if (value == NULL) {
    fprintf (stderr, "test failed: hash key %s not found\n", key);
    return -1;
  }

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
  int errnum;
  PCRE2_SIZE offset;
  pcre2_code *re;
  int r;

  re = pcre2_compile ((PCRE2_SPTR)pattern, PCRE2_ZERO_TERMINATED,
                      0, &errnum, &offset, NULL);
  if (re == NULL)
    error (EXIT_FAILURE, 0,
           "cannot compile regular expression '%s': %d", pattern, errnum);

  CLEANUP_PCRE2_MATCH_DATA_FREE pcre2_match_data *match_data =
    pcre2_match_data_create_from_pattern (re, NULL);

  r = pcre2_match (re, (PCRE2_SPTR)str, PCRE2_ZERO_TERMINATED,
                   0, 0, match_data, NULL);
  pcre2_code_free (re);

  return r != PCRE2_ERROR_NOMATCH;
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
    if (!srcdir)
      error (EXIT_FAILURE, 0,
             "environment variable $srcdir is not defined.\n"
             "Normally it is defined by automake.  If you are running the\n"
             "tests directly, set $srcdir to point to the source tests/c-api\n"
             "directory.");

    if (asprintf (&ret, "%s%s", srcdir, path + 7) == -1)
      error (EXIT_FAILURE, errno, "asprintf");
  }
  else {
    ret = strdup (path);
    if (!ret)
      error (EXIT_FAILURE, errno, "strdup");
  }

  return ret;
}

int
using_cross_appliance (void)
{
  return is_cross_appliance;
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

  if (guestfs_add_drive_scratch (g, INT64_C(2)*1024*1024*1024, -1) == -1) {
    printf ("FAIL: guestfs_add_drive_scratch\n");
    exit (EXIT_FAILURE);
  }

  if (guestfs_add_drive_scratch (g, INT64_C(2)*1024*1024*1024, -1) == -1) {
    printf ("FAIL: guestfs_add_drive_scratch\n");
    exit (EXIT_FAILURE);
  }

  if (guestfs_add_drive_scratch (g, INT64_C(10)*1024*1024, -1) == -1) {
    printf ("FAIL: guestfs_add_drive_scratch\n");
    exit (EXIT_FAILURE);
  }

  if (guestfs_add_drive_ro (g, "../test-data/test.iso") == -1) {
    printf ("FAIL: guestfs_add_drive_ro ../test-data/test.iso\n");
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

static int
check_cross_appliance (guestfs_h *g)
{
  struct utsname host;
  CLEANUP_FREE_UTSNAME struct guestfs_utsname *appliance = NULL;
  int r;
  struct guestfs_utsname host_utsname;

  r = uname (&host);
  if (r == -1)
    error (EXIT_FAILURE, errno, "uname");

  appliance = guestfs_utsname (g);
  if (appliance == NULL)
    exit (EXIT_FAILURE);

  host_utsname.uts_sysname = host.sysname;
  host_utsname.uts_release = host.release;
  host_utsname.uts_version = host.version;
  host_utsname.uts_machine = host.machine;

  return guestfs_compare_utsname (appliance, &host_utsname);
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
  is_cross_appliance = check_cross_appliance (g);

  nr_failed = perform_tests (g);

  guestfs_close (g);

  if (nr_failed > 0) {
    printf ("***** %zu / %zu tests FAILED *****\n", nr_failed, nr_tests);
    exit (EXIT_FAILURE);
  }

  exit (EXIT_SUCCESS);
}
