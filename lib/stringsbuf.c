/* libguestfs
 * Copyright (C) 2013 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

/**
 * An expandable NULL-terminated vector of strings (like C<argv>).
 *
 * Use the C<DECLARE_STRINGSBUF> macro to declare the stringsbuf.
 *
 * Note: Don't confuse this with stringsbuf in the daemon which
 * is a different type with different methods.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

#include "guestfs.h"
#include "guestfs-internal.h"

/**
 * Add a string to the end of the list.
 *
 * This doesn't call L<strdup(3)> on the string, so the string itself
 * is stored inside the vector.
 */
void
guestfs_int_add_string_nodup (guestfs_h *g, struct stringsbuf *sb, char *str)
{
  if (sb->size >= sb->alloc) {
    sb->alloc += 64;
    sb->argv = safe_realloc (g, sb->argv, sb->alloc * sizeof (char *));
  }

  sb->argv[sb->size] = str;
  sb->size++;
}

/**
 * Add a string to the end of the list.
 *
 * This makes a copy of the string.
 */
void
guestfs_int_add_string (guestfs_h *g, struct stringsbuf *sb, const char *str)
{
  guestfs_int_add_string_nodup (g, sb, safe_strdup (g, str));
}

/**
 * Add a string to the end of the list.
 *
 * Uses an sprintf-like format string when creating the string.
 */
void
guestfs_int_add_sprintf (guestfs_h *g, struct stringsbuf *sb,
			 const char *fs, ...)
{
  va_list args;
  char *str;
  int r;

  va_start (args, fs);
  r = vasprintf (&str, fs, args);
  va_end (args);
  if (r == -1)
    g->abort_cb ();

  guestfs_int_add_string_nodup (g, sb, str);
}

/**
 * Finish the string buffer.
 *
 * This adds the terminating NULL to the end of the vector.
 */
void
guestfs_int_end_stringsbuf (guestfs_h *g, struct stringsbuf *sb)
{
  guestfs_int_add_string_nodup (g, sb, NULL);
}

/**
 * Free the string buffer and the strings.
 */
void
guestfs_int_free_stringsbuf (struct stringsbuf *sb)
{
  size_t i;

  if (sb->argv) {
    for (i = 0; i < sb->size; ++i)
      free (sb->argv[i]);
  }
  free (sb->argv);
}

void
guestfs_int_cleanup_free_stringsbuf (struct stringsbuf *sb)
{
  guestfs_int_free_stringsbuf (sb);
}
