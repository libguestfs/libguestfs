/* libguestfs
 * Copyright (C) 2016 Red Hat Inc.
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

/**
 * This file provides simple version number management.
 */

void
guestfs_int_version_from_libvirt (struct version *v, int vernum)
{
  v->v_major = vernum / 1000000UL;
  v->v_minor = vernum / 1000UL % 1000UL;
  v->v_micro = vernum % 1000UL;
}

void
guestfs_int_version_from_values (struct version *v, int maj, int min, int mic)
{
  v->v_major = maj;
  v->v_minor = min;
  v->v_micro = mic;
}

bool
guestfs_int_version_ge (const struct version *v, int maj, int min, int mic)
{
  return (v->v_major > maj) ||
         ((v->v_major == maj) &&
          ((v->v_minor > min) ||
           ((v->v_minor == min) &&
            (v->v_micro >= mic))));
}
