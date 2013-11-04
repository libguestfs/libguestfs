/* libguestfs virt-builder tool -*- fundamental -*-
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

%{
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "index-struct.h"

extern void yyerror (const char *);
extern int yylex (void);

/* Join two strings with \n */
static char *
concat_newline (const char *str1, const char *str2)
{
  size_t len1, len2, len;
  char *ret;

  if (str2 == NULL)
    return strdup (str1);

  len1 = strlen (str1);
  len2 = strlen (str2);
  len = len1 + 1 /* \n */ + len2 + 1 /* \0 */;
  ret = malloc (len);
  memcpy (ret, str1, len1);
  ret[len1] = '\n';
  memcpy (ret + len1 + 1, str2, len2);
  ret[len-1] = '\0';

  return ret;
}

%}

%locations

%union {
  struct section *section;
  struct field *field;
  char *str;
}

%token <str>   SECTION_HEADER
%token <field> FIELD
%token <str>   VALUE_CONT
%token         EMPTY_LINE
%token         PGP_PROLOGUE
%token         PGP_EPILOGUE

%type <section> sections section
%type <field>   fields field
%type <str>     continuations

%%

index:
      sections
        { parsed_index = $1; }
    | PGP_PROLOGUE sections PGP_EPILOGUE
        { parsed_index = $2; }

sections:
      section
        { $$ = $1; }
    | section EMPTY_LINE sections
        { $$ = $1; $$->next = $3; }

section:
      SECTION_HEADER fields
        { $$ = malloc (sizeof (struct section));
          $$->next = NULL;
          $$->name = $1;
          $$->fields = $2; }

fields:
      /* empty */
        { $$ = NULL; }
    | field fields
        { $$ = $1; $$->next = $2; }

field: FIELD continuations
        { $$ = $1;
          char *old_value = $$->value;
          $$->value = concat_newline (old_value, $2);
          free (old_value);
          free ($2); }

continuations:
      /* empty */
        { $$ = NULL; }
    | VALUE_CONT continuations
        { $$ = concat_newline ($1, $2);
          free ($1);
          free ($2); }

%%

void
yyerror (const char *msg)
{
  fprintf (stderr, "syntax error at line %d: %s\n",
           yylloc.first_line, msg);
}
