/* libguestfs
 * Copyright (C) 2012 Red Hat Inc.
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

/* Test fidelity of filenames on various filesystems.
 * See RHBZ#823885 and RHBZ#823887.
 * Thanks to Laszlo Ersek for suggestions for this test.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

static const char ourenvvar[] = "SKIP_TEST_CHARSET_FIDELITY";

struct filesystem {
  const char *fs_name;          /* Name of filesystem. */
  int fs_case_insensitive;      /* True if filesystem is case insensitive. */
  int fs_8bit_only;             /* True if fs only supports 8 bit chars. */
  const char *fs_mount_options; /* Mount options, if required. */
  const char *fs_feature;       /* Feature test, if required. */

  /* Note these skip options indicate BUGS in the filesystems (not
   * in libguestfs).  The filesystems should be able to pass these
   * tests if they are working correctly.
   */
  int fs_skip_latin1;           /* Skip latin1 test. */
  int fs_skip_latin2;           /* Skip latin2 test. */
};

static struct filesystem filesystems[] = {
  { "ext2",  0, 0, NULL, NULL, 0, 0 },
  { "ext3",  0, 0, NULL, NULL, 0, 0 },
  { "ext4",  0, 0, NULL, NULL, 0, 0 },
  { "btrfs", 0, 0, NULL, "btrfs", 0, 0 },
  { "vfat",  1, 0, "iocharset=iso8859-1,utf8", NULL, 1, 1 },
  { "msdos", 1, 1, "iocharset=iso8859-1", NULL, 0, 0 },
  /* In reality NTFS is case insensitive, but the ntfs-3g driver isn't. */
  { "ntfs",  0, 0, NULL, "ntfs3g", 0, 0 },
};

static void test_filesystem (guestfs_h *g, const struct filesystem *fs);
static void make_filesystem (guestfs_h *g, const struct filesystem *fs);
static void mount_filesystem (guestfs_h *g, const struct filesystem *fs);
static void unmount_filesystem (guestfs_h *g, const struct filesystem *fs);
static void test_ascii (guestfs_h *g, const struct filesystem *fs);
static void test_latin1 (guestfs_h *g, const struct filesystem *fs);
static void test_latin2 (guestfs_h *g, const struct filesystem *fs);
static void test_chinese (guestfs_h *g, const struct filesystem *fs);
static void ignore_lost_and_found (char **);

int
main (int argc, char *argv[])
{
  char *str;
  guestfs_h *g;
  size_t i;
  struct filesystem *fs;

  /* Allow this test to be skipped. */
  str = getenv (ourenvvar);
  if (str && guestfs_int_is_true (str) > 0) {
    printf ("%s: test skipped because environment variable is set.\n",
            guestfs_int_program_name);
    exit (77);
  }

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, 0, "failed to create handle");

  guestfs_set_program (g, "virt-testing");

  if (guestfs_add_drive_scratch (g, 1024*1024*1024, -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_part_disk (g, "/dev/sda", "mbr") == -1)
    exit (EXIT_FAILURE);

  for (i = 0; i < sizeof filesystems / sizeof filesystems[0]; ++i) {
    fs = &filesystems[i];
    test_filesystem (g, fs);
  }

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

/* This function coordinates the test for each filesystem type. */
static void
test_filesystem (guestfs_h *g, const struct filesystem *fs)
{
  const char *feature[] = { fs->fs_feature, NULL };
  char envvar[sizeof (ourenvvar) + 20];
  char *str;

  if (fs->fs_feature && !guestfs_feature_available (g, (char **) feature)) {
    printf ("skipped test of %s because %s feature not available\n",
            fs->fs_name, fs->fs_feature);
    return;
  }

  snprintf (envvar, sizeof envvar, "%s_%s", ourenvvar, fs->fs_name);
  str = getenv (envvar);
  if (str && guestfs_int_is_true (str) > 0) {
    printf ("skipped test of %s because environment variable is set\n",
            fs->fs_name);
    return;
  }

  printf ("testing charset fidelity on %s\n", fs->fs_name);

  make_filesystem (g, fs);
  mount_filesystem (g, fs);

  test_ascii (g, fs);

  if (fs->fs_8bit_only)
    goto out;

  if (!fs->fs_skip_latin1)
    test_latin1 (g, fs);
  if (!fs->fs_skip_latin2)
    test_latin2 (g, fs);
  test_chinese (g, fs);

 out:
  unmount_filesystem (g, fs);
}

static void
make_filesystem (guestfs_h *g, const struct filesystem *fs)
{
  if (guestfs_mkfs (g, fs->fs_name, "/dev/sda1") == -1)
    exit (EXIT_FAILURE);
}

static void
mount_filesystem (guestfs_h *g, const struct filesystem *fs)
{
  const char *mount_options;

  mount_options = fs->fs_mount_options ? : "";
  if (guestfs_mount_options (g, mount_options, "/dev/sda1", "/") == -1)
    exit (EXIT_FAILURE);
}

static void
unmount_filesystem (guestfs_h *g, const struct filesystem *fs)
{
  if (guestfs_umount (g, "/") == -1)
    exit (EXIT_FAILURE);
}

static void
test_ascii (guestfs_h *g, const struct filesystem *fs)
{
  char **files;
  size_t count;

  /* Create various ASCII-named files. */
  if (guestfs_touch (g, "/ABC") == -1)
    exit (EXIT_FAILURE);
  if (guestfs_touch (g, "/def") == -1)
    exit (EXIT_FAILURE);
  if (guestfs_touch (g, "/abc") == -1)
    exit (EXIT_FAILURE);

  /* Read list of files, check for case sensitivity. */
  files = guestfs_ls (g, "/");
  if (files == NULL)
    exit (EXIT_FAILURE);
  ignore_lost_and_found (files);
  count = guestfs_int_count_strings (files);

  if (fs->fs_case_insensitive) { /* case insensitive */
    if (count != 2)
      error (EXIT_FAILURE, 0,
             "error: %s: %s is supposed to be case-insensitive, but %zu files "
             "(instead of 2) were returned",
             __func__, fs->fs_name, count);

    if (STRCASENEQ (files[0], "abc") ||
        STRCASENEQ (files[1], "def"))
      error (EXIT_FAILURE, 0,
             "error: %s: %s returned unexpected filenames '%s' and '%s'",
             __func__, fs->fs_name, files[0], files[1]);
  }
  else {                        /* case sensitive */
    if (count != 3)
      error (EXIT_FAILURE, 0,
             "error: %s: %s is supposed to be case-sensitive, but %zu files "
             "(instead of 3) were returned",
             __func__, fs->fs_name, count);

    if (STRNEQ (files[0], "ABC") ||
        STRNEQ (files[1], "abc") ||
        STRNEQ (files[2], "def"))
      error (EXIT_FAILURE, 0,
             "error: %s: %s returned unexpected filenames '%s', '%s', '%s'",
             __func__, fs->fs_name, files[0], files[1], files[2]);

    if (guestfs_rm (g, "/abc") == -1)
      exit (EXIT_FAILURE);
  }

  if (guestfs_rm (g, "/ABC") == -1)
    exit (EXIT_FAILURE);
  if (guestfs_rm (g, "/def") == -1)
    exit (EXIT_FAILURE);
}

/* Note: This is testing characters in the Latin1 set, but the
 * encoding is still UTF-8 as it must be for libguestfs.
 */
static void
test_latin1 (guestfs_h *g, const struct filesystem *fs)
{
  /* LATIN CAPITAL LETTER O WITH TILDE */
  const char O_tilde[] = { 0xc3, 0x95, 0 };
  const char slash_O_tilde[] = { '/', 0xc3, 0x95, 0 };
  /* LATIN SMALL LETTER O WITH TILDE */
  const char o_tilde[] = { 0xc3, 0xb5, 0 };
  const char slash_o_tilde[] = { '/', 0xc3, 0xb5, 0 };

  char **files;
  size_t count;

  if (guestfs_touch (g, slash_O_tilde) == -1)
    exit (EXIT_FAILURE);
  if (guestfs_touch (g, slash_o_tilde) == -1)
    exit (EXIT_FAILURE);

  /* Read list of files, check for case sensitivity. */
  files = guestfs_ls (g, "/");
  if (files == NULL)
    exit (EXIT_FAILURE);
  ignore_lost_and_found (files);
  count = guestfs_int_count_strings (files);

  if (fs->fs_case_insensitive) { /* case insensitive */
    if (count != 1)
      error (EXIT_FAILURE, 0,
             "error: %s: %s is supposed to be case-insensitive, but %zu files "
             "(instead of 1) were returned",
             __func__, fs->fs_name, count);

    if (memcmp (files[0], o_tilde, 3) != 0 &&
        memcmp (files[0], O_tilde, 3) != 0)
      error (EXIT_FAILURE, 0,
             "error: %s: %s returned unexpected filename '%s'",
             __func__, fs->fs_name, files[0]);
  }
  else {                        /* case sensitive */
    if (count != 2)
      error (EXIT_FAILURE, 0,
             "error: %s: %s is supposed to be case-sensitive, but %zu files "
             "(instead of 2) were returned",
             __func__, fs->fs_name, count);

    if (memcmp (files[0], O_tilde, 3) != 0 ||
        memcmp (files[1], o_tilde, 3) != 0)
      error (EXIT_FAILURE, 0,
             "error: %s: %s returned unexpected filenames '%s' and '%s'",
             __func__, fs->fs_name, files[0], files[1]);

    if (guestfs_rm (g, slash_O_tilde) == -1)
      exit (EXIT_FAILURE);
  }

  if (guestfs_rm (g, slash_o_tilde) == -1)
    exit (EXIT_FAILURE);
}

/* Note: This is testing characters in the Latin2 set, but the
 * encoding is still UTF-8 as it must be for libguestfs.
 */
static void
test_latin2 (guestfs_h *g, const struct filesystem *fs)
{
  /* LATIN CAPITAL LETTER O WITH DOUBLE ACUTE */
  const char O_dacute[] = { 0xc5, 0x90, 0 };
  const char slash_O_dacute[] = { '/', 0xc5, 0x90, 0 };
  /* LATIN SMALL LETTER O WITH DOUBLE ACUTE */
  const char o_dacute[] = { 0xc5, 0x91, 0 };
  const char slash_o_dacute[] = { '/', 0xc5, 0x91, 0 };

  char **files;
  size_t count;

  if (guestfs_touch (g, slash_O_dacute) == -1)
    exit (EXIT_FAILURE);
  if (guestfs_touch (g, slash_o_dacute) == -1)
    exit (EXIT_FAILURE);

  /* Read list of files, check for case sensitivity. */
  files = guestfs_ls (g, "/");
  if (files == NULL)
    exit (EXIT_FAILURE);
  ignore_lost_and_found (files);
  count = guestfs_int_count_strings (files);

  if (fs->fs_case_insensitive) { /* case insensitive */
    if (count != 1)
      error (EXIT_FAILURE, 0,
             "error: %s: %s is supposed to be case-insensitive, but %zu files "
             "(instead of 1) were returned",
             __func__, fs->fs_name, count);

    if (memcmp (files[0], o_dacute, 3) != 0 &&
        memcmp (files[0], O_dacute, 3) != 0)
      error (EXIT_FAILURE, 0,
             "error: %s: %s returned unexpected filename '%s'",
             __func__, fs->fs_name, files[0]);
  }
  else {                        /* case sensitive */
    if (count != 2)
      error (EXIT_FAILURE, 0,
             "error: %s: %s is supposed to be case-sensitive, but %zu files "
             "(instead of 2) were returned",
             __func__, fs->fs_name, count);

    if (memcmp (files[0], O_dacute, 3) != 0 ||
        memcmp (files[1], o_dacute, 3) != 0)
      error (EXIT_FAILURE, 0,
             "error: %s: %s returned unexpected filenames '%s' and '%s'",
             __func__, fs->fs_name, files[0], files[1]);

    if (guestfs_rm (g, slash_O_dacute) == -1)
      exit (EXIT_FAILURE);
  }

  if (guestfs_rm (g, slash_o_dacute) == -1)
    exit (EXIT_FAILURE);
}

static void
test_chinese (guestfs_h *g, const struct filesystem *fs)
{
  /* Various Simplified Chinese characters from:
   * https://secure.wikimedia.org/wikipedia/en/wiki/Chinese_characters#Comparisons_of_traditional_Chinese.2C_simplified_Chinese.2C_and_Japanese
   */
  char filenames[][5] = {
    { '/', 0xe7, 0x94, 0xb5, 0 },
    { '/', 0xe4, 0xb9, 0xb0, 0 },
    { '/', 0xe5, 0xbc, 0x80, 0 },
    { '/', 0xe4, 0xb8, 0x9c, 0 },
    { '/', 0xe8, 0xbd, 0xa6, 0 },
    { '/', 0xe7, 0xba, 0xa2, 0 },
  };
  const size_t nr_filenames = sizeof filenames / sizeof filenames[0];
  size_t i, j;
  char **files;
  size_t count;

  for (i = 0; i < nr_filenames; ++i) {
    if (guestfs_touch (g, filenames[i]) == -1)
      exit (EXIT_FAILURE);
  }

  /* Check the filenames. */
  files = guestfs_ls (g, "/");
  if (files == NULL)
    exit (EXIT_FAILURE);
  ignore_lost_and_found (files);
  count = guestfs_int_count_strings (files);

  if (count != nr_filenames)
    error (EXIT_FAILURE, 0,
           "error: %s: %s returned unexpected number of files "
           "(%zu, expecting %zu)",
           __func__, fs->fs_name, count, nr_filenames);

  for (j = 0; j < count; ++j) {
    for (i = 0; i < nr_filenames; ++i)
      if (memcmp (files[j], &filenames[i][1], 4) == 0)
        goto next;
    error (EXIT_FAILURE, 0,
           "error: %s: %s returned unexpected filename '%s'",
           __func__, fs->fs_name, files[j]);

  next:;
  }

  for (i = 0; i < nr_filenames; ++i)
    if (guestfs_rm (g, filenames[i]) == -1)
      exit (EXIT_FAILURE);
}

/* Remove 'lost+found' and (I guess in future) other similar files
 * from the list.
 */
static void
ignore_lost_and_found (char **files)
{
  size_t i, j;

  for (i = j = 0; files[i] != NULL; ++i) {
    if (STREQ (files[i], "lost+found"))
      free (files[i]);
    else
      files[j++] = files[i];
  }
  files[j] = NULL;
}
