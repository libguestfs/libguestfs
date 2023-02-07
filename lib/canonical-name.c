/* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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
      device[5] != 'm' && /* not /dev/md - RHBZ#1414682 */
      ((len = strcspn (device+5, "d")) > 0 && len <= 2)) {
    /* NB!  These do not need to be translated by
     * device_name_translation.  They will be translated if necessary
     * when the caller uses them in APIs which go through to the
     * daemon.
     */
    ret = safe_asprintf (g, "/dev/sd%s", &device[5+len+1]);
  }
  else if (STRPREFIX (device, "/dev/mapper/") ||
           STRPREFIX (device, "/dev/dm-")) {
    /* Note about error behaviour: The API documentation is inconsistent
     * but existing users expect that this API will not return an
     * error but instead return the original string.
     *
     * In addition LUKS / BitLocker volumes return EINVAL here, which
     * is an expected error.
     *
     * So in the error case the error message goes to debug and we
     * return the original string.
     *
     * https://www.redhat.com/archives/libguestfs/2020-October/msg00061.html
     */
    guestfs_push_error_handler (g, NULL, NULL);
    ret = guestfs_lvm_canonical_lv_name (g, device);
    guestfs_pop_error_handler (g);
    if (ret == NULL)
      ret = safe_strdup (g, device);
  }
  else
    ret = safe_strdup (g, device);

  return ret;                   /* caller frees */
}
