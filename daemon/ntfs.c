/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2023 Red Hat Inc.
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
#include <inttypes.h>
#include <string.h>
#include <unistd.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"
#include "xstrtol.h"

#define MAX_ARGS 64

int
optgroup_ntfs3g_available (void)
{
  return prog_exists ("ntfs-3g.probe");
}

int
optgroup_ntfsprogs_available (void)
{
  return prog_exists ("ntfsresize");
}

char *
ntfs_get_label (const char *device)
{
  int r;
  CLEANUP_FREE char *err = NULL;
  char *out = NULL;
  size_t len;

  r = command (&out, &err, "ntfslabel", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    return NULL;
  }

  /* Trim trailing \n if present. */
  len = strlen (out);
  if (len > 0 && out[len-1] == '\n')
    out[len-1] = '\0';

  return out;
}

int
ntfs_set_label (const char *device, const char *label)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  /* XXX We should check if the label is longer than 128 unicode
   * characters and return an error.  This is not so easy since we
   * don't have the required libraries.
   */
  r = command (NULL, &err, "ntfslabel", device, label, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
do_ntfs_3g_probe (int rw, const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;
  const char *rw_flag;

  rw_flag = rw ? "-w" : "-r";

  r = commandr (NULL, &err, "ntfs-3g.probe", rw_flag, device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return r;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_ntfsresize (const char *device, int64_t size, int force)
{
  CLEANUP_FREE char *err = NULL;
  int r;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  char size_str[32];

  ADD_ARG (argv, i, "ntfsresize");
  ADD_ARG (argv, i, "-P");

  if (optargs_bitmask & GUESTFS_NTFSRESIZE_SIZE_BITMASK) {
    if (size <= 0) {
      reply_with_error ("size is zero or negative");
      return -1;
    }

    snprintf (size_str, sizeof size_str, "%" PRIi64, size);
    ADD_ARG (argv, i, "--size");
    ADD_ARG (argv, i, size_str);
  }

  if (optargs_bitmask & GUESTFS_NTFSRESIZE_FORCE_BITMASK && force)
    ADD_ARG (argv, i, "--force");

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  r = commandvf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return 0;
}

int
do_ntfsresize_size (const char *device, int64_t size)
{
  optargs_bitmask = GUESTFS_NTFSRESIZE_SIZE_BITMASK;
  return do_ntfsresize (device, size, 0);
}

int64_t
ntfs_minimum_size (const char *device)
{
  CLEANUP_FREE char *err = NULL, *out = NULL;
  CLEANUP_FREE_STRING_LIST char **lines = NULL;
  int r;
  size_t i;
  int64_t volume_size = 0;
  const char *size_pattern = "You might resize at ",
             *full_pattern = "Volume is full",
             *cluster_size_pattern = "Cluster size",
             *volume_size_pattern = "Current volume size:";
  int is_full = 0;
  int32_t cluster_size = 0;

  /* FS may be marked for check, so force ntfsresize */
  r = command (&out, &err, "ntfsresize", "--info", "-ff", device, NULL);

  lines = split_lines (out);
  if (lines == NULL)
    return -1;

  if (verbose) {
    for (i = 0; lines[i] != NULL; ++i)
      fprintf (stderr, "ntfs_minimum_size: lines[%zu] = \"%s\"\n", i, lines[i]);
  }

#if __WORDSIZE == 64
#define XSTRTOD64 xstrtol
#else
#define XSTRTOD64 xstrtoll
#endif

  if (r == -1) {
    /* If volume is full, ntfsresize returns error. */
    for (i = 0; lines[i] != NULL; ++i) {
      if (strstr (lines[i], full_pattern))
        is_full = 1;
      else if (STRPREFIX (lines[i], cluster_size_pattern)) {
        if (sscanf (lines[i] + strlen (cluster_size_pattern),
                    "%*[ ]:%" SCNd32, &cluster_size) != 1) {
          reply_with_error ("cannot parse cluster size");
          return -1;
        }
      }
      else if (STRPREFIX (lines[i], volume_size_pattern)) {
        if (XSTRTOD64 (lines[i] + strlen (volume_size_pattern),
                       NULL, 10, &volume_size, NULL) != LONGINT_OK) {
          reply_with_error ("cannot parse volume size");
          return -1;
        }
      }
    }
    if (is_full) {
      if (cluster_size == 0) {
        reply_with_error ("bad cluster size");
        return -1;
      }
      /* In case of a full filesystem, we estimate minimum size
       * as volume size rounded up to cluster size.
       */
      return (volume_size + cluster_size - 1) / cluster_size * cluster_size;
    }

    reply_with_error ("%s", err);
    return -1;
  }

  for (i = 0; lines[i] != NULL; ++i) {
    if (STRPREFIX (lines[i], size_pattern)) {
      int64_t ret;
      if (XSTRTOD64 (lines[i] + strlen (size_pattern),
                     NULL, 10, &ret, NULL) != LONGINT_OK) {
        reply_with_error ("cannot parse minimum size");
        return -1;
      }
      return ret;
    }
  }

#undef XSTRTOD64

  reply_with_error ("minimum size not found. Check output format:\n%s", out);
  return -1;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_ntfsfix (const char *device, int clearbadsectors)
{
  const char *argv[MAX_ARGS];
  size_t i = 0;
  int r;
  CLEANUP_FREE char *err = NULL;

  ADD_ARG (argv, i, "ntfsfix");

  if ((optargs_bitmask & GUESTFS_NTFSFIX_CLEARBADSECTORS_BITMASK) &&
      clearbadsectors)
    ADD_ARG (argv, i, "-b");

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return 0;
}

int
do_ntfscat_i (const mountable_t *mountable, int64_t inode)
{
  int r;
  FILE *fp;
  CLEANUP_FREE char *cmd = NULL;
  CLEANUP_FREE char *buffer = NULL;

  buffer = malloc (GUESTFS_MAX_CHUNK_SIZE);
  if (buffer == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  /* Inode must be greater than 0 */
  if (inode < 0) {
    reply_with_error ("inode must be >= 0");
    return -1;
  }

  /* Construct the command. */
  if (asprintf (&cmd, "ntfscat -i %" PRIi64 " %s",
                inode, mountable->device) == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", cmd);
    return -1;
  }

  /* Now we must send the reply message, before the file contents.  After
   * this there is no opportunity in the protocol to send any error
   * message back.  Instead we can only cancel the transfer.
   */
  reply (NULL, NULL);

  while ((r = fread (buffer, 1, GUESTFS_MAX_CHUNK_SIZE, fp)) > 0) {
    if (send_file_write (buffer, r) < 0) {
      pclose (fp);
      return -1;
    }
  }

  if (ferror (fp)) {
    fprintf (stderr, "fread: %" PRIi64 ": %m\n", inode);
    send_file_end (1);		/* Cancel. */
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0) {
    fprintf (stderr, "pclose: %" PRIi64 ": %m\n", inode);
    send_file_end (1);		/* Cancel. */
    return -1;
  }

  if (send_file_end (0))	/* Normal end of file. */
    return -1;

  return 0;
}
