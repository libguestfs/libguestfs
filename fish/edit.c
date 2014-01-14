/* guestfish - guest filesystem shell
 * Copyright (C) 2009-2014 Red Hat Inc.
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
#include <libintl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <assert.h>

#include "fish.h"

static char *generate_random_name (const char *filename);

/* guestfish edit command, suggested by Ján Ondrej, implemented by RWMJ */

int
run_edit (const char *cmd, size_t argc, char *argv[])
{
  CLEANUP_FREE char *tmpdir = guestfs_get_tmpdir (g);
  CLEANUP_UNLINK_FREE char *filename = NULL;
  char buf[256];
  const char *editor;
  CLEANUP_FREE char *remotefilename = NULL, *newname = NULL;
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
  if (asprintf (&filename, "%s/guestfishXXXXXX", tmpdir) == -1) {
    perror ("asprintf");
    return -1;
  }

  fd = mkstemp (filename);
  if (fd == -1) {
    perror ("mkstemp");
    return -1;
  }

  snprintf (buf, sizeof buf, "/dev/fd/%d", fd);

  if (guestfs_download (g, remotefilename, buf) == -1) {
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    perror (filename);
    return -1;
  }

  /* Get the old stat. */
  if (stat (filename, &oldstat) == -1) {
    perror (filename);
    return -1;
  }

  /* Edit it. */
  /* XXX Safe? */
  snprintf (buf, sizeof buf, "%s %s", editor, filename);

  r = system (buf);
  if (r != 0) {
    perror (buf);
    return -1;
  }

  /* Get the new stat. */
  if (stat (filename, &newstat) == -1) {
    perror (filename);
    return -1;
  }

  /* Changed? */
  if (oldstat.st_ctime == newstat.st_ctime &&
      oldstat.st_size == newstat.st_size)
    return 0;

  /* Upload to a new file in the same directory, so if it fails we
   * don't end up with a partially written file.  Give the new file
   * a completely random name so we have only a tiny chance of
   * overwriting some existing file.
   */
  newname = generate_random_name (remotefilename);
  if (!newname)
    return -1;

  /* Write new content. */
  if (guestfs_upload (g, filename, newname) == -1)
    return -1;

  /* Set the permissions, UID, GID and SELinux context of the new
   * file to match the old file (RHBZ#788641).
   */
  if (guestfs_copy_attributes (g, remotefilename, newname,
      GUESTFS_COPY_ATTRIBUTES_ALL, 1, -1) == -1)
    return -1;

  if (guestfs_mv (g, newname, remotefilename) == -1)
    return -1;

  return 0;
}

static char
random_char (void)
{
  char c[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  return c[random () % (sizeof c - 1)];
}

static char *
generate_random_name (const char *filename)
{
  char *ret, *p;
  size_t i;

  ret = malloc (strlen (filename) + 16);
  if (!ret) {
    perror ("malloc");
    return NULL;
  }
  strcpy (ret, filename);

  p = strrchr (ret, '/');
  assert (p);
  p++;

  /* Because of "+ 16" above, there should be enough space in the
   * output buffer to write 8 random characters here.
   */
  for (i = 0; i < 8; ++i)
    *p++ = random_char ();
  *p++ = '\0';

  return ret; /* caller will free */
}
