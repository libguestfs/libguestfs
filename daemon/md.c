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
#include <unistd.h>
#include <fcntl.h>

#ifdef HAVE_LINUX_RAID_MD_U_H
#include <sys/ioctl.h>
#include <linux/major.h>
#include <linux/raid/md_u.h>
#endif /* HAVE_LINUX_RAID_MD_U_H */

#include <caml/mlvalues.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"
#include "c-ctype.h"

int
optgroup_mdadm_available (void)
{
  return prog_exists ("mdadm");
}

/* Check if 'dev' is a real RAID device, because in the case where md
 * is linked directly into the kernel (not a module), /dev/md0 is
 * sometimes created.  This is called from OCaml function
 * Md.list_md_devices.
 */
extern value guestfs_int_daemon_is_raid_device (value devicev);

/* NB: This is a [@@noalloc] call. */
value
guestfs_int_daemon_is_raid_device (value devv)
{
  const char *dev = String_val (devv);
  int ret = 1;

#if defined(HAVE_LINUX_RAID_MD_U_H) && defined(GET_ARRAY_INFO)
  int fd;
  mdu_array_info_t array;

  fd = open (dev, O_RDONLY);
  if (fd >= 0) {
    if (ioctl (fd, GET_ARRAY_INFO, &array) == -1 && errno == ENODEV)
      ret = 0;
    close (fd);
  }
#endif

  return Val_bool (ret);
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

#if defined(__GNUC__) && GUESTFS_GCC_VERSION >= 40800 /* gcc >= 4.8.0 */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wstack-usage="
#endif

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
  CLEANUP_FREE char *err = NULL;
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
    nrdevices =
      guestfs_int_count_strings (devices) + count_bits (umissingbitmap);

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
  if (guestfs_int_count_strings (devices) + count_bits (umissingbitmap) !=
      (size_t) (nrdevices + spare)) {
    reply_with_error ("devices (%zu) + bits set in missingbitmap (%zu) is not equal to nrdevices (%d) + spare (%d)",
                      guestfs_int_count_strings (devices),
                      count_bits (umissingbitmap),
                      nrdevices, spare);
    return -1;
  }

  const size_t MAX_ARGS = nrdevices + 16;
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
    return -1;
  }

  udev_settle ();

  return 0;
}

#if defined(__GNUC__) && GUESTFS_GCC_VERSION >= 40800 /* gcc >= 4.8.0 */
#pragma GCC diagnostic pop
#endif

int
do_md_stop (const char *md)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  const char *mdadm[] = { "mdadm", "--stop", md, NULL};
  r = commandv (NULL, &err, mdadm);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }
  return 0;
}

static size_t
count_spaces (const char *line)
{
  size_t r = 0;
  while (*line) {
    if (*line == ' ')
      r++;
    line++;
  }
  return r;
}

/* Parse a line like: "active raid1 sdb1[0] sdc1[1](F)" */
static guestfs_int_mdstat_list *
parse_md_stat_line (char *line)
{
  guestfs_int_mdstat_list *ret;
  guestfs_int_mdstat *t;
  size_t spaces, n, i, len;
  char *next;
  char *p, *q;

  ret = malloc (sizeof *ret);
  if (!ret) {
    reply_with_perror ("malloc");
    return NULL;
  }

  /* We don't know exactly how many entries we will need yet, but we
   * can estimate it, and this will always be an over-estimate.
   */
  spaces = count_spaces (line);
  ret->guestfs_int_mdstat_list_val =
    calloc (spaces+1, sizeof (struct guestfs_int_mdstat));
  if (ret->guestfs_int_mdstat_list_val == NULL) {
    reply_with_perror ("calloc");
    free (ret);
    return NULL;
  }

  for (n = 0; *line; line = next) {
    len = strcspn (line, " ");
    if (line[len] == '\0')
      next = &line[len];
    else {
      line[len] = '\0';
      next = &line[len+1];
    }

    if (verbose)
      printf ("mdstat: %s\n", line);

    /* Looking for entries that contain "[..]", skip ones which don't. */
    p = strchr (line, '[');
    if (p == NULL)
      continue;
    q = strchr (line, ']');
    if (q == NULL)
      continue;
    if (p > q)
      continue;

    ret->guestfs_int_mdstat_list_len = n+1;
    t = &ret->guestfs_int_mdstat_list_val[n];

    /* Device name is everything before the '[' character, but we
     * need to prefix with /dev/.
     */
    if (p == line) {
      reply_with_error ("device entry is too short: %s", line);
      goto error;
    }

    *p = '\0';
    if (asprintf (&t->mdstat_device, "/dev/%s", line) == -1) {
      reply_with_perror ("asprintf");
      goto error;
    }

    /* Device index is the number after '['. */
    line = p+1;
    *q = '\0';
    if (sscanf (line, "%" SCNi32, &t->mdstat_index) != 1) {
      reply_with_error ("not a device number: %s", line);
      goto error;
    }

    /* Looking for flags "(F)(S)...". */
    line = q+1;
    len = strlen (line);
    t->mdstat_flags = malloc (len+1);
    if (!t->mdstat_flags) {
      reply_with_error ("malloc");
      goto error;
    }

    for (i = 0; *line; line++) {
      if (c_isalpha (*line))
        t->mdstat_flags[i++] = *line;
    }
    t->mdstat_flags[i] = '\0';

    n++;
  }

  return ret;

 error:
  for (i = 0; i < spaces+1; ++i) {
    free (ret->guestfs_int_mdstat_list_val[i].mdstat_device);
    free (ret->guestfs_int_mdstat_list_val[i].mdstat_flags);
  }
  free (ret->guestfs_int_mdstat_list_val);
  free (ret);
  return NULL;
}

extern guestfs_int_mdstat_list *
do_md_stat (const char *md)
{
  size_t mdlen;
  FILE *fp;
  CLEANUP_FREE char *line = NULL;
  size_t allocsize = 0;
  ssize_t n;
  guestfs_int_mdstat_list *ret = NULL;

  if (STRPREFIX (md, "/dev/"))
    md += 5;
  mdlen = strlen (md);

  fp = fopen ("/proc/mdstat", "r");
  if (fp == NULL) {
    reply_with_perror ("fopen: %s", "/proc/mdstat");
    return NULL;
  }

  /* Search for a line which begins with "<md> : ". */
  while ((n = getline (&line, &allocsize, fp)) != -1) {
    if (STRPREFIX (line, md) &&
        line[mdlen] == ' ' && line[mdlen+1] == ':' && line[mdlen+2] == ' ') {
      /* Found it. */
      ret = parse_md_stat_line (&line[mdlen+3]);
      if (!ret) {
        fclose (fp);
        return NULL;
      }

      /* Stop parsing the mdstat file after we've found the line
       * we are interested in.
       */
      break;
    }
  }

  if (fclose (fp) == EOF) {
    reply_with_perror ("fclose: %s", "/proc/mdstat");
    xdr_free ((xdrproc_t) xdr_guestfs_int_mdstat_list, (char *) ret);
    return NULL;
  }

  /* Did we find the line? */
  if (!ret) {
    reply_with_error ("%s: MD device not found", md);
    return NULL;
  }

  return ret;
}
