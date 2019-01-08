/* libguestfs - the guestfsd daemon
 * Copyright (C) 2010-2019 Red Hat Inc.
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

#include "daemon.h"

/* This just stops gcc from giving a warning about our custom printf
 * formatters %Q and %R.  See guestfs-hacking(1) for more
 * info about these.  In GCC 4.8.0 the warning is even harder to
 * 'trick', hence the need for the #pragma directives.
 */
#if defined(__GNUC__) && GUESTFS_GCC_VERSION >= 40800 /* gcc >= 4.8.0 */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wsuggest-attribute=format"
#endif
int
asprintf_nowarn (char **strp, const char *fmt, ...)
{
  int r;
  va_list args;

  va_start (args, fmt);
  r = vasprintf (strp, fmt, args);
  va_end (args);
  return r;
}
#if defined(__GNUC__) && GUESTFS_GCC_VERSION >= 40800 /* gcc >= 4.8.0 */
#pragma GCC diagnostic pop
#endif
