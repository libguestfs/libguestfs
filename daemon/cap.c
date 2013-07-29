/* libguestfs - the guestfsd daemon
 * Copyright (C) 2012 Red Hat Inc.
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
#include <limits.h>
#include <unistd.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#if defined(HAVE_CAP)

#include <sys/capability.h>

int
optgroup_linuxcaps_available (void)
{
  return 1;
}

char *
do_cap_get_file (const char *path)
{
  cap_t cap;
  char *r, *ret;

  CHROOT_IN;
  cap = cap_get_file (path);
  CHROOT_OUT;

  if (cap == NULL) {
    /* The getcap utility (part of libcap) ignores ENODATA.  It just
     * means there is no capability attached to the file (RHBZ#989356).
     */
    if (errno == ENODATA) {
      ret = strdup ("");
      if (ret == NULL) {
        reply_with_perror ("strdup");
        return NULL;
      }
      return ret;
    }

    reply_with_perror ("%s", path);
    return NULL;
  }

  r = cap_to_text (cap, NULL);
  if (r == NULL) {
    reply_with_perror ("cap_to_text");
    cap_free (cap);
    return NULL;
  }

  cap_free (cap);

  /* 'r' is not an ordinary pointer that can be freed with free(3)!
   * In the current implementation of libcap, if you try to do that it
   * will segfault.  We have to duplicate this into an ordinary
   * buffer, then call cap_free (r).
   */
  ret = strdup (r);
  if (ret == NULL) {
    reply_with_perror ("strdup");
    cap_free (r);
    return NULL;
  }
  cap_free (r);

  return ret;                   /* caller frees */
}

int
do_cap_set_file (const char *path, const char *capstr)
{
  cap_t cap;
  int r;

  cap = cap_from_text (capstr);
  if (cap == NULL) {
    reply_with_perror ("could not parse cap string: %s: cap_from_text", capstr);
    return -1;
  }

  CHROOT_IN;
  r = cap_set_file (path, cap);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    cap_free (cap);
    return -1;
  }

  cap_free (cap);

  return 0;
}

#else /* no libcap */

OPTGROUP_LINUXCAPS_NOT_AVAILABLE

#endif /* no libcap */
