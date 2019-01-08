/* libguestfs - implement --short-options and --long-options
 * Copyright (C) 2010-2019 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/**
 * This file contains common code used to implement I<--short-options>
 * and I<--long-options> in C virt tools.  (The equivalent for
 * OCaml virt tools is implemented by F<common/mltools/getopt.ml>).
 *
 * These "hidden" options are used to implement bash tab completion.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>

#include "guestfs-internal-all.h"
#include "display-options.h"

/**
 * Implements the internal C<tool I<--short-options>> flag, which just
 * lists out the short options available.  Used by bash completion.
 */
void
display_short_options (const char *format)
{
  while (*format) {
    if (*format != ':')
      printf ("-%c\n", *format);
    ++format;
  }
  exit (EXIT_SUCCESS);
}

/**
 * Implements the internal C<tool I<--long-options>> flag, which just
 * lists out the long options available.  Used by bash completion.
 */
void
display_long_options (const struct option *long_options)
{
  while (long_options->name) {
    if (STRNEQ (long_options->name, "long-options") &&
        STRNEQ (long_options->name, "short-options"))
      printf ("--%s\n", long_options->name);
    long_options++;
  }
  exit (EXIT_SUCCESS);
}
