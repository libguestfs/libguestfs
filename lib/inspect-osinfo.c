/* libguestfs
 * Copyright (C) 2018 Red Hat Inc.
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

#include <config.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

char *
guestfs_impl_inspect_get_osinfo (guestfs_h *g, const char *root)
{
  CLEANUP_FREE char *type = NULL;
  CLEANUP_FREE char *distro = NULL;
  int major, minor;

  type = guestfs_inspect_get_type (g, root);
  if (!type)
    return NULL;
  distro = guestfs_inspect_get_distro (g, root);
  if (!distro)
    return NULL;
  major = guestfs_inspect_get_major_version (g, root);
  minor = guestfs_inspect_get_minor_version (g, root);

  if (STREQ (type, "linux")) {
    if (STREQ (distro, "centos")) {
      if (major >= 7)
        return safe_asprintf (g, "%s%d.0", distro, major);
      else if (major == 6)
        return safe_asprintf (g, "%s%d.%d", distro, major, minor);
    }
    else if (STREQ (distro, "debian")) {
      if (major >= 4)
        return safe_asprintf (g, "%s%d", distro, major);
    }
    else if (STREQ (distro, "fedora") || STREQ (distro, "mageia"))
      return safe_asprintf (g, "%s%d", distro, major);
    else if (STREQ (distro, "sles")) {
      if (minor == 0)
        return safe_asprintf (g, "%s%d", distro, major);
      else
        return safe_asprintf (g, "%s%dsp%d", distro, major, minor);
    }
    else if (STREQ (distro, "ubuntu"))
      return safe_asprintf (g, "%s%d.%02d", distro, major, minor);

    if (major > 0 || minor > 0)
      return safe_asprintf (g, "%s%d.%d", distro, major, minor);
  }
  else if (STREQ (type, "freebsd") || STREQ (type, "netbsd") || STREQ (type, "openbsd"))
    return safe_asprintf (g, "%s%d.%d", distro, major, minor);
  else if (STREQ (type, "dos")) {
    if (STREQ (distro, "msdos"))
      return safe_strdup (g, "msdos6.22");
  }

  /* No ID could be guessed, return "unknown". */
  return safe_strdup (g, "unknown");
}
