/* guestfish - the filesystem interactive shell
 * Copyright (C) 2009-2011 Red Hat Inc.
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
#include <inttypes.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "fish.h"

/* guestfish edit command, suggested by Ján Ondrej, implemented by RWMJ */

int
run_edit (const char *cmd, size_t argc, char *argv[])
{
  TMP_TEMPLATE_ON_STACK (filename);
  char buf[256];
  const char *editor;
  char *remotefilename;
  struct stat oldstat, newstat;
  int r, fd;

  if (argc != 1) {
    fprintf (stderr, _("use '%s filename' to edit a file\n"), cmd);
    return -1;
  }

  /* Choose an editor. */
  if (STRCASEEQ (cmd, "vi"))
    editor = "vi";
  else if (STRCASEEQ (cmd, "emacs"))
    editor = "emacs -nw";
  else {
    editor = getenv ("EDITOR");
    if (editor == NULL)
      editor = "vi"; /* could be cruel here and choose ed(1) */
  }

  /* Handle 'win:...' prefix. */
  remotefilename = win_prefix (argv[0]);
  if (remotefilename == NULL)
    return -1;

  /* Download the file and write it to a temporary. */
  fd = mkstemp (filename);
  if (fd == -1) {
    perror ("mkstemp");
    free (remotefilename);
    return -1;
  }

  snprintf (buf, sizeof buf, "/dev/fd/%d", fd);

  if (guestfs_download (g, remotefilename, buf) == -1) {
    close (fd);
    unlink (filename);
    free (remotefilename);
    return -1;
  }

  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    free (remotefilename);
    return -1;
  }

  /* Get the old stat. */
  if (stat (filename, &oldstat) == -1) {
    perror (filename);
    unlink (filename);
    free (remotefilename);
    return -1;
  }

  /* Edit it. */
  /* XXX Safe? */
  snprintf (buf, sizeof buf, "%s %s", editor, filename);

  r = system (buf);
  if (r != 0) {
    perror (buf);
    unlink (filename);
    free (remotefilename);
    return -1;
  }

  /* Get the new stat. */
  if (stat (filename, &newstat) == -1) {
    perror (filename);
    unlink (filename);
    free (remotefilename);
    return -1;
  }

  /* Changed? */
  if (oldstat.st_ctime == newstat.st_ctime &&
      oldstat.st_size == newstat.st_size) {
    unlink (filename);
    free (remotefilename);
    return 0;
  }

  /* Write new content. */
  if (guestfs_upload (g, filename, remotefilename) == -1) {
    unlink (filename);
    free (remotefilename);
    return -1;
  }

  unlink (filename);
  free (remotefilename);
  return 0;
}
