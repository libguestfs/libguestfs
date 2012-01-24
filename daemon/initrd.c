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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

char **
do_initrd_list (const char *path)
{
  FILE *fp;
  char *cmd;
  char filename[PATH_MAX];
  char **filenames = NULL;
  int size = 0, alloc = 0;
  size_t len;

  /* "zcat /sysroot/<path> | cpio --quiet -it", but path must be quoted. */
  if (asprintf_nowarn (&cmd, "zcat %R | cpio --quiet -it", path) == -1) {
    reply_with_perror ("asprintf");
    return NULL;
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("popen: %s", cmd);
    free (cmd);
    return NULL;
  }
  free (cmd);

  while (fgets (filename, sizeof filename, fp) != NULL) {
    len = strlen (filename);
    if (len > 0 && filename[len-1] == '\n')
      filename[len-1] = '\0';

    if (add_string (&filenames, &size, &alloc, filename) == -1) {
      pclose (fp);
      return NULL;
    }
  }

  if (add_string (&filenames, &size, &alloc, NULL) == -1) {
    pclose (fp);
    return NULL;
  }

  if (pclose (fp) != 0) {
    reply_with_perror ("pclose");
    free_strings (filenames);
    return NULL;
  }

  return filenames;
}

char *
do_initrd_cat (const char *path, const char *filename, size_t *size_r)
{
  char tmpdir[] = "/tmp/initrd-cat-XXXXXX";
  if (mkdtemp (tmpdir) == NULL) {
    reply_with_perror ("mkdtemp");
    return NULL;
  }

  /* "zcat /sysroot/<path> | cpio --quiet -id file", but paths must be quoted */
  char *cmd;
  if (asprintf_nowarn (&cmd, "cd %Q && zcat %R | cpio --quiet -id %Q",
                       tmpdir, path, filename) == -1) {
    reply_with_perror ("asprintf");
    rmdir (tmpdir);
    return NULL;
  }

  /* Extract file into temporary directory.  This may create subdirs.
   * It's also possible that this doesn't create anything at all
   * (eg. if the named file does not exist in the cpio archive) --
   * cpio is silent in this case.
   */
  int r = system (cmd);
  if (r == -1) {
    reply_with_perror ("command failed: %s", cmd);
    free (cmd);
    rmdir (tmpdir);
    return NULL;
  }
  free (cmd);
  if (WEXITSTATUS (r) != 0) {
    reply_with_perror ("command failed with return code %d",
                       WEXITSTATUS (r));
    rmdir (tmpdir);
    return NULL;
  }

  /* See if we got a file. */
  char fullpath[PATH_MAX];
  snprintf (fullpath, sizeof fullpath, "%s/%s", tmpdir, filename);

  struct stat statbuf;
  int fd;

  fd = open (fullpath, O_RDONLY);
  if (fd == -1) {
    reply_with_perror ("open: %s:%s", path, filename);
    rmdir (tmpdir);
    return NULL;
  }

  /* From this point, we know the file exists, so we require full
   * cleanup.
   */
  char *ret = NULL;

  if (fstat (fd, &statbuf) == -1) {
    reply_with_perror ("fstat: %s:%s", path, filename);
    goto cleanup;
  }

  /* The actual limit on messages is smaller than this.  This
   * check just limits the amount of memory we'll try and allocate
   * here.  If the message is larger than the real limit, that will
   * be caught later when we try to serialize the message.
   */
  if (statbuf.st_size >= GUESTFS_MESSAGE_MAX) {
    reply_with_error ("%s:%s: file is too large for the protocol",
                      path, filename);
    goto cleanup;
  }

  ret = malloc (statbuf.st_size);
  if (ret == NULL) {
    reply_with_perror ("malloc");
    goto cleanup;
  }

  if (xread (fd, ret, statbuf.st_size) == -1) {
    reply_with_perror ("read: %s:%s", path, filename);
    free (ret);
    ret = NULL;
    goto cleanup;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s:%s", path, filename);
    free (ret);
    ret = NULL;
    goto cleanup;
  }
  fd = -1;

  /* Mustn't touch *size_r until we are sure that we won't return any
   * error (RHBZ#589039).
   */
  *size_r = statbuf.st_size;

 cleanup:
  if (fd >= 0)
    close (fd);

  /* Remove the file. */
  if (unlink (fullpath) == -1) {
    fprintf (stderr, "unlink: ");
    perror (fullpath);
    /* non-fatal */
  }

  /* Remove the directories up to and including the temp directory. */
  do {
    char *p = strrchr (fullpath, '/');
    if (!p) break;
    *p = '\0';
    if (rmdir (fullpath) == -1) {
      fprintf (stderr, "rmdir: ");
      perror (fullpath);
      /* non-fatal */
    }
  } while (STRNEQ (fullpath, tmpdir));

  return ret;
}
