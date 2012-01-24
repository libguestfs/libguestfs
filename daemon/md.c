/* libguestfs - the guestfsd daemon
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <glob.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"
#include "c-ctype.h"

int
optgroup_mdadm_available (void)
{
  return prog_exists ("mdadm");
}

static size_t
count_bits (uint64_t bitmap)
{
  size_t c;

  if (bitmap == 0)
    return 0;

  c = bitmap & 1 ? 1 : 0;
  bitmap >>= 1;
  return c + count_bits (bitmap);
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_md_create (const char *name, char *const *devices,
              int64_t missingbitmap, int nrdevices, int spare,
              int64_t chunk, const char *level)
{
  char nrdevices_s[32];
  char spare_s[32];
  char chunk_s[32];
  size_t j;
  int r;
  char *err;
  uint64_t umissingbitmap = (uint64_t) missingbitmap;

  /* Check the optional parameters and set defaults where appropriate. */
  if (!(optargs_bitmask & GUESTFS_MD_CREATE_MISSINGBITMAP_BITMASK))
    umissingbitmap = 0;

  if (optargs_bitmask & GUESTFS_MD_CREATE_SPARE_BITMASK) {
    if (spare < 0) {
      reply_with_error ("spare must not be negative");
      return -1;
    }
  }
  else
    spare = 0;

  if (optargs_bitmask & GUESTFS_MD_CREATE_NRDEVICES_BITMASK) {
    if (nrdevices < 2) {
      reply_with_error ("nrdevices is less than 2");
      return -1;
    }
  }
  else
    nrdevices = count_strings (devices) + count_bits (umissingbitmap);

  if (optargs_bitmask & GUESTFS_MD_CREATE_LEVEL_BITMASK) {
    if (STRNEQ (level, "linear") && STRNEQ (level, "raid0") &&
        STRNEQ (level, "0") && STRNEQ (level, "stripe") &&
        STRNEQ (level, "raid1") && STRNEQ (level, "1") &&
        STRNEQ (level, "mirror") &&
        STRNEQ (level, "raid4") && STRNEQ (level, "4") &&
        STRNEQ (level, "raid5") && STRNEQ (level, "5") &&
        STRNEQ (level, "raid6") && STRNEQ (level, "6") &&
        STRNEQ (level, "raid10") && STRNEQ (level, "10")) {
      reply_with_error ("unknown level parameter: %s", level);
      return -1;
    }
  }
  else
    level = "raid1";

  if (optargs_bitmask & GUESTFS_MD_CREATE_CHUNK_BITMASK) {
    /* chunk is bytes in the libguestfs API, but K when we pass it to mdadm */
    if ((chunk & 1023) != 0) {
      reply_with_error ("chunk size must be a multiple of 1024 bytes");
      return -1;
    }
  }

  /* Check invariant. */
  if (count_strings (devices) + count_bits (umissingbitmap) !=
      (size_t) (nrdevices + spare)) {
    reply_with_error ("devices (%zu) + bits set in missingbitmap (%zu) is not equal to nrdevices (%d) + spare (%d)",
                      count_strings (devices), count_bits (umissingbitmap),
                      nrdevices, spare);
    return -1;
  }

  size_t MAX_ARGS = nrdevices + 16;
  const char *argv[MAX_ARGS];
  size_t i = 0;

  ADD_ARG (argv, i, "mdadm");
  ADD_ARG (argv, i, "--create");
  /* --run suppresses "Continue creating array" question */
  ADD_ARG (argv, i, "--run");
  ADD_ARG (argv, i, name);
  ADD_ARG (argv, i, "--level");
  ADD_ARG (argv, i, level);
  ADD_ARG (argv, i, "--raid-devices");
  snprintf (nrdevices_s, sizeof nrdevices_s, "%d", nrdevices);
  ADD_ARG (argv, i, nrdevices_s);
  if (optargs_bitmask & GUESTFS_MD_CREATE_SPARE_BITMASK) {
    ADD_ARG (argv, i, "--spare-devices");
    snprintf (spare_s, sizeof spare_s, "%d", spare);
    ADD_ARG (argv, i, spare_s);
  }
  if (optargs_bitmask & GUESTFS_MD_CREATE_CHUNK_BITMASK) {
    ADD_ARG (argv, i, "--chunk");
    snprintf (chunk_s, sizeof chunk_s, "%" PRIi64, chunk / 1024);
    ADD_ARG (argv, i, chunk_s);
  }

  /* Add devices and "missing". */
  j = 0;
  while (devices[j] != NULL || umissingbitmap != 0) {
    if (umissingbitmap & 1)
      ADD_ARG (argv, i, "missing");
    else {
      ADD_ARG (argv, i, devices[j]);
      j++;
    }
    umissingbitmap >>= 1;
  }

  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("mdadm: %s: %s", name, err);
    free (err);
    return -1;
  }

  free (err);

  udev_settle ();

  return 0;
}

static int
glob_errfunc (const char *epath, int eerrno)
{
  fprintf (stderr, "glob: failure reading %s: %s\n", epath, strerror (eerrno));
  return 1;
}

char **
do_list_md_devices (void)
{
  char **r = NULL;
  int size = 0, alloc = 0;
  glob_t mds;

  memset(&mds, 0, sizeof(mds));

#define PREFIX "/sys/block/md"
#define SUFFIX "/md"

  /* Look for directories under /sys/block matching md[0-9]*
   * As an additional check, we also make sure they have a md subdirectory.
   */
  int err = glob (PREFIX "[0-9]*" SUFFIX, GLOB_ERR, glob_errfunc, &mds);
  if (err == GLOB_NOSPACE) {
    reply_with_error ("glob: returned GLOB_NOSPACE: "
                      "rerun with LIBGUESTFS_DEBUG=1");
    goto error;
  } else if (err == GLOB_ABORTED) {
    reply_with_error ("glob: returned GLOB_ABORTED: "
                      "rerun with LIBGUESTFS_DEBUG=1");
    goto error;
  }

  for (size_t i = 0; i < mds.gl_pathc; i++) {
    size_t len = strlen (mds.gl_pathv[i]) - strlen (PREFIX) - strlen (SUFFIX);

#define DEV "/dev/md"
    char *dev = malloc (strlen(DEV) + len  + 1);
    if (NULL == dev) {
      reply_with_perror("malloc");
      goto error;
    }

    char *n = dev;
    n = mempcpy(n, DEV, strlen(DEV));
    n = mempcpy(n, &mds.gl_pathv[i][strlen(PREFIX)], len);
    *n = '\0';

    if (add_string_nodup (&r, &size, &alloc, dev) == -1) goto error;
  }

  if (add_string_nodup (&r, &size, &alloc, NULL) == -1) goto error;
  globfree (&mds);

  return r;

error:
  globfree (&mds);
  if (r != NULL) free_strings (r);
  return NULL;
}

char **
do_md_detail(const char *md)
{
  size_t i;
  int r;

  char *out = NULL, *err = NULL;
  char **lines = NULL;

  char **ret = NULL;
  int size = 0, alloc = 0;

  const char *mdadm[] = { "mdadm", "-D", "--export", md, NULL };
  r = commandv (&out, &err, mdadm);
  if (r == -1) {
    reply_with_error ("%s", err);
    goto error;
  }

  /* Split the command output into lines */
  lines = split_lines (out);
  if (lines == NULL) {
    reply_with_perror ("malloc");
    goto error;
  }

  /* Parse the output of mdadm -D --export:
   * MD_LEVEL=raid1
   * MD_DEVICES=2
   * MD_METADATA=1.0
   * MD_UUID=cfa81b59:b6cfbd53:3f02085b:58f4a2e1
   * MD_NAME=localhost.localdomain:0
   */
  for (i = 0; lines[i] != NULL; ++i) {
    char *line = lines[i];

    /* Skip blank lines (shouldn't happen) */
    if (line[0] == '\0') continue;

    /* Split the line in 2 at the equals sign */
    char *eq = strchr (line, '=');
    if (eq) {
      *eq = '\0'; eq++;

      /* Remove the MD_ prefix from the key and translate the remainder to lower
       * case */
      if (STRPREFIX (line, "MD_")) {
        line += 3;
        for (char *j = line; *j != '\0'; j++) {
          *j = c_tolower (*j);
        }
      }

      /* Add the key/value pair to the output */
      if (add_string (&ret, &size, &alloc, line) == -1 ||
          add_string (&ret, &size, &alloc, eq) == -1) goto error;
    } else {
      /* Ignore lines with no equals sign (shouldn't happen). Log to stderr so
       * it will show up in LIBGUESTFS_DEBUG. */
      fprintf (stderr, "md-detail: unexpected mdadm output ignored: %s", line);
    }
  }

  free (out);
  free (err);
  free_strings (lines);

  if (add_string (&ret, &size, &alloc, NULL) == -1) return NULL;

  return ret;

error:
  free (out);
  free (err);
  if (lines)
    free_strings (lines);
  if (ret)
    free_strings (ret);

  return NULL;
}

int
do_md_stop(const char *md)
{
  int r;
  char *err = NULL;

  const char *mdadm[] = { "mdadm", "--stop", md, NULL};
  r = commandv(NULL, &err, mdadm);
  if (r == -1) {
    reply_with_error("%s", err);
    free(err);
    return -1;
  }
  free (err);
  return 0;
}
