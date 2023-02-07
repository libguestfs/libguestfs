/* libguestfs
 * Copyright (C) 2014-2023 Red Hat Inc.
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

/**
 * Unit tests of internal functions.
 *
 * These tests may use a libguestfs handle, but must not launch the
 * handle.  Also, avoid long-running tests.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-utils.h"

/**
 * Test C<guestfs_int_split_string>.
 */
static void
test_split (void)
{
  char **ret;

  ret = guestfs_int_split_string (':', "");
  assert (ret);
  assert (guestfs_int_count_strings (ret) == 0);
  guestfs_int_free_string_list (ret);

  ret = guestfs_int_split_string (':', "a");
  assert (ret);
  assert (guestfs_int_count_strings (ret) == 1);
  assert (STREQ (ret[0], "a"));
  guestfs_int_free_string_list (ret);

  ret = guestfs_int_split_string (':', ":");
  assert (ret);
  assert (guestfs_int_count_strings (ret) == 2);
  assert (STREQ (ret[0], ""));
  assert (STREQ (ret[1], ""));
  guestfs_int_free_string_list (ret);

  ret = guestfs_int_split_string (':', "::");
  assert (ret);
  assert (guestfs_int_count_strings (ret) == 3);
  assert (STREQ (ret[0], ""));
  assert (STREQ (ret[1], ""));
  assert (STREQ (ret[2], ""));
  guestfs_int_free_string_list (ret);

  ret = guestfs_int_split_string (':', ":a");
  assert (ret);
  assert (guestfs_int_count_strings (ret) == 2);
  assert (STREQ (ret[0], ""));
  assert (STREQ (ret[1], "a"));
  guestfs_int_free_string_list (ret);

  ret = guestfs_int_split_string (':', "a:");
  assert (ret);
  assert (guestfs_int_count_strings (ret) == 2);
  assert (STREQ (ret[0], "a"));
  assert (STREQ (ret[1], ""));
  guestfs_int_free_string_list (ret);

  ret = guestfs_int_split_string (':', "a:b:c");
  assert (ret);
  assert (guestfs_int_count_strings (ret) == 3);
  assert (STREQ (ret[0], "a"));
  assert (STREQ (ret[1], "b"));
  assert (STREQ (ret[2], "c"));
  guestfs_int_free_string_list (ret);
}

/**
 * Test C<guestfs_int_concat_strings>.
 */
static void
test_concat (void)
{
  char *ret;
  const char *test1[] = { NULL };
  const char *test2[] = { "", NULL };
  const char *test3[] = { "a", NULL };
  const char *test4[] = { "a", "", NULL };
  const char *test5[] = { "a", "b", NULL };

  ret = guestfs_int_concat_strings ((char **) test1);
  assert (STREQ (ret, ""));
  free (ret);

  ret = guestfs_int_concat_strings ((char **) test2);
  assert (STREQ (ret, ""));
  free (ret);

  ret = guestfs_int_concat_strings ((char **) test3);
  assert (STREQ (ret, "a"));
  free (ret);

  ret = guestfs_int_concat_strings ((char **) test4);
  assert (STREQ (ret, "a"));
  free (ret);

  ret = guestfs_int_concat_strings ((char **) test5);
  assert (STREQ (ret, "ab"));
  free (ret);
}

/**
 * Test C<guestfs_int_join_strings>.
 */
static void
test_join (void)
{
  char *ret;
  const char *test1[] = { NULL };
  const char *test2[] = { "", NULL };
  const char *test3[] = { "a", NULL };
  const char *test4[] = { "a", "", NULL };
  const char *test5[] = { "a", "b", NULL };

  ret = guestfs_int_join_strings (":!", (char **) test1);
  assert (STREQ (ret, ""));
  free (ret);

  ret = guestfs_int_join_strings (":!", (char **) test2);
  assert (STREQ (ret, ""));
  free (ret);

  ret = guestfs_int_join_strings (":!", (char **) test3);
  assert (STREQ (ret, "a"));
  free (ret);

  ret = guestfs_int_join_strings (":!", (char **) test4);
  assert (STREQ (ret, "a:!"));
  free (ret);

  ret = guestfs_int_join_strings (":!", (char **) test5);
  assert (STREQ (ret, "a:!b"));
  free (ret);
}

/**
 * Test C<guestfs_int_validate_guid>.
 */
static void
test_validate_guid (void)
{
  assert (guestfs_int_validate_guid ("") == 0);
  assert (guestfs_int_validate_guid ("1") == 0);
  assert (guestfs_int_validate_guid ("21EC20203AEA1069A2DD08002B30309D") == 0);

  assert (guestfs_int_validate_guid ("{21EC2020-3AEA-1069-A2DD-08002B30309D}") == 1);
  assert (guestfs_int_validate_guid ("21EC2020-3AEA-1069-A2DD-08002B30309D") == 1);
}

/**
 * Test C<guestfs_int_drive_name>.
 */
static void
test_drive_name (void)
{
  char s[10];

  guestfs_int_drive_name (0, s);
  assert (STREQ (s, "a"));
  guestfs_int_drive_name (25, s);
  assert (STREQ (s, "z"));
  guestfs_int_drive_name (26, s);
  assert (STREQ (s, "aa"));
  guestfs_int_drive_name (27, s);
  assert (STREQ (s, "ab"));
  guestfs_int_drive_name (51, s);
  assert (STREQ (s, "az"));
  guestfs_int_drive_name (52, s);
  assert (STREQ (s, "ba"));
  guestfs_int_drive_name (701, s);
  assert (STREQ (s, "zz"));
  guestfs_int_drive_name (702, s);
  assert (STREQ (s, "aaa"));
  guestfs_int_drive_name (18277, s);
  assert (STREQ (s, "zzz"));
}

/**
 * Test C<guestfs_int_drive_index>.
 */
static void
test_drive_index (void)
{
  assert (guestfs_int_drive_index ("a") == 0);
  assert (guestfs_int_drive_index ("z") == 25);
  assert (guestfs_int_drive_index ("aa") == 26);
  assert (guestfs_int_drive_index ("ab") == 27);
  assert (guestfs_int_drive_index ("az") == 51);
  assert (guestfs_int_drive_index ("ba") == 52);
  assert (guestfs_int_drive_index ("zz") == 701);
  assert (guestfs_int_drive_index ("aaa") == 702);
  assert (guestfs_int_drive_index ("zzz") == 18277);

  assert (guestfs_int_drive_index ("") == -1);
  assert (guestfs_int_drive_index ("abc123") == -1);
  assert (guestfs_int_drive_index ("123") == -1);
  assert (guestfs_int_drive_index ("Z") == -1);
  assert (guestfs_int_drive_index ("aB") == -1);
}

/**
 * Test C<guestfs_int_getumask>.
 */
static void
test_getumask (void)
{
  guestfs_h *g;
  const int orig_umask = umask (0777);

  g = guestfs_create ();
  assert (g);

  assert (guestfs_int_getumask (g) == 0777);
  umask (0022);
  assert (guestfs_int_getumask (g) == 0022);
  assert (guestfs_int_getumask (g) == 0022);
  umask (0222);
  assert (guestfs_int_getumask (g) == 0222);
  umask (0000);
  assert (guestfs_int_getumask (g) == 0000);

  umask (orig_umask);           /* Restore original umask. */
  guestfs_close (g);
}

/**
 * Test C<guestfs_int_new_command> etc.
 *
 * XXX These tests could be made much more thorough.  So far we simply
 * test that it's not obviously broken.
 */
static void
test_command (void)
{
  guestfs_h *g;
  struct command *cmd;
  int r;

  g = guestfs_create ();
  assert (g);

  /* argv-style */
  cmd = guestfs_int_new_command (g);
  assert (cmd);
  guestfs_int_cmd_add_arg (cmd, "touch");
  guestfs_int_cmd_add_arg (cmd, "test-utils-test-command");
  r = guestfs_int_cmd_run (cmd);
  assert (r == 0);
  guestfs_int_cmd_close (cmd);

  /* system-style */
  cmd = guestfs_int_new_command (g);
  assert (cmd);
  guestfs_int_cmd_add_string_unquoted (cmd, "rm ");
  guestfs_int_cmd_add_string_quoted (cmd, "test-utils-test-command");
  r = guestfs_int_cmd_run (cmd);
  assert (r == 0);
  guestfs_int_cmd_close (cmd);

  guestfs_close (g);
}

/**
 * Test C<guestfs_int_qemu_escape_param>
 *
 * XXX I wanted to make this test run qemu, passing some parameters
 * which need to be escaped, but I cannot think of a way to do that
 * without launching a VM.
 */
static void
test_qemu_escape_param (void)
{
  CLEANUP_FREE char *ret1 = NULL, *ret2 = NULL, *ret3 = NULL;
  guestfs_h *g;

  g = guestfs_create ();
  assert (g);

  ret1 = guestfs_int_qemu_escape_param (g, "name,with,commas");
  assert (STREQ (ret1, "name,,with,,commas"));

  ret2 = guestfs_int_qemu_escape_param (g, ",,,,");
  assert (STREQ (ret2, ",,,,,,,,"));

  ret3 = guestfs_int_qemu_escape_param (g, "");
  assert (STREQ (ret3, ""));

  guestfs_close (g);
}

/**
 * Test C<guestfs_int_timeval_diff>.
 */
static void
test_timeval_diff (void)
{
  struct timeval x, y;
  int64_t ms;

  y.tv_sec = 1;
  y.tv_usec = 0;
  x.tv_sec = 0;
  x.tv_usec = 0;
  ms = guestfs_int_timeval_diff (&x, &y);
  assert (ms == 1000);

  y.tv_sec = 0;
  y.tv_usec = 0;
  x.tv_sec = 1;
  x.tv_usec = 0;
  ms = guestfs_int_timeval_diff (&x, &y);
  assert (ms == -1000);

  y.tv_sec = 1;
  y.tv_usec = 0;
  x.tv_sec = 0;
  x.tv_usec = 900000;
  ms = guestfs_int_timeval_diff (&x, &y);
  assert (ms == 100);

  y.tv_sec = 0;
  y.tv_usec = 900000;
  x.tv_sec = 1;
  x.tv_usec = 0;
  ms = guestfs_int_timeval_diff (&x, &y);
  assert (ms == -100);

  y.tv_sec = 1;
  y.tv_usec = 100000;
  x.tv_sec = 0;
  x.tv_usec = 900000;
  ms = guestfs_int_timeval_diff (&x, &y);
  assert (ms == 200);

  y.tv_sec = 0;
  y.tv_usec = 900000;
  x.tv_sec = 1;
  x.tv_usec = 100000;
  ms = guestfs_int_timeval_diff (&x, &y);
  assert (ms == -200);
}

COMPILE_REGEXP (test_match_re, "a+b", 0)
COMPILE_REGEXP (test_match1_re, "(a+)b", 0)
COMPILE_REGEXP (test_match2_re, "(a+)(b)", 0)

static void
test_match (void)
{
  guestfs_h *g;
  char *ret, *ret2;

  g = guestfs_create ();
  assert (g);

  assert (match (g, "aaaaab", test_match_re));
  assert (! match (g, "aaaaacb", test_match_re));
  assert (! match (g, "", test_match_re));

  ret = match1 (g, "aaab", test_match1_re);
  assert (STREQ (ret, "aaa"));
  free (ret);

  assert (! match1 (g, "aaacb", test_match1_re));
  assert (! match1 (g, "", test_match1_re));

  assert (match2 (g, "aaabc", test_match2_re, &ret, &ret2));
  assert (STREQ (ret, "aaa"));
  assert (STREQ (ret2, "b"));
  free (ret);
  free (ret2);

  guestfs_close (g);
}

static void
test_stringsbuf (void)
{
  guestfs_h *g;
  DECLARE_STRINGSBUF (sb);

  g = guestfs_create ();
  assert (g);

  guestfs_int_add_string (g, &sb, "aaa");
  guestfs_int_add_string (g, &sb, "bbb");
  guestfs_int_add_string (g, &sb, "ccc");
  guestfs_int_add_string (g, &sb, "");
  guestfs_int_end_stringsbuf (g, &sb);

  assert (sb.size == 5 /* 4 strings + terminating NULL */);
  assert (STREQ (sb.argv[0], "aaa"));
  assert (STREQ (sb.argv[1], "bbb"));
  assert (STREQ (sb.argv[2], "ccc"));
  assert (STREQ (sb.argv[3], ""));
  assert (sb.argv[4] == NULL);

  assert (guestfs_int_count_strings (sb.argv) == 4);

  guestfs_int_free_stringsbuf (&sb);
  guestfs_close (g);
}

/* Use the same macros as in lib/drives.c */
#define VALID_FORMAT(str) \
  guestfs_int_string_is_valid ((str), 1, 0, \
                               VALID_FLAG_ALPHA|VALID_FLAG_DIGIT, "-_")
#define VALID_DISK_LABEL(str) \
  guestfs_int_string_is_valid ((str), 1, 20, VALID_FLAG_ALPHA, NULL)
#define VALID_HOSTNAME(str) \
  guestfs_int_string_is_valid ((str), 1, 255, \
                               VALID_FLAG_ALPHA|VALID_FLAG_DIGIT, "-.:[]")

static void
test_valid (void)
{
  assert (!VALID_FORMAT (""));
  assert (!VALID_DISK_LABEL (""));
  assert (!VALID_HOSTNAME (""));

  assert (!VALID_DISK_LABEL ("012345678901234567890"));

  assert (VALID_FORMAT ("abc"));
  assert (VALID_FORMAT ("ABC"));
  assert (VALID_FORMAT ("abc123"));
  assert (VALID_FORMAT ("abc123-"));
  assert (VALID_FORMAT ("abc123_"));
  assert (!VALID_FORMAT ("abc123."));

  assert (VALID_DISK_LABEL ("abc"));
  assert (VALID_DISK_LABEL ("ABC"));
  assert (!VALID_DISK_LABEL ("abc123"));
  assert (!VALID_DISK_LABEL ("abc123-"));

  assert (VALID_HOSTNAME ("abc"));
  assert (VALID_HOSTNAME ("ABC"));
  assert (VALID_HOSTNAME ("abc123"));
  assert (VALID_HOSTNAME ("abc-123"));
  assert (VALID_HOSTNAME ("abc.123"));
  assert (VALID_HOSTNAME ("abc:123"));
  assert (VALID_HOSTNAME ("abc[123]"));
  assert (!VALID_HOSTNAME ("abc/def"));
}

int
main (int argc, char *argv[])
{
  test_split ();
  test_concat ();
  test_join ();
  test_validate_guid ();
  test_drive_name ();
  test_drive_index ();
  test_getumask ();
  test_command ();
  test_qemu_escape_param ();
  test_timeval_diff ();
  test_match ();
  test_stringsbuf ();
  test_valid ();

  exit (EXIT_SUCCESS);
}
