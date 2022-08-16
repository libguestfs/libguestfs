/* libguestfs - the guestfsd daemon
 * Copyright (C) 2014 Red Hat Inc.
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
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

/* Has one FileOut parameter. */
/* Takes optional arguments, consult optargs_bitmask. */
int
do_cpio_out (const char *dir, const char *format)
{
  CLEANUP_FREE char *buf = NULL;
  struct stat statbuf;
  int r;
  FILE *fp;
  CLEANUP_FREE char *cmd = NULL;
  size_t cmd_size;
  CLEANUP_FREE char *buffer = NULL;

  buffer = malloc (GUESTFS_MAX_CHUNK_SIZE);
  if (buffer == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  /* Check the filename exists and is a directory (RHBZ#908322). */
  buf = sysroot_path (dir);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  if (stat (buf, &statbuf) == -1) {
    reply_with_perror ("stat: %s", dir);
    return -1;
  }

  if (! S_ISDIR (statbuf.st_mode)) {
    reply_with_error ("%s: not a directory", dir);
    return -1;
  }

  /* Check the format is one of the permitted ones. */
  if ((optargs_bitmask & GUESTFS_CPIO_OUT_FORMAT_BITMASK)) {
    if (STRNEQ (format, "newc") && STRNEQ (format, "crc")) {
      reply_with_error ("%s: format must be 'newc' or 'crc'", format);
      return -1;
    }
  }
  else
    format = "newc";

  fp = open_memstream (&cmd, &cmd_size);
  if (fp == NULL) {
  cmd_error:
    reply_with_perror ("open_memstream");
    return -1;
  }
  fprintf (fp, "cd ");
  shell_quote (buf, fp);
  fprintf (fp, " && find -print0 | %s -0 -o -H %s --quiet", "cpio", format);
  if (fclose (fp) == EOF)
    goto cmd_error;

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
    fprintf (stderr, "fread: %s: %m\n", dir);
    send_file_end (1);		/* Cancel. */
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0) {
    fprintf (stderr, "pclose: %s: %m\n", dir);
    send_file_end (1);		/* Cancel. */
    return -1;
  }

  if (send_file_end (0))	/* Normal end of file. */
    return -1;

  return 0;
}
