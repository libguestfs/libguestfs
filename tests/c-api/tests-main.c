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

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#include "tests.h"

guestfs_h *g;

static void
print_strings (char *const *argv)
{
  size_t argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    printf ("\t%s\n", argv[argc]);
}

static void
incr (guestfs_h *g, void *iv)
{
  int *i = (int *) iv;
  (*i)++;
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

void
next_test (guestfs_h *g, size_t test_num, size_t nr_tests,
           const char *test_name)
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

int
main (int argc, char *argv[])
{
  const char *filename;
  int fd;
  size_t nr_failed ;
  int close_sentinel = 1;

  setbuf (stdout, NULL);

  no_test_warnings ();

  g = guestfs_create ();
  if (g == NULL) {
    printf ("FAIL: guestfs_create\n");
    exit (EXIT_FAILURE);
  }

  filename = "test1.img";
  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_TRUNC|O_CLOEXEC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (EXIT_FAILURE);
  }
  if (ftruncate (fd, 524288000) == -1) {
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

  filename = "test2.img";
  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_TRUNC|O_CLOEXEC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (EXIT_FAILURE);
  }
  if (ftruncate (fd, 52428800) == -1) {
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

  filename = "test3.img";
  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_TRUNC|O_CLOEXEC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (EXIT_FAILURE);
  }
  if (ftruncate (fd, 10485760) == -1) {
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

  nr_failed = perform_tests ();

  /* Check close callback is called. */
  guestfs_set_close_callback (g, incr, &close_sentinel);

  guestfs_close (g);

  if (close_sentinel != 2) {
    fprintf (stderr, "FAIL: close callback was not called\n");
    exit (EXIT_FAILURE);
  }

  unlink ("test1.img");
  unlink ("test2.img");
  unlink ("test3.img");

  if (nr_failed > 0) {
    printf ("***** %zu / %zu tests FAILED *****\n", nr_failed, nr_tests);
    exit (EXIT_FAILURE);
  }

  exit (EXIT_SUCCESS);
}
