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
  char *subkey;
  char *value;
};

/* A struct holding the data needed during the parsing. */
struct parse_context {
  struct section *parsed_index;        /* The result of the parsing. */
  /* yyparse sets this if any comments were seen.  Required for checking
   * compatibility with virt-builder 1.24.
   */
  int seen_comments;
  const char *input_file;
  const char *progname;
  const char *error_suffix;
};

/* Initialize the content of a parse_context. */
extern void parse_context_init (struct parse_context *state);

/* Free the content of a parse_context.  The actual pointer is not freed. */
extern void parse_context_free (struct parse_context *state);

/* Free the content of a section, recursively freeing also its fields.
 * The actual pointer is not freed.
 */
extern void section_free (struct section *section);

/* Free the content of a field, recursively freeing also its next field.
 * The actual pointer is not freed.
 */
extern void field_free (struct field *field);

#endif /* INDEX_STRUCT_H */
