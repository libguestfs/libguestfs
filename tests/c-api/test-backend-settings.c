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

/* Test backend settings API. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>
#include <assert.h>

#include "guestfs.h"
#include "guestfs-utils.h"

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  char **strs;
  char *str;
  int r, pass;

  /* Make sure that LIBGUESTFS_BACKEND_SETTINGS in the test
   * environment doesn't affect the handle.
   */
  unsetenv ("LIBGUESTFS_BACKEND_SETTINGS");

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");

  /* There should be no backend settings initially. */
  strs = guestfs_get_backend_settings (g);
  assert (strs != NULL);
  assert (strs[0] == NULL);
  guestfs_int_free_string_list (strs);

  guestfs_push_error_handler (g, NULL, NULL);
  str = guestfs_get_backend_setting (g, "foo");
  guestfs_pop_error_handler (g);
  assert (str == NULL);
  assert (guestfs_last_errno (g) == ESRCH);

  r = guestfs_clear_backend_setting (g, "bar");
  assert (r == 0);

  /* Create some settings in the handle, either using
   * guestfs_set_backend_settings or using the environment variable.
   */
  for (pass = 0; pass <= 1; ++pass) {
    if (pass == 0) {
      const char *initial_settings[] = {
        "foo", "foo=1", "foo=bar", "bar", "baz=value", NULL
      };
      r = guestfs_set_backend_settings (g, (char **) initial_settings);
      assert (r == 0);
    }
    else /* pass == 1 */ {
      const char *initial_settings = "foo:foo=1:foo=bar:bar:baz=value";

      guestfs_close (g);

      setenv ("LIBGUESTFS_BACKEND_SETTINGS", initial_settings, 1);
      g = guestfs_create ();
      if (g == NULL)
        error (EXIT_FAILURE, errno, "guestfs_create");
    }

    /* Check the settings are correct. */
    strs = guestfs_get_backend_settings (g);
    assert (strs != NULL);
    assert (STREQ (strs[0], "foo"));
    assert (STREQ (strs[1], "foo=1"));
    assert (STREQ (strs[2], "foo=bar"));
    assert (STREQ (strs[3], "bar"));
    assert (STREQ (strs[4], "baz=value"));
    assert (strs[5] == NULL);
    guestfs_int_free_string_list (strs);

    str = guestfs_get_backend_setting (g, "bar");
    assert (str != NULL);
    assert (STREQ (str, "1"));
    free (str);

    str = guestfs_get_backend_setting (g, "baz");
    assert (str != NULL);
    assert (STREQ (str, "value"));
    free (str);

    str = guestfs_get_backend_setting (g, "foo");
    assert (str != NULL);
    /* An implementation could return any of the values. */
    free (str);

    guestfs_push_error_handler (g, NULL, NULL);
    str = guestfs_get_backend_setting (g, "nothere");
    guestfs_pop_error_handler (g);
    assert (str == NULL);
    assert (guestfs_last_errno (g) == ESRCH);

    r = guestfs_set_backend_setting (g, "foo", "");
    assert (r == 0);
    r = guestfs_set_backend_setting (g, "foo", "1");
    assert (r == 0);
    r = guestfs_set_backend_setting (g, "foo", "2");
    assert (r == 0);
    r = guestfs_set_backend_setting (g, "foo", "3");
    assert (r == 0);
    r = guestfs_clear_backend_setting (g, "foo");
    assert (r == 1);

    r = guestfs_clear_backend_setting (g, "bar");
    assert (r == 1);

    r = guestfs_clear_backend_setting (g, "baz");
    assert (r == 1);

    strs = guestfs_get_backend_settings (g);
    assert (strs != NULL);
    assert (strs[0] == NULL);
    guestfs_int_free_string_list (strs);
  }

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}
