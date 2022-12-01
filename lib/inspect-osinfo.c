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
      if (major >= 8)
        return safe_asprintf (g, "%s%d", distro, major);
      else if (major == 7)
        return safe_asprintf (g, "%s%d.0", distro, major);
      else if (major == 6)
        return safe_asprintf (g, "%s%d.%d", distro, major, minor);
    }
    else if (STREQ (distro, "rocky")) {
      if (major >= 8)
        return safe_asprintf (g, "%s%d", distro, major);
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
    else if (STREQ (distro, "archlinux") || STREQ (distro, "gentoo")
             || STREQ (distro, "voidlinux"))
      return safe_strdup (g, distro);
    else if (STREQ (distro, "altlinux")) {
      if (major >= 8)
        return safe_asprintf (g, "alt%d.%d", major, minor);
      return safe_asprintf (g, "%s%d.%d", distro, major, minor);
    }

    if (STRNEQ (distro, "unknown") && (major > 0 || minor > 0))
      return safe_asprintf (g, "%s%d.%d", distro, major, minor);
  }
  else if (STREQ (type, "freebsd") || STREQ (type, "netbsd") || STREQ (type, "openbsd"))
    return safe_asprintf (g, "%s%d.%d", distro, major, minor);
  else if (STREQ (type, "dos")) {
    if (STREQ (distro, "msdos"))
      return safe_strdup (g, "msdos6.22");
  }
  else if (STREQ (type, "windows")) {
    CLEANUP_FREE char *product_name = NULL;
    CLEANUP_FREE char *product_variant = NULL;
    CLEANUP_FREE char *build_id_str = NULL;
    int build_id;

    product_name = guestfs_inspect_get_product_name (g, root);
    if (!product_name)
      return NULL;
    product_variant = guestfs_inspect_get_product_variant (g, root);
    if (!product_variant)
      return NULL;

    switch (major) {
    case 5:
      switch (minor) {
      case 1:
        return safe_strdup (g, "winxp");
      case 2:
        if (strstr (product_name, "XP"))
          return safe_strdup (g, "winxp");
        else if (strstr (product_name, "R2"))
          return safe_strdup (g, "win2k3r2");
        else
          return safe_strdup (g, "win2k3");
      }
      break;
    case 6:
      switch (minor) {
      case 0:
        if (strstr (product_variant, "Server"))
          return safe_strdup (g, "win2k8");
        else
          return safe_strdup (g, "winvista");
      case 1:
        if (strstr (product_variant, "Server"))
          return safe_strdup (g, "win2k8r2");
        else
          return safe_strdup (g, "win7");
      case 2:
        if (strstr (product_variant, "Server"))
          return safe_strdup (g, "win2k12");
        else
          return safe_strdup (g, "win8");
      case 3:
        if (strstr (product_variant, "Server"))
          return safe_strdup (g, "win2k12r2");
        else
          return safe_strdup (g, "win8.1");
      }
      break;
    case 10:
      switch (minor) {
      case 0:
        if (strstr (product_variant, "Server")) {
          if (strstr (product_name, "2022"))
            return safe_strdup (g, "win2k22");
          else if (strstr (product_name, "2019"))
            return safe_strdup (g, "win2k19");
          else
            return safe_strdup (g, "win2k16");
        }
        else {
          /* For Windows >= 10 Client we can only distinguish between
           * versions by looking at the build ID.  See:
           * https://learn.microsoft.com/en-us/answers/questions/586619/windows-11-build-ver-is-still-10022000194.html
           * https://github.com/cygwin/cygwin/blob/a263fe0b268580273c1adc4b1bad256147990222/winsup/cygwin/wincap.cc#L429
           */
          build_id_str = guestfs_inspect_get_build_id (g, root);
          if (!build_id_str)
            return NULL;

          build_id = guestfs_int_parse_unsigned_int (g, build_id_str);
          if (build_id == -1)
            return NULL;

          if (build_id >= 22000)
            return safe_strdup (g, "win11");
          else
            return safe_strdup (g, "win10");
        }
      }
      break;
    }
  }

  /* No ID could be guessed, return "unknown". */
  return safe_strdup (g, "unknown");
}
