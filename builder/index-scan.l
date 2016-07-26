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

%top{
#include <config.h>
}

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Silence gcc warnings from the generated code. */
#if defined(__GNUC__)
#pragma GCC diagnostic push
/* flex creates macros that it doesn't use */
#pragma GCC diagnostic ignored "-Wunused-macros"
/* on aarch64, flex doesn't know that char is unsigned */
#pragma GCC diagnostic ignored "-Wsign-compare"
/* on debian-mipsel, flex doesn't create prototypes for all functions */
#pragma GCC diagnostic ignored "-Wmissing-prototypes"
#endif

#include "index-struct.h"
#include "index-parse.h"

#define YY_EXTRA_TYPE struct parse_context *
#define YY_USER_ACTION yylloc->first_line = yylloc->last_line = yylineno;

extern void scanner_init (yyscan_t *scanner, struct parse_context *context, FILE *in);
extern void scanner_destroy (yyscan_t scanner);

%}

%option nounput
%option noyywrap
%option yylineno
%option reentrant
%option bison-bridge
%option bison-locations

%%

 /* Apart from the PGP prologue/epilogue which is a hack, the
  * scanning strategy is to deal with the file strictly line by
  * line, and pass those lines up to the parser which deals with
  * whether they appear in the right order to be meaningful.
  * Note that flex does longest-match.
  */

  /* Ignore comments - '#' MUST appear at the start of a line. */
^"#".*\n                { yyextra->seen_comments++; }

  /* An empty line is significant. */
^\n                                     { return EMPTY_LINE; }

  /* [...] marks beginning of a section. */
^"["[-A-Za-z0-9._]+"]"\n {
                      yylval->str = strndup (yytext+1, yyleng-3);
                      return SECTION_HEADER;
                    }

  /* field=value or field[subfield]=value */
^[A-Za-z0-9_.]+("["[A-Za-z0-9_,.]+"]")?"=".*\n {
                      size_t i = strcspn (yytext, "=[");
                      yylval->field = malloc (sizeof (struct field));
                      yylval->field->next = NULL;
                      yylval->field->key = strndup (yytext, i);
                      if (yytext[i] == '[') {
                        const size_t j = strcspn (yytext+i+1, "]");
                        yylval->field->subkey = strndup (yytext+i+1, j);
                        i += 1+j+1;
                      } else {
                        yylval->field->subkey = NULL;
                      }
                      /* Note we chop the final \n off here. */
                      yylval->field->value = strndup (yytext+i+1, yyleng-(i+2));
                      return FIELD;
                    }

  /* Continuation line for multi-line values. */
^[[:blank:]].*\n        {
                      yylval->str = strndup (yytext+1, yyleng-2);
                      return VALUE_CONT;
                    }

 /* Hack to eat the PGP prologue. */
^"-----BEGIN PGP SIGNED MESSAGE-----\n"  {
  int c, prevnl = 0;

  /* Eat everything to the first blank line. */
  while ((c = input (yyscanner)) != EOF) {
    if (c == '\n' && prevnl)
      break;
    prevnl = c == '\n';
  }

  return PGP_PROLOGUE;
}

 /* Hack to eat the PGP epilogue. */
^"-----BEGIN PGP SIGNATURE-----\n"  {
  /* Eat everything to the end of the file. */
  while (input (yyscanner) != EOF)
    ;

  return PGP_EPILOGUE;
}

 /* anything else is an error */
. {
  return UNKNOWN_LINE;
}

%%

void
scanner_init (yyscan_t *scanner, struct parse_context *context, FILE *in)
{
  yylex_init (scanner);
  yyset_extra (context, *scanner);
  yyset_in (in, *scanner);
}

void
scanner_destroy (yyscan_t scanner)
{
  yylex_destroy (scanner);
}
