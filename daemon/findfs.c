/* libguestfs - the guestfsd daemon
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

#include "daemon.h"
#include "actions.h"

static char *
findfs (const char *tag, const char *label_or_uuid)
{
  /* Kill the cache file, forcing blkid to reread values from the
   * original filesystems.  In blkid there is a '-p' option which is
   * supposed to do this, but (a) it doesn't work and (b) that option
   * is not supported in RHEL 5.
   */
  unlink ("/etc/blkid/blkid.tab");
  unlink ("/run/blkid/blkid.tab");

  size_t len = strlen (tag) + strlen (label_or_uuid) + 2;
  char arg[len];
  snprintf (arg, len, "%s=%s", tag, label_or_uuid);

  char *out, *err;
  int r = command (&out, &err, "findfs", arg, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  /* Trim trailing \n if present. */
  len = strlen (out);
  if (len > 0 && out[len-1] == '\n')
    out[len-1] = '\0';

  if (STRPREFIX (out, "/dev/mapper/") || STRPREFIX (out, "/dev/dm-")) {
    char *canonical;
    r = lv_canonical (out, &canonical);
    if (r == -1) {
      free (out);
      return NULL;
    }
    if (r == 1) {
      free (out);
      out = canonical;
    }
    /* Ignore the case where r == 0.  /dev/mapper does not correspond
     * to an LV, so the best we can do is just return it as-is.
     */
  }

  return out;                   /* caller frees */
}

char *
do_findfs_uuid (const char *uuid)
{
  return findfs ("UUID", uuid);
}

char *
do_findfs_label (const char *label)
{
  return findfs ("LABEL", label);
}
