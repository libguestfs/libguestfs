/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2011 Red Hat Inc.
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
#include "actions.h"

static int cpmv_cmd (const char *cmd, const char *flags, const char *src, const char *dest);

int
do_cp (const char *src, const char *dest)
{
  return cpmv_cmd ("cp", NULL, src, dest);
}

int
do_cp_a (const char *src, const char *dest)
{
  return cpmv_cmd ("cp", "-a", src, dest);
}

int
do_mv (const char *src, const char *dest)
{
  return cpmv_cmd ("mv", NULL, src, dest);
}

static int
cpmv_cmd (const char *cmd, const char *flags, const char *src, const char *dest)
{
  char *srcbuf, *destbuf;
  char *err;
  int r;

  srcbuf = sysroot_path (src);
  if (srcbuf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  destbuf = sysroot_path (dest);
  if (destbuf == NULL) {
    reply_with_perror ("malloc");
    free (srcbuf);
    return -1;
  }

  pulse_mode_start ();

  if (flags)
    r = command (NULL, &err, cmd, flags, srcbuf, destbuf, NULL);
  else
    r = command (NULL, &err, cmd, srcbuf, destbuf, NULL);

  free (srcbuf);
  free (destbuf);

  if (r == -1) {
    pulse_mode_cancel ();
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }
  free (err);

  pulse_mode_end ();

  return 0;
}
