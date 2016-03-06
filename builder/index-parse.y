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
#include "index-parse.h"

/* The generated code uses frames > 5000 bytes. */
#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wframe-larger-than="
#pragma GCC diagnostic ignored "-Wstack-usage="
#endif

#define YY_EXTRA_TYPE struct parse_context *

extern void yyerror (YYLTYPE * yylloc, yyscan_t scanner, struct parse_context *context, const char *msg);
extern int yylex (YYSTYPE * yylval, YYLTYPE * yylloc, yyscan_t scanner);

extern int do_parse (struct parse_context *context, FILE *in);
extern void scanner_init (yyscan_t *scanner, struct parse_context *context, FILE *in);
extern void scanner_destroy (yyscan_t scanner);

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

%code requires {
#ifndef YY_TYPEDEF_YY_SCANNER_T
#define YY_TYPEDEF_YY_SCANNER_T
typedef void *yyscan_t;
#endif
}

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
%token         UNKNOWN_LINE

%type <section> sections section
%type <field>   fields field
%type <str>     continuations

%pure-parser

%lex-param   { yyscan_t scanner }
%parse-param { yyscan_t scanner }
%parse-param { struct parse_context *context }

%destructor { section_free ($$); } <section>
%destructor { field_free ($$); } <field>

%%

index:
      sections
        { context->parsed_index = $1; }
    | PGP_PROLOGUE sections PGP_EPILOGUE
        { context->parsed_index = $2; }

sections:
      emptylines section emptylines
        { $$ = $2; }
    | emptylines section EMPTY_LINE emptylines sections
        { $$ = $2; $$->next = $5; }
    | emptylines
        { $$ = NULL; }

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

emptylines:
      /* empty */
        {}
    | EMPTY_LINE emptylines
        {}

%%

void
yyerror (YYLTYPE * yylloc, yyscan_t scanner, struct parse_context *context, const char *msg)
{
  int has_suffix = context->error_suffix != NULL && context->error_suffix[0] != 0;

  fprintf (stderr, "%s%s%s%ssyntax error at line %d: %s%s%s\n",
           context->progname ? context->progname : "",
           context->progname ? ": " : "",
           context->input_file ? context->input_file : "",
           context->input_file ? ": " : "",
           yylloc->first_line, msg,
           has_suffix ? " " : "",
           has_suffix ? context->error_suffix : "");
}

int
do_parse (struct parse_context *context, FILE *in)
{
  yyscan_t scanner;
  int res;

  scanner_init (&scanner, context, in);
  res = yyparse (scanner, context);
  scanner_destroy (scanner);

  return res;
}
