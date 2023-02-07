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
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/stat.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

static int
input_to_nul (FILE *fp, char *buf, size_t maxlen)
{
  size_t i = 0;
  int c;

  while (i < maxlen) {
    c = fgetc (fp);
    if (c == EOF)
      return 0;
    buf[i++] = c;
    if (c == '\0')
      return i;
  }

  reply_with_error ("input_to_nul: input string too long");
  return -1;
}

/* Has one FileOut parameter. */
int
do_find0 (const char *dir)
{
  struct stat statbuf;
  int r;
  FILE *fp;
  CLEANUP_FREE char *cmd = NULL;
  size_t cmd_size;
  CLEANUP_FREE char *sysrootdir = NULL;
  size_t sysrootdirlen;
  CLEANUP_FREE char *str = NULL;

  str = malloc (GUESTFS_MAX_CHUNK_SIZE);
  if (str == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  sysrootdir = sysroot_path (dir);
  if (!sysrootdir) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = stat (sysrootdir, &statbuf);
  if (r == -1) {
    reply_with_perror ("%s", dir);
    return -1;
  }
  if (!S_ISDIR (statbuf.st_mode)) {
    reply_with_error ("%s: not a directory", dir);
    return -1;
  }

  sysrootdirlen = strlen (sysrootdir);

  fp = open_memstream (&cmd, &cmd_size);
  if (fp == NULL) {
  cmd_error:
    reply_with_perror ("open_memstream");
    return -1;
  }
  fprintf (fp, "find ");
  shell_quote (sysrootdir, fp);
  fprintf (fp, " -print0");
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

  /* The code below assumes each path returned can fit into a protocol
   * chunk (if not you'll get a runtime protocol error).  If this
   * turns out not to be a problem at some point in the future then
   * we'll need to modify the code to handle it.  XXX
   */
  while ((r = input_to_nul (fp, str, GUESTFS_MAX_CHUNK_SIZE)) > 0) {
    const size_t len = strlen (str);
    if (len <= sysrootdirlen)
      continue;

    /* Remove the directory part of the path before sending it. */
    if (send_file_write (str + sysrootdirlen, r - sysrootdirlen) < 0) {
      pclose (fp);
      return -1;
    }
  }

  if (ferror (fp)) {
    fprintf (stderr, "fgetc: %s: %m\n", dir);
    send_file_end (1);                /* Cancel. */
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0) {
    fprintf (stderr, "pclose: %s: %m\n", dir);
    send_file_end (1);                /* Cancel. */
    return -1;
  }

  if (send_file_end (0))        /* Normal end of file. */
    return -1;

  return 0;
}
