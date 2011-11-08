/* guestfish - the filesystem interactive shell
 * Copyright (C) 2010 Red Hat Inc.
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
#include <stdarg.h>
#include <string.h>
#include <unistd.h>

#include "fish.h"
#include "prepopts.h"

static prep_data *parse_type_string (const char *type_string);

void
list_prepared_drives (void)
{
  size_t i, j;

  printf (_("List of available prepared disk images:\n\n"));

  for (i = 0; i < NR_PREPS; ++i) {
    printf (_("\
guestfish -N %-8s - %s\n\
\n\
%s\n"),
            preps[i].name, preps[i].shortdesc, preps[i].longdesc);

    if (preps[i].nr_params > 0) {
      printf ("\n");
      printf (_("  Optional parameters:\n"));
      printf ("    -N %s", preps[i].name);
      for (j = 0; j < preps[i].nr_params; ++j)
        printf (":<%s>", preps[i].params[j].pname);
      printf ("\n");
      for (j = 0; j < preps[i].nr_params; ++j) {
        printf ("      ");
        printf (_("<%s> %s (default: %s)\n"),
                preps[i].params[j].pname,
                preps[i].params[j].pdesc,
                preps[i].params[j].pdefault);
      }
    }

    printf ("\n");
  }

  printf (_("\
Prepared disk images are written to file \"test1.img\" in the local\n\
directory.  (\"test2.img\" etc if -N option is given multiple times).\n\
For more information see the guestfish(1) manual.\n"));
}

/* Parse the type string (from the command line) and create the output
 * file 'filename'.  This is called before launch.  Return the opaque
 * prep_data which will be passed back to us in prepare_drive below.
 */
prep_data *
create_prepared_file (const char *type_string, const char *filename)
{
  prep_data *data = parse_type_string (type_string);
  if (data->prep->prelaunch)
    data->prep->prelaunch (filename, data);
  return data;
}

static prep_data *
parse_type_string (const char *type_string)
{
  size_t i;

  /* Match on the type part (without parameters). */
  size_t len = strcspn (type_string, ":");
  for (i = 0; i < NR_PREPS; ++i)
    if (STRCASEEQLEN (type_string, preps[i].name, len))
      break;

  if (i == NR_PREPS) {
    fprintf (stderr, _("\
guestfish: -N parameter '%s': no such prepared disk image known.\n\
Use 'guestfish -N help' to list possible values for the -N parameter.\n"),
             type_string);
    exit (EXIT_FAILURE);
  }

  prep_data *data = malloc (sizeof *data);
  if (data == NULL) {
    perror ("malloc");
    exit (EXIT_FAILURE);
  }
  data->prep = &preps[i];
  data->orig_type_string = type_string;

  /* Set up the optional parameters to all-defaults. */
  data->params = malloc (data->prep->nr_params * sizeof (char *));
  if (data->params == NULL) {
    perror ("malloc");
    exit (EXIT_FAILURE);
  }

  for (i = 0; i < data->prep->nr_params; ++i)
    data->params[i] = bad_cast (data->prep->params[i].pdefault);

  /* Parse the optional parameters. */
  const char *p = type_string + len;
  if (*p) p++; /* skip colon char */

  i = 0;
  while (*p) {
    len = strcspn (p, ":");
    data->params[i] = strndup (p, len);
    if (data->params[i] == NULL) {
      perror ("strndup");
      exit (EXIT_FAILURE);
    }

    p += len;
    if (*p) p++; /* skip colon char */
    i++;
  }

  return data;
}

/* Prepare a drive.  The appliance has been launched, and 'device' is
 * the libguestfs device.  'data' is the requested type.  'filename'
 * is just used for error messages.
 */
void
prepare_drive (const char *filename, prep_data *data,
               const char *device)
{
  if (data->prep->postlaunch)
    data->prep->postlaunch (filename, data, device);
}

void
prep_error (prep_data *data, const char *filename, const char *fs, ...)
{
  fprintf (stderr,
           _("guestfish: error creating prepared disk image '%s' on '%s': "),
           data->orig_type_string, filename);

  va_list args;
  va_start (args, fs);
  vfprintf (stderr, fs, args);
  va_end (args);

  fprintf (stderr, "\n");

  exit (EXIT_FAILURE);
}

void
free_prep_data (void *vp)
{
  prep_data *data = vp;
  size_t i;

  for (i = 0; i < data->prep->nr_params; ++i)
    if (data->params[i] != data->prep->params[i].pdefault)
      free (data->params[i]);
  free (data->params);
  free (data);
}
