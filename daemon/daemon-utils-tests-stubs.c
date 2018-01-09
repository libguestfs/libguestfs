/* guestfsd
 * Copyright (C) 2017 Red Hat Inc.
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

#include "daemon.h"

/* This stubs out some functions that we want to link to the unit
 * tests, but don't want to actually pull in plus dependencies.
 */

char * __attribute__((noreturn))
device_name_translation (const char *device)
{
  abort ();
}

void __attribute__((noreturn))
reply_with_error_errno (int err, const char *fs, ...)
{
  abort ();
}

void __attribute__((noreturn))
reply_with_perror_errno (int err, const char *fs, ...)
{
  abort ();
}
