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

#include "index-parse.h"
#include "index-struct.h"

#define YY_USER_ACTION yylloc.first_line = yylloc.last_line = yylineno;

extern void yyerror (const char *);

%}

%option noyywrap
%option yylineno

%%

 /* Apart from the PGP prologue/epilogue which is a hack, the
  * scanning strategy is to deal with the file strictly line by
  * line, and pass those lines up to the parser which deals with
  * whether they appear in the right order to be meaningful.
  * Note that flex does longest-match.
  */

  /* Ignore comments - '#' MUST appear at the start of a line. */
^"#".*\n                { seen_comments++; }

  /* An empty line is significant. */
^\n                                     { return EMPTY_LINE; }

  /* [...] marks beginning of a section. */
^"["[-A-Za-z0-9.]+"]"\n {
                      yylval.str = strndup (yytext+1, yyleng-3);
                      return SECTION_HEADER;
                    }

  /* field=value or field[subfield]=value */
^[A-Za-z0-9_.]+("["[A-Za-z0-9_,.]+"]")?"=".*\n {
                      size_t i = strcspn (yytext, "=");
                      yylval.field = malloc (sizeof (struct field));
                      yylval.field->next = NULL;
                      yylval.field->key = strndup (yytext, i);
                      /* Note we chop the final \n off here. */
                      yylval.field->value = strndup (yytext+i+1, yyleng-(i+2));
                      return FIELD;
                    }

  /* Continuation line for multi-line values. */
^[[:blank:]].*\n        {
                      yylval.str = strndup (yytext+1, yyleng-2);
                      return VALUE_CONT;
                    }

 /* Hack to eat the PGP prologue. */
^"-----BEGIN PGP SIGNED MESSAGE-----\n"  {
  int c, prevnl = 0;

  /* Eat everything to the first blank line. */
  while ((c = input ()) != EOF) {
    if (c == '\n' && prevnl)
      break;
    prevnl = c == '\n';
  }

  return PGP_PROLOGUE;
}

 /* Hack to eat the PGP epilogue. */
^"-----BEGIN PGP SIGNATURE-----\n"  {
  /* Eat everything to the end of the file. */
  while (input () != EOF)
    ;

  return PGP_EPILOGUE;
}

 /* anything else is an error */
. {
  yyerror ("unexpected character in input");
  exit (EXIT_FAILURE);
}
