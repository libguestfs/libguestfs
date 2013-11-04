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
#include <string.h>
#include <limits.h>
#include <getopt.h>
#include <errno.h>
#include <libintl.h>

#include <guestfs.h>

#include "guestfs-internal-frontend.h"

#include "index-struct.h"
#include "index-parse.h"

extern FILE *yyin;

static void
usage (int exit_status)
{
  printf ("%s index\n", program_name);
  exit (exit_status);
}

int
main (int argc, char *argv[])
{
  enum { HELP_OPTION = CHAR_MAX + 1 };
  static const char *options = "V";
  static const struct option long_options[] = {
    { "help", 0, 0, HELP_OPTION },
    { "compat-1.24.0", 0, 0, 0 },
    { "compat-1.24.1", 0, 0, 0 },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  int c;
  int option_index;
  int compat_1_24_0 = 0;
  int compat_1_24_1 = 0;
  const char *input;
  struct section *sections;

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:                     /* options which are long only */
      if (STREQ (long_options[option_index].name, "compat-1.24.0"))
        compat_1_24_0 = compat_1_24_1 = 1;
      else if (STREQ (long_options[option_index].name, "compat-1.24.1"))
        compat_1_24_1 = 1;
      else {
        fprintf (stderr, _("%s: unknown long option: %s (%d)\n"),
                 program_name, long_options[option_index].name, option_index);
        exit (EXIT_FAILURE);
      }
      break;

    case 'V':
      printf ("%s %s\n", PACKAGE_NAME, PACKAGE_VERSION);
      exit (EXIT_SUCCESS);

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  if (optind != argc-1)
    usage (EXIT_FAILURE);

  input = argv[optind++];

  yyin = fopen (input, "r");
  if (yyin == NULL) {
    perror (input);
    exit (EXIT_FAILURE);
  }

  if (yyparse () != 0) {
    fprintf (stderr, _("%s: '%s' could not be validated, see errors above\n"),
             program_name, input);
    exit (EXIT_FAILURE);
  }

  if (fclose (yyin) == EOF) {
    fprintf (stderr, _("%s: %s: error reading input file: %m\n"),
             program_name, input);
    exit (EXIT_FAILURE);
  }

  if (compat_1_24_1 && seen_comments) {
    fprintf (stderr, _("%s: %s contains comments which will not work with virt-builder 1.24.1\n"),
             program_name, input);
    exit (EXIT_FAILURE);
  }

  /* Iterate over the parsed sections, semantically validating it. */
  for (sections = parsed_index; sections != NULL; sections = sections->next) {
    int seen_sig = 0;
    struct field *fields;

    for (fields = sections->fields; fields != NULL; fields = fields->next) {
      if (compat_1_24_0) {
        if (strchr (fields->key, '[') ||
            strchr (fields->key, ']')) {
          fprintf (stderr, _("%s: %s: section [%s], field '%s' has invalid characters which will not work with virt-builder 1.24.0\n"),
                   program_name, input, sections->name, fields->key);
          exit (EXIT_FAILURE);
        }
      }
      if (compat_1_24_1) {
        if (strchr (fields->key, '.') ||
            strchr (fields->key, ',')) {
          fprintf (stderr, _("%s: %s: section [%s], field '%s' has invalid characters which will not work with virt-builder 1.24.1\n"),
                   program_name, input, sections->name, fields->key);
          exit (EXIT_FAILURE);
        }
      }
      if (STREQ (fields->key, "sig"))
        seen_sig = 1;
    }

    if (compat_1_24_0 && !seen_sig) {
      fprintf (stderr, _("%s: %s: section [%s] is missing a 'sig' field which will not work with virt-builder 1.24.0\n"),
               program_name, input, sections->name);
      exit (EXIT_FAILURE);
    }
  }

  /* Free the parsed data. */
  free_index ();

  printf ("%s validated OK\n", input);

  exit (EXIT_SUCCESS);
}
