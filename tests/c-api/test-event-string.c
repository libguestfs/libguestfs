/* libguestfs
 * Copyright (C) 2013 Red Hat Inc.
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

/* Test guestfs_event_to_string. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

#include "guestfs.h"
#include "guestfs-utils.h"

int
main (int argc, char *argv[])
{
  uint64_t events;
  char *str;

  events = 0;
  str = guestfs_event_to_string (events);
  assert (str != NULL);
  assert (STREQ (str, ""));
  free (str);

  events = GUESTFS_EVENT_CLOSE;
  str = guestfs_event_to_string (events);
  assert (str != NULL);
  assert (STREQ (str, "close"));
  free (str);

  events = GUESTFS_EVENT_CLOSE | GUESTFS_EVENT_PROGRESS;
  str = guestfs_event_to_string (events);
  assert (str != NULL);
  assert (STREQ (str, "close,progress"));
  free (str);

  events = GUESTFS_EVENT_CLOSE | GUESTFS_EVENT_SUBPROCESS_QUIT | GUESTFS_EVENT_ENTER;
  str = guestfs_event_to_string (events);
  assert (str != NULL);
  assert (STREQ (str, "close,enter,subprocess_quit"));
  free (str);

  events = GUESTFS_EVENT_ALL;
  str = guestfs_event_to_string (events);
  assert (str != NULL);
  free (str);

  exit (EXIT_SUCCESS);
}
