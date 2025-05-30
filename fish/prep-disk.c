/* guestfish - guest filesystem shell
 * Copyright (C) 2010-2025 Red Hat Inc.
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
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <libintl.h>

#include "fish.h"
#include "prepopts.h"

void
prep_prelaunch_disk (const char *filename, prep_data *data)
{
  if (alloc_disk (filename, data->params[0], 0, 1) == -1)
    prep_error (data, filename, _("failed to allocate disk"));
}

void
prep_postlaunch_disk (const char *filename, prep_data *data, const char *device)
{
  /* nothing */
}
