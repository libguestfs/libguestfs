/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009 Red Hat Inc.
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
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

static int
input_to_nul (FILE *fp, char *buf, int maxlen)
{
  int i = 0, c;

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
do_find (char *dir)
{
  struct stat statbuf;
  int r, len, sysrootdirlen;
  char *cmd;
  FILE *fp;
  char **res = NULL;
  int size = 0, alloc = 0;
  char *sysrootdir;
  char str[PATH_MAX];

  NEED_ROOT (NULL);
  ABS_PATH (dir, return NULL);

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
    if (verbose)
      printf ("find string: %s\n", str);

    len = strlen (str);
    if (len <= sysrootdirlen)
      continue;

    /* Remove the directory part of the path when adding it. */
    if (add_string (&res, &size, &alloc, str + sysrootdirlen) == -1) {
      pclose (fp);
      return NULL;
    }
  }
  if (pclose (fp) != 0) {
    reply_with_perror ("pclose: find");
    free_stringslen (res, size);
    return NULL;
  }

  if (r == -1) {
    free_stringslen (res, size);
    return NULL;
  }

  if (add_string (&res, &size, &alloc, NULL) == -1)
    return NULL;

  sort_strings (res, size-1);

  return res;			/* caller frees */
}
