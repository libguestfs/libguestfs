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

/* This is not just a test of 'utils.c'.  We can test other internal
 * functions here too.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-frontend.h"

/* Test guestfs_int_split_string. */
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

/* Test guestfs_int_concat_strings. */
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

/* Test guestfs_int_join_strings. */
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

/* Test guestfs_int_validate_guid. */
static void
test_validate_guid (void)
{
  assert (guestfs_int_validate_guid ("") == 0);
  assert (guestfs_int_validate_guid ("1") == 0);
  assert (guestfs_int_validate_guid ("21EC20203AEA1069A2DD08002B30309D") == 0);

  assert (guestfs_int_validate_guid ("{21EC2020-3AEA-1069-A2DD-08002B30309D}") == 1);
  assert (guestfs_int_validate_guid ("21EC2020-3AEA-1069-A2DD-08002B30309D") == 1);
}

int
main (int argc, char *argv[])
{
  test_split ();
  test_concat ();
  test_join ();
  test_validate_guid ();

  exit (EXIT_SUCCESS);
}
