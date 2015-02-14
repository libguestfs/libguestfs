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

#define GLOBAL_CONFIG_FILENAME "libguestfs-tools.conf"
static const char *home_filename = /* $HOME/ */ ".libguestfs-tools.rc";
static const char *etc_filename = "/etc/" GLOBAL_CONFIG_FILENAME;

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
               guestfs_int_program_name, filename);
    */

    if (config_read (&conf, fp) == CONFIG_FALSE) {
      fprintf (stderr,
               _("%s: %s: line %d: error parsing configuration file: %s\n"),
               guestfs_int_program_name, filename, config_error_line (&conf),
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

  {
    /* Then read the configuration from XDG system paths. */
    const char *xdg_env, *var;
    CLEANUP_FREE_STRING_LIST char **xdg_config_dirs = NULL;
    size_t xdg_config_dirs_count;

    xdg_env = getenv ("XDG_CONFIG_DIRS");
    var = xdg_env != NULL && xdg_env[0] != 0 ? xdg_env : "/etc/xdg";
    xdg_config_dirs = guestfs_int_split_string (':', var);
    xdg_config_dirs_count = guestfs_int_count_strings (xdg_config_dirs);
    for (size_t i = xdg_config_dirs_count; i > 0; --i) {
      CLEANUP_FREE char *path = NULL;
      const char *dir = xdg_config_dirs[i - 1];

      if (asprintf (&path, "%s/libguestfs/" GLOBAL_CONFIG_FILENAME, dir) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }

      read_config_from_file (path);
    }
  }

  /* Read the configuration from $HOME, to override system settings. */
  home = getenv ("HOME");
  if (home != NULL) {
    {
      /* Old-style configuration file first. */
      CLEANUP_FREE char *path = NULL;

      if (asprintf (&path, "%s/%s", home, home_filename) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }

      read_config_from_file (path);
    }

    {
      /* Then, XDG_CONFIG_HOME path. */
      CLEANUP_FREE char *path = NULL;
      CLEANUP_FREE char *home_copy = strdup (home);
      const char *xdg_env;

      if (home_copy == NULL) {
        perror ("strdup");
        exit (EXIT_FAILURE);
      }

      xdg_env = getenv ("XDG_CONFIG_HOME");
      if (xdg_env == NULL) {
        if (asprintf (&path, "%s/.config/libguestfs/" GLOBAL_CONFIG_FILENAME,
                      home_copy) == -1) {
          perror ("asprintf");
          exit (EXIT_FAILURE);
        }
      } else {
        if (asprintf (&path, "%s/libguestfs/" GLOBAL_CONFIG_FILENAME,
                      xdg_env) == -1) {
          perror ("asprintf");
          exit (EXIT_FAILURE);
        }
      }

      read_config_from_file (path);
    }
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
             guestfs_int_program_name);
  */
}

#endif /* !HAVE_LIBCONFIG */
