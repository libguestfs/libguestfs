/* libguestfs
 * Copyright (C) 2014 Red Hat Inc.
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

#include "c-ctype.h"

#include "guestfs.h"
#include "guestfs-internal.h"

/**
 * Check whether a string supposed to contain a GUID actually contains
 * it.  It can recognize strings either as
 * C<{21EC2020-3AEA-1069-A2DD-08002B30309D}> or
 * C<21EC2020-3AEA-1069-A2DD-08002B30309D>.
 */
int
guestfs_int_validate_guid (const char *str)
{
  size_t i, len = strlen (str);

  switch (len) {
  case 36:
    break;
  case 38:
    if (str[0] == '{' && str[len -1] == '}') {
      ++str;
      len -= 2;
      break;
    }
    return 0;
  default:
    return 0;
  }

  for (i = 0; i < len; ++i) {
    switch (i) {
    case 8:
    case 13:
    case 18:
    case 23:
      if (str[i] != '-')
        return 0;
      break;
    default:
      if (!c_isalnum (str[i]))
        return 0;
      break;
    }
  }

  return 1;
}
