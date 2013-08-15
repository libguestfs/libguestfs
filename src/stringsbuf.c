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

/* Note: Don't confuse this with stringsbuf in the daemon. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

#include "guestfs.h"
#include "guestfs-internal.h"

void
guestfs___add_string_nodup (guestfs_h *g, struct stringsbuf *sb, char *str)
{
  if (sb->size >= sb->alloc) {
    sb->alloc += 64;
    sb->argv = safe_realloc (g, sb->argv, sb->alloc * sizeof (char *));
  }

  sb->argv[sb->size] = str;
  sb->size++;
}

void
guestfs___add_string (guestfs_h *g, struct stringsbuf *sb, const char *str)
{
  guestfs___add_string_nodup (g, sb, safe_strdup (g, str));
}

void
guestfs___add_sprintf (guestfs_h *g, struct stringsbuf *sb,
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

  guestfs___add_string_nodup (g, sb, str);
}

void
guestfs___end_stringsbuf (guestfs_h *g, struct stringsbuf *sb)
{
  guestfs___add_string_nodup (g, sb, NULL);
}

void
guestfs___free_stringsbuf (struct stringsbuf *sb)
{
  size_t i;

  if (sb->argv) {
    for (i = 0; i < sb->size; ++i)
      free (sb->argv[i]);
  }
  free (sb->argv);
}

void
guestfs___cleanup_free_stringsbuf (struct stringsbuf *sb)
{
  guestfs___free_stringsbuf (sb);
}
