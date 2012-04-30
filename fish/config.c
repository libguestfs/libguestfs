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
 * parsing and before the verbose flag has been set.
 */

void
parse_config (void)
{
  const char *home;
  size_t len;
  char *path;
  FILE *fp;
  config_t conf;

  config_init (&conf);

  /* Try $HOME first. */
  home = getenv ("HOME");
  if (home != NULL) {
    len = strlen (home) + 1 + strlen (home_filename) + 1;
    path = malloc (len);
    if (path == NULL) {
      perror ("malloc");
      exit (EXIT_FAILURE);
    }
    snprintf (path, len, "%s/%s", home, home_filename);

    fp = fopen (path, "r");
    if (fp != NULL) {
      /*
      if (verbose)
        fprintf (stderr, "%s: reading configuration from %s\n",
                 program_name, path);
      */

      if (config_read (&conf, fp) == CONFIG_FALSE) {
        fprintf (stderr,
                 _("%s: %s: line %d: error parsing configuration file: %s\n"),
                 program_name, path, config_error_line (&conf),
                 config_error_text (&conf));
        exit (EXIT_FAILURE);
      }

      if (fclose (fp) == -1) {
        perror (path);
        exit (EXIT_FAILURE);
      }

      /* Notes:
       *
       * (1) It's not obvious from the documentation, that config_read
       * completely resets the 'conf' structure.  This means we cannot
       * call config_read twice on the two possible configuration
       * files, but instead have to copy out settings into our
       * variables between calls.
       *
       * (2) If the next call fails then 'read_only' variable is not
       * updated.  Failure could happen just because the setting is
       * missing from the configuration file, so we ignore it here.
       */
      config_lookup_bool (&conf, "read_only", &read_only);
    }

    free (path);
  }

  fp = fopen (etc_filename, "r");
  if (fp != NULL) {
    /*
    if (verbose)
      fprintf (stderr, "%s: reading configuration from %s\n",
               program_name, etc_filename);
    */

    if (config_read (&conf, fp) == CONFIG_FALSE) {
      fprintf (stderr,
               _("%s: %s: line %d: error parsing configuration file: %s\n"),
               program_name, etc_filename, config_error_line (&conf),
               config_error_text (&conf));
      exit (EXIT_FAILURE);
    }

    if (fclose (fp) == -1) {
      perror (etc_filename);
      exit (EXIT_FAILURE);
    }

    config_lookup_bool (&conf, "read_only", &read_only);
  }

  config_destroy (&conf);
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
