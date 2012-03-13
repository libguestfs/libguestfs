/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2012 Red Hat Inc.
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

char **
do_find (const char *dir)
{
  struct stat statbuf;
  int r;
  size_t sysrootdirlen;
  size_t len;
  char *cmd;
  FILE *fp;
  DECLARE_STRINGSBUF (ret);
  char *sysrootdir;
  char str[PATH_MAX];

  sysrootdir = sysroot_path (dir);
  if (!sysrootdir) {
    reply_with_perror ("malloc");
    return NULL;
  }

  r = stat (sysrootdir, &statbuf);
  if (r == -1) {
    reply_with_perror ("%s", dir);
    free (sysrootdir);
    return NULL;
  }
  if (!S_ISDIR (statbuf.st_mode)) {
    reply_with_error ("%s: not a directory", dir);
    free (sysrootdir);
    return NULL;
  }

  sysrootdirlen = strlen (sysrootdir);

  /* Assemble the external find command. */
  if (asprintf_nowarn (&cmd, "find %Q -print0", sysrootdir) == -1) {
    reply_with_perror ("malloc");
    free (sysrootdir);
    return NULL;
  }
  free (sysrootdir);

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", cmd);
    free (cmd);
    return NULL;
  }
  free (cmd);

  while ((r = input_to_nul (fp, str, PATH_MAX)) > 0) {
    len = strlen (str);
    if (len <= sysrootdirlen)
      continue;

    /* Remove the directory part of the path when adding it. */
    if (add_string (&ret, str + sysrootdirlen) == -1) {
      pclose (fp);
      return NULL;
    }
  }
  if (pclose (fp) != 0) {
    reply_with_perror ("pclose");
    free_stringslen (ret.argv, ret.size);
    return NULL;
  }

  if (r == -1) {
    free_stringslen (ret.argv, ret.size);
    return NULL;
  }

  if (ret.size > 0)
    sort_strings (ret.argv, ret.size);

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return ret.argv;              /* caller frees */
}

/* The code below assumes each path returned can fit into a protocol
 * chunk.  If this turns out not to be true at some point in the
 * future then we'll need to modify the code a bit to handle it.
 */
#if PATH_MAX > GUESTFS_MAX_CHUNK_SIZE
#error "PATH_MAX > GUESTFS_MAX_CHUNK_SIZE"
#endif

/* Has one FileOut parameter. */
int
do_find0 (const char *dir)
{
  struct stat statbuf;
  int r;
  FILE *fp;
  char *cmd;
  char *sysrootdir;
  size_t sysrootdirlen, len;
  char str[GUESTFS_MAX_CHUNK_SIZE];

  sysrootdir = sysroot_path (dir);
  if (!sysrootdir) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = stat (sysrootdir, &statbuf);
  if (r == -1) {
    reply_with_perror ("%s", dir);
    free (sysrootdir);
    return -1;
  }
  if (!S_ISDIR (statbuf.st_mode)) {
    reply_with_error ("%s: not a directory", dir);
    free (sysrootdir);
    return -1;
  }

  sysrootdirlen = strlen (sysrootdir);

  if (asprintf_nowarn (&cmd, "find %Q -print0", sysrootdir) == -1) {
    reply_with_perror ("asprintf");
    free (sysrootdir);
    return -1;
  }
  free (sysrootdir);

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", cmd);
    free (cmd);
    return -1;
  }
  free (cmd);

  /* Now we must send the reply message, before the file contents.  After
   * this there is no opportunity in the protocol to send any error
   * message back.  Instead we can only cancel the transfer.
   */
  reply (NULL, NULL);

  while ((r = input_to_nul (fp, str, GUESTFS_MAX_CHUNK_SIZE)) > 0) {
    len = strlen (str);
    if (len <= sysrootdirlen)
      continue;

    /* Remove the directory part of the path before sending it. */
    if (send_file_write (str + sysrootdirlen, r - sysrootdirlen) < 0) {
      pclose (fp);
      return -1;
    }
  }

  if (ferror (fp)) {
    perror (dir);
    send_file_end (1);                /* Cancel. */
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0) {
    perror (dir);
    send_file_end (1);                /* Cancel. */
    return -1;
  }

  if (send_file_end (0))        /* Normal end of file. */
    return -1;

  return 0;
}
