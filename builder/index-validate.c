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
#include <error.h>
#include <errno.h>
#include <locale.h>
#include <libintl.h>

#include <guestfs.h>

#include "getprogname.h"
#include "guestfs-internal-frontend.h"

#include "index-struct.h"
#include "index-parse.h"

extern int do_parse (struct parse_context *context, FILE *in);

static void
usage (int exit_status)
{
  printf ("%s index\n", getprogname ());
  exit (exit_status);
}

int
main (int argc, char *argv[])
{
  enum { HELP_OPTION = CHAR_MAX + 1 };
  static const char options[] = "V";
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
  struct parse_context context;
  FILE *in;
  int ret;

  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  parse_context_init (&context);

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:                     /* options which are long only */
      if (STREQ (long_options[option_index].name, "compat-1.24.0"))
        compat_1_24_0 = compat_1_24_1 = 1;
      else if (STREQ (long_options[option_index].name, "compat-1.24.1"))
        compat_1_24_1 = 1;
      else
        error (EXIT_FAILURE, 0,
               _("unknown long option: %s (%d)"),
               long_options[option_index].name, option_index);
      break;

    case 'V':
      printf ("%s %s%s\n",
              getprogname (),
              PACKAGE_VERSION, PACKAGE_VERSION_EXTRA);
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

  in = fopen (input, "r");
  if (in == NULL)
    error (EXIT_FAILURE, errno, "fopen: %s", input);

  ret = do_parse (&context, in);

  if (fclose (in) == EOF) {
    fprintf (stderr, _("%s: %s: error closing input file: %m (ignored)\n"),
             getprogname (), input);
  }

  if (ret != 0) {
    parse_context_free (&context);
    error (EXIT_FAILURE, 0,
           _("'%s' could not be validated, see errors above"), input);
  }

  if (compat_1_24_1 && context.seen_comments) {
    parse_context_free (&context);
    error (EXIT_FAILURE, 0,
           _("%s contains comments which will not work with virt-builder 1.24.1"),
           input);
  }

  /* Iterate over the parsed sections, semantically validating it. */
  for (sections = context.parsed_index; sections != NULL; sections = sections->next) {
    int seen_sig = 0;
    struct field *fields;

    if (compat_1_24_0) {
      if (strchr (sections->name, '_')) {
        parse_context_free (&context);
        error (EXIT_FAILURE, 0,
               _("%s: section [%s] has invalid characters which will not work with virt-builder 1.24.0"),
               input, sections->name);
      }
    }

    for (fields = sections->fields; fields != NULL; fields = fields->next) {
      if (compat_1_24_0) {
        if (strchr (fields->key, '[') ||
            strchr (fields->key, ']')) {
          parse_context_free (&context);
          error (EXIT_FAILURE, 0,
                 _("%s: section [%s], field '%s' has invalid characters which will not work with virt-builder 1.24.0"),
                 input, sections->name, fields->key);
        }
      }
      if (compat_1_24_1) {
        if (strchr (fields->key, '.') ||
            strchr (fields->key, ',')) {
          parse_context_free (&context);
          error (EXIT_FAILURE, 0,
                 _("%s: section [%s], field '%s' has invalid characters which will not work with virt-builder 1.24.1"),
                 input, sections->name, fields->key);
        }
      }
      if (STREQ (fields->key, "sig"))
        seen_sig = 1;
    }

    if (compat_1_24_0 && !seen_sig) {
      parse_context_free (&context);
      error (EXIT_FAILURE, 0,
             _("%s: section [%s] is missing a 'sig' field which will not work with virt-builder 1.24.0"),
             input, sections->name);
    }
  }

  /* Free the parsed data. */
  parse_context_free (&context);

  printf ("%s validated OK\n", input);

  exit (EXIT_SUCCESS);
}
