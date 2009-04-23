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
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

/* This command exposes debugging information, internals and
 * status.  There is no comprehensive documentation for this
 * command.  You have to look at the source code in this file
 * to find out what you can do.
 *
 * Commands always output a freeform string.
 */

#if ENABLE_DEBUG_COMMAND
struct cmd {
  const char *cmd;
  char * (*f) (const char *subcmd, int argc, char *const *const argv);
};

static char *debug_help (const char *subcmd, int argc, char *const *const argv);
static char *debug_fds (const char *subcmd, int argc, char *const *const argv);
static char *debug_sh (const char *subcmd, int argc, char *const *const argv);

static struct cmd cmds[] = {
  { "help", debug_help },
  { "fds", debug_fds },
  { "sh", debug_sh },
  { NULL, NULL }
};
#endif

char *
do_debug (const char *subcmd, char *const *const argv)
{
#if ENABLE_DEBUG_COMMAND
  int argc, i;

  for (i = argc = 0; argv[i] != NULL; ++i)
    argc++;

  for (i = 0; cmds[i].cmd != NULL; ++i) {
    if (strcasecmp (subcmd, cmds[i].cmd) == 0)
      return cmds[i].f (subcmd, argc, argv);
  }

  reply_with_error ("use 'debug help' to list the supported commands");
  return NULL;
#else
  reply_with_error ("guestfsd was not configured with --enable-debug-command");
  return NULL;
#endif
}

#if ENABLE_DEBUG_COMMAND
static char *
debug_help (const char *subcmd, int argc, char *const *const argv)
{
  int len, i;
  char *r, *p;

  r = strdup ("Commands supported:");
  if (!r) {
    reply_with_perror ("strdup");
    return NULL;
  }

  len = strlen (r);
  for (i = 0; cmds[i].cmd != NULL; ++i) {
    len += strlen (cmds[i].cmd) + 1; /* space + new command */
    p = realloc (r, len + 1);	     /* +1 for the final NUL */
    if (p == NULL) {
      reply_with_perror ("realloc");
      free (r);
      return NULL;
    }
    r = p;

    strcat (r, " ");
    strcat (r, cmds[i].cmd);
  }

  return r;
}

/* Show open FDs. */
static char *
debug_fds (const char *subcmd, int argc, char *const *const argv)
{
  int r;
  char *out;
  size_t size;
  FILE *fp;
  DIR *dir;
  struct dirent *d;
  char fname[256], link[256];
  struct stat statbuf;

  fp = open_memstream (&out, &size);
  if (!fp) {
    reply_with_perror ("open_memstream");
    return NULL;
  }

  dir = opendir ("/proc/self/fd");
  if (!dir) {
    reply_with_perror ("opendir: /proc/self/fd");
    fclose (fp);
    return NULL;
  }

  while ((d = readdir (dir)) != NULL) {
    if (strcmp (d->d_name, ".") == 0 || strcmp (d->d_name, "..") == 0)
      continue;

    snprintf (fname, sizeof fname, "/proc/self/fd/%s", d->d_name);

    r = lstat (fname, &statbuf);
    if (r == -1) {
      reply_with_perror ("stat: %s", fname);
      fclose (fp);
      free (out);
      closedir (dir);
      return NULL;
    }

    if (S_ISLNK (statbuf.st_mode)) {
      r = readlink (fname, link, sizeof link - 1);
      if (r == -1) {
	reply_with_perror ("readline: %s", fname);
	fclose (fp);
	free (out);
	closedir (dir);
	return NULL;
      }
      link[r] = '\0';

      fprintf (fp, "%2s %s\n", d->d_name, link);
    } else
      fprintf (fp, "%2s 0%o\n", d->d_name, statbuf.st_mode);
  }

  fclose (fp);

  if (closedir (dir) == -1) {
    reply_with_perror ("closedir");
    free (out);
    return NULL;
  }

  return out;
}

/* Run an arbitrary shell command. */
static char *
debug_sh (const char *subcmd, int argc, char *const *const argv)
{
  int r;
  char *out, *err;

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("ps: %s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  return out;
}

#endif /* ENABLE_DEBUG_COMMAND */
