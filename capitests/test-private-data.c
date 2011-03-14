/* libguestfs
 * Copyright (C) 2011 Red Hat Inc.
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

/* Test aspects of the private data area API. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <assert.h>

#include "guestfs.h"

#define PREFIX "test_"

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  const char *key;
  void *data;
  size_t count;

  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, "failed to create handle\n");
    exit (EXIT_FAILURE);
  }

  guestfs_set_private (g, PREFIX "a", (void *) 1);
  guestfs_set_private (g, PREFIX "b", (void *) 2);
  guestfs_set_private (g, PREFIX "c", (void *) 3);
  guestfs_set_private (g, PREFIX "a", (void *) 4); /* overwrites previous */

  /* Check we can fetch keys. */
  assert (guestfs_get_private (g, PREFIX "a") == (void *) 4);
  assert (guestfs_get_private (g, PREFIX "b") == (void *) 2);
  assert (guestfs_get_private (g, PREFIX "c") == (void *) 3);
  assert (guestfs_get_private (g, PREFIX "d") == NULL);

  /* Check we can count keys by iterating. */
  count = 0;
  data = guestfs_first_private (g, &key);
  while (data != NULL) {
    if (strncmp (key, PREFIX, strlen (PREFIX)) == 0)
      count++;
    data = guestfs_next_private (g, &key);
  }
  assert (count == 3);

  /* Delete some keys. */
  guestfs_set_private (g, PREFIX "a", NULL);
  guestfs_set_private (g, PREFIX "b", NULL);

  /* Count them again. */
  count = 0;
  data = guestfs_first_private (g, &key);
  while (data != NULL) {
    if (strncmp (key, PREFIX, strlen (PREFIX)) == 0)
      count++;
    data = guestfs_next_private (g, &key);
  }
  assert (count == 1);

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}
