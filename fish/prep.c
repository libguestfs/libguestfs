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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>

#include "fish.h"

static prep_data *parse_type_string (const char *type_string);
static void prep_error (prep_data *data, const char *filename, const char *fs, ...) __attribute__((noreturn, format (printf,3,4)));

struct prep {
  const char *name;             /* eg. "fs" */

  size_t nr_params;             /* optional parameters */
  struct param *params;

  const char *shortdesc;        /* short description */
  const char *longdesc;         /* long description */

                                /* functions to implement it */
  void (*prelaunch) (const char *filename, prep_data *);
  void (*postlaunch) (const char *filename, prep_data *, const char *device);
};

struct param {
  const char *pname;            /* parameter name */
  const char *pdefault;         /* parameter default */
  const char *pdesc;            /* parameter description */
};

static void prelaunch_disk (const char *filename, prep_data *data);
static struct param disk_params[] = {
  { "size", "100M", "the size of the disk image" },
};

static void prelaunch_part (const char *filename, prep_data *data);
static void postlaunch_part (const char *filename, prep_data *data, const char *device);
static struct param part_params[] = {
  { "size", "100M", "the size of the disk image" },
  { "partition", "mbr", "partition table type" },
};

static void prelaunch_fs (const char *filename, prep_data *data);
static void postlaunch_fs (const char *filename, prep_data *data, const char *device);
static struct param fs_params[] = {
  { "filesystem", "ext2", "the type of filesystem to use" },
  { "size", "100M", "the size of the disk image" },
  { "partition", "mbr", "partition table type" },
};

static const struct prep preps[] = {
  { "disk",
    1, disk_params,
    "create a blank disk",
    "\
  Create a blank disk, size 100MB (by default).\n\
\n\
  The default size can be changed by supplying an optional parameter.",
    prelaunch_disk, NULL
  },
  { "part",
    2, part_params,
    "create a partitioned disk",
    "\
  Create a disk with a single partition.  By default the size of the disk\n\
  is 100MB (the available space in the partition will be a tiny bit smaller)\n\
  and the partition table will be MBR (old DOS-style).\n\
\n\
  These defaults can be changed by supplying optional parameters.",
    prelaunch_part, postlaunch_part
  },
  { "fs",
    3, fs_params,
    "create a filesystem",
    "\
  Create a disk with a single partition, with the partition containing\n\
  an empty filesystem.  This defaults to creating a 100MB disk (the available\n\
  space in the filesystem will be a tiny bit smaller) with an MBR (old\n\
  DOS-style) partition table and an ext2 filesystem.\n\
\n\
  These defaults can be changed by supplying optional parameters.",
    prelaunch_fs, postlaunch_fs
  },
};

#define nr_preps (sizeof preps / sizeof preps[0])

void
list_prepared_drives (void)
{
  size_t i, j;

  printf (_("List of available prepared disk images:\n\n"));

  for (i = 0; i < nr_preps; ++i) {
    printf (_("\
guestfish -N %-16s %s\n\
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

struct prep_data {
  const struct prep *prep;
  const char *orig_type_string;
  const char **params;
};

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
  for (i = 0; i < nr_preps; ++i)
    if (STRCASEEQLEN (type_string, preps[i].name, len))
      break;

  if (i == nr_preps) {
    fprintf (stderr, _("\
guestfish: -N parameter '%s': no such prepared disk image known.\n\
Use 'guestfish -N list' to list possible values for the -N parameter.\n"),
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
    data->params[i] = data->prep->params[i].pdefault;

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

static void
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

static void
prelaunch_disk (const char *filename, prep_data *data)
{
  if (alloc_disk (filename, data->params[0], 0, 1) == -1)
    prep_error (data, filename, _("failed to allocate disk"));
}

static void
prelaunch_part (const char *filename, prep_data *data)
{
  if (alloc_disk (filename, data->params[0], 0, 1) == -1)
    prep_error (data, filename, _("failed to allocate disk"));
}

static void
postlaunch_part (const char *filename, prep_data *data, const char *device)
{
  if (guestfs_part_disk (g, device, data->params[1]) == -1)
    prep_error (data, filename, _("failed to partition disk: %s"),
                guestfs_last_error (g));
}

static void
prelaunch_fs (const char *filename, prep_data *data)
{
  if (alloc_disk (filename, data->params[1], 0, 1) == -1)
    prep_error (data, filename, _("failed to allocate disk"));
}

static void
postlaunch_fs (const char *filename, prep_data *data, const char *device)
{
  if (guestfs_part_disk (g, device, data->params[2]) == -1)
    prep_error (data, filename, _("failed to partition disk: %s"),
                guestfs_last_error (g));

  char *part;
  if (asprintf (&part, "%s1", device) == -1) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }

  if (guestfs_mkfs (g, data->params[0], part) == -1)
    prep_error (data, filename, _("failed to create filesystem (%s): %s"),
                data->params[0], guestfs_last_error (g));

  free (part);
}
