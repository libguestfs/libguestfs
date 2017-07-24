/* libguestfs - the guestfsd daemon
 * Copyright (C) 2017 Red Hat Inc.
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
#include <unistd.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#define MAX_ARGS 64

int
optgroup_squashfs_available (void)
{
  return prog_exists ("mksquashfs");
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_mksquashfs (const char *path, const char *compress, char *const *excludes)
{
  CLEANUP_FREE char *buf = NULL;
  CLEANUP_UNLINK_FREE char *tmpfile = NULL;
  CLEANUP_UNLINK_FREE char *exclude_from_file = NULL;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE char *buffer = NULL;
  int r;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  int fd;
  FILE *fp;

  buf = sysroot_path (path);
  if (buf == NULL) {
    reply_with_perror ("malloc/sysroot_path");
    return -1;
  }

  /* /var/tmp is used instead of /tmp, as /tmp is mounted as tmpfs
   * and thus a newly created filesystem might not fit in memory.
   */
  tmpfile = strdup ("/var/tmp/squashfs.XXXXXX");
  if (tmpfile == NULL) {
    reply_with_perror ("strdup");
    return -1;
  }

  fd = mkstemp (tmpfile);
  if (fd == -1) {
    reply_with_perror ("mkstemp");
    return -1;
  }
  close (fd);

  buffer = malloc (GUESTFS_MAX_CHUNK_SIZE);
  if (buffer == NULL) {
    reply_with_perror ("malloc/buffer");
    return -1;
  }

  ADD_ARG (argv, i, "mksquashfs");
  ADD_ARG (argv, i, buf);
  ADD_ARG (argv, i, tmpfile);
  ADD_ARG (argv, i, "-noappend");
  ADD_ARG (argv, i, "-root-becomes");
  ADD_ARG (argv, i, buf);
  ADD_ARG (argv, i, "-wildcards");
  ADD_ARG (argv, i, "-no-recovery");

  if (optargs_bitmask & GUESTFS_MKSQUASHFS_COMPRESS_BITMASK) {
    ADD_ARG (argv, i, "-comp");
    ADD_ARG (argv, i, compress);
  }

  if (optargs_bitmask & GUESTFS_MKSQUASHFS_EXCLUDES_BITMASK) {
    exclude_from_file = make_exclude_from_file ("mksquashfs", excludes);
    if (!exclude_from_file)
      return -1;

    ADD_ARG (argv, i, "-ef");
    ADD_ARG (argv, i, exclude_from_file);
  }

  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", path, err);
    return -1;
  }

  fp = fopen (tmpfile, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", tmpfile);
    return -1;
  }

  /* Now we must send the reply message, before the file contents.  After
   * this there is no opportunity in the protocol to send any error
   * message back.  Instead we can only cancel the transfer.
   */
  reply (NULL, NULL);

  while ((r = fread (buffer, 1, GUESTFS_MAX_CHUNK_SIZE, fp)) > 0) {
    if (send_file_write (buffer, r) < 0) {
      fclose (fp);
      return -1;
    }
  }

  if (ferror (fp)) {
    fprintf (stderr, "fread: %s: %m\n", tmpfile);
    send_file_end (1);		/* Cancel. */
    fclose (fp);
    return -1;
  }

  if (fclose (fp) != 0) {
    fprintf (stderr, "fclose: %s: %m\n", tmpfile);
    send_file_end (1);		/* Cancel. */
    return -1;
  }

  if (send_file_end (0))	/* Normal end of file. */
    return -1;

  return 0;
}
