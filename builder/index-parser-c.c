/* virt-builder
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

/* This file handles the interface between the C/lex/yacc index file
 * parser, and the OCaml world.  See index_parser.ml for the OCaml
 * type definition.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#ifdef HAVE_CAML_UNIXSUPPORT_H
#include <caml/unixsupport.h>
#else
#define Nothing ((value) 0)
extern void unix_error (int errcode, char * cmdname, value arg) Noreturn;
#endif

#include "index-struct.h"
#include "index-parse.h"

extern FILE *yyin;

value
virt_builder_parse_index (value filenamev)
{
  CAMLparam1 (filenamev);
  CAMLlocal4 (rv, v, sv, fv);
  struct section *sections;
  size_t i, nr_sections;

  yyin = fopen (String_val (filenamev), "r");
  if (yyin == NULL)
    unix_error (errno, (char *) "fopen", filenamev);

  if (yyparse () != 0) {
    fclose (yyin);
    caml_invalid_argument ("parse error");
  }

  if (fclose (yyin) == EOF)
    unix_error (errno, (char *) "fclose", filenamev);

  /* Convert the parsed data to OCaml structures. */
  nr_sections = 0;
  for (sections = parsed_index; sections != NULL; sections = sections->next)
    nr_sections++;
  rv = caml_alloc (nr_sections, 0);

  for (i = 0, sections = parsed_index; sections != NULL;
       i++, sections = sections->next) {
    struct field *fields;
    size_t j, nr_fields;

    nr_fields = 0;
    for (fields = sections->fields; fields != NULL; fields = fields->next)
      nr_fields++;
    fv = caml_alloc (nr_fields, 0);

    for (j = 0, fields = sections->fields; fields != NULL;
         j++, fields = fields->next) {
      v = caml_alloc_tuple (2);
      sv = caml_copy_string (fields->key);
      Store_field (v, 0, sv);   /* (key, value) */
      sv = caml_copy_string (fields->value);
      Store_field (v, 1, sv);
      Store_field (fv, j, v);   /* assign to return array of fields */
    }

    v = caml_alloc_tuple (2);
    sv = caml_copy_string (sections->name);
    Store_field (v, 0, sv);     /* (name, fields) */
    Store_field (v, 1, fv);
    Store_field (rv, i, v);     /* assign to return array of sections */
  }

  /* Free parsed global data. */
  free_index ();

  CAMLreturn (rv);
}
