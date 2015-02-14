/* libguestfs
 * Copyright (C) 2009-2014 Red Hat Inc.
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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

char *
guestfs_impl_canonical_device_name (guestfs_h *g, const char *device)
{
  char *ret;
  size_t len;

  /* /dev/hd etc. */
  if (STRPREFIX (device, "/dev/") &&
      strchr (device+5, '/') == NULL && /* not an LV name */
      ((len = strcspn (device+5, "d")) > 0 && len <= 2)) {
    ret = safe_asprintf (g, "/dev/sd%s", &device[5+len+1]);
  }
  else if (STRPREFIX (device, "/dev/mapper/") ||
           STRPREFIX (device, "/dev/dm-")) {
    /* XXX hide errors */
    ret = guestfs_lvm_canonical_lv_name (g, device);
    if (ret == NULL)
      ret = safe_strdup (g, device);
  }
  else
    ret = safe_strdup (g, device);

  return ret;                   /* caller frees */
}
