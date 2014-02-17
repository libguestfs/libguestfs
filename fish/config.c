/* libguestfs - guestfish and guestmount shared option parsing
 * Copyright (C) 2011 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <libintl.h>

#ifdef HAVE_LIBCONFIG
#include <libconfig.h>
#endif

#include "guestfs.h"

#include "options.h"

#ifdef HAVE_LIBCONFIG

static const char *home_filename = /* $HOME/ */ ".libguestfs-tools.rc";
static const char *etc_filename = "/etc/libguestfs-tools.conf";

/* Note that parse_config is called very early, before command line
 * parsing, before the verbose flag has been set, even before the
 * global handle 'g' is opened.
 */

static void
read_config_from_file (const char *filename)
{
  FILE *fp;

  fp = fopen (filename, "r");
  if (fp != NULL) {
    config_t conf;

    config_init (&conf);

    /*
    if (verbose)
      fprintf (stderr, "%s: reading configuration from %s\n",
               program_name, filename);
    */

    if (config_read (&conf, fp) == CONFIG_FALSE) {
      fprintf (stderr,
               _("%s: %s: line %d: error parsing configuration file: %s\n"),
               program_name, filename, config_error_line (&conf),
               config_error_text (&conf));
      exit (EXIT_FAILURE);
    }

    if (fclose (fp) == -1) {
      perror (filename);
      exit (EXIT_FAILURE);
    }

    config_lookup_bool (&conf, "read_only", &read_only);

    config_destroy (&conf);
  }
}

void
parse_config (void)
{
  const char *home;

  /* Try the global configuration first. */
  read_config_from_file (etc_filename);

  /* Read the configuration from $HOME, to override system settings. */
  home = getenv ("HOME");
  if (home != NULL) {
    CLEANUP_FREE char *path = NULL;

    if (asprintf (&path, "%s/%s", home, home_filename) == -1) {
      perror ("asprintf");
      exit (EXIT_FAILURE);
    }

    read_config_from_file (path);
  }
}

#else /* !HAVE_LIBCONFIG */

void
parse_config (void)
{
  /*
  if (verbose)
    fprintf (stderr,
             _("%s: compiled without libconfig, guestfish configuration file ignored\n"),
             program_name);
  */
}

#endif /* !HAVE_LIBCONFIG */
