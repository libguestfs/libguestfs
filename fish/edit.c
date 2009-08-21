/* guestfish - the filesystem interactive shell
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
#include <inttypes.h>

#include "fish.h"

/* guestfish edit command, suggested by Ján Ondrej, implemented by RWMJ */

static char *
load_file (const char *filename, size_t *len_r)
{
  int fd, r, start;
  char *content = NULL, *p;
  char buf[65536];

  *len_r = 0;

  fd = open (filename, O_RDONLY);
  if (fd == -1) {
    perror (filename);
    return NULL;
  }

  while ((r = read (fd, buf, sizeof buf)) > 0) {
    start = *len_r;
    *len_r += r;
    p = realloc (content, *len_r + 1);
    if (p == NULL) {
      perror ("realloc");
      free (content);
      return NULL;
    }
    content = p;
    memcpy (content + start, buf, r);
    content[start+r] = '\0';
  }

  if (r == -1) {
    perror (filename);
    free (content);
    return NULL;
  }

  if (close (fd) == -1) {
    perror (filename);
    free (content);
    return NULL;
  }

  return content;
}

int
do_edit (const char *cmd, int argc, char *argv[])
{
  char filename[] = "/tmp/guestfishXXXXXX";
  char buf[256];
  const char *editor;
  char *content, *content_new;
  int r, fd;

  if (argc != 1) {
    fprintf (stderr, _("use '%s filename' to edit a file\n"), cmd);
    return -1;
  }

  /* Choose an editor. */
  if (strcasecmp (cmd, "vi") == 0)
    editor = "vi";
  else if (strcasecmp (cmd, "emacs") == 0)
    editor = "emacs -nw";
  else {
    editor = getenv ("EDITOR");
    if (editor == NULL)
      editor = "vi"; /* could be cruel here and choose ed(1) */
  }

  /* Download the file and write it to a temporary. */
  fd = mkstemp (filename);
  if (fd == -1) {
    perror ("mkstemp");
    return -1;
  }

  if ((content = guestfs_cat (g, argv[0])) == NULL) {
    close (fd);
    unlink (filename);
    return -1;
  }

  if (xwrite (fd, content, strlen (content)) == -1) {
    close (fd);
    unlink (filename);
    free (content);
    return -1;
  }

  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    free (content);
    return -1;
  }

  /* Edit it. */
  /* XXX Safe? */
  snprintf (buf, sizeof buf, "%s %s", editor, filename);

  r = system (buf);
  if (r != 0) {
    perror (buf);
    unlink (filename);
    free (content);
    return -1;
  }

  /* Reload it. */
  size_t size;
  content_new = load_file (filename, &size);
  if (content_new == NULL) {
    unlink (filename);
    free (content);
    return -1;
  }

  unlink (filename);

  /* Changed? */
  if (strlen (content) == size && strncmp (content, content_new, size) == 0) {
    free (content);
    free (content_new);
    return 0;
  }

  /* Write new content. */
  if (guestfs_write_file (g, argv[0], content_new, size) == -1) {
    free (content);
    free (content_new);
    return -1;
  }

  free (content);
  free (content_new);
  return 0;
}
