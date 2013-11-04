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

/* The data structures produced when parsing the index file. */

#ifndef INDEX_STRUCT_H
#define INDEX_STRUCT_H

/* A section or list of sections. */
struct section {
  struct section *next;
  char *name;
  struct field *fields;
};

/* A field or list of fields. */
struct field {
  struct field *next;
  char *key;
  char *value;
};

/* The parser (yyparse) stores the result here. */
extern struct section *parsed_index;

/* yyparse sets this if any comments were seen.  Required for checking
 * compatibility with virt-builder 1.24.
 */
extern int seen_comments;

extern void free_index (void);

#endif /* INDEX_STRUCT_H */
