/* guestfish - the filesystem interactive shell
 * Copyright (C) 2010 Red Hat Inc.
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
#include <string.h>
#include <unistd.h>
#include <libintl.h>

#include "fish.h"

int
run_supported (const char *cmd, size_t argc, char *argv[])
{
  char **groups;

  /* As a side-effect this also checks that we've called 'launch'. */
  groups = guestfs_available_all_groups (g);
  if (groups == NULL)
    return -1;

  /* Temporarily replace the error handler so that messages don't get
   * printed to stderr while we are issuing commands.
   */
  guestfs_error_handler_cb old_error_cb;
  void *old_error_cb_data;
  old_error_cb = guestfs_get_error_handler (g, &old_error_cb_data);
  guestfs_set_error_handler (g, NULL, NULL);

  /* Work out the max string length of any group name. */
  size_t i;
  size_t len = 0;
  for (i = 0; groups[i] != NULL; ++i) {
    size_t l = strlen (groups[i]);
    if (l > len)
      len = l;
  }

  for (i = 0; groups[i] != NULL; ++i) {
    size_t l = strlen (groups[i]);
    size_t j;
    for (j = 0; j < len-l; ++j)
      putchar (' ');
    printf ("%s", groups[i]);
    putchar (' ');

    char *gg[] = { groups[i], NULL };
    int r = guestfs_available (g, gg);
    if (r == 0)
      printf ("%s", _("yes"));
    else
      printf ("%s", _("no"));
    putchar ('\n');
  }

  /* Free groups list. */
  for (i = 0; groups[i] != NULL; ++i)
    free (groups[i]);
  free (groups);

  /* Restore error handler. */
  guestfs_set_error_handler (g, old_error_cb, old_error_cb_data);

  return 0;
}
