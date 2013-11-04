/* libguestfs virt-builder tool
 * Copyright (C) 2013 Red Hat Inc.
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

#include "index-struct.h"

struct section *parsed_index = NULL;
int seen_comments = 0;

static void free_section (struct section *section);
static void free_field (struct field *field);

void
free_index (void)
{
  free_section (parsed_index);
}

static void
free_section (struct section *section)
{
  if (section) {
    free_section (section->next);
    free (section->name);
    free_field (section->fields);
    free (section);
  }
}

static void
free_field (struct field *field)
{
  if (field) {
    free_field (field->next);
    free (field->key);
    free (field->value);
    free (field);
  }
}
