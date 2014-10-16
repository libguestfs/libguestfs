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
#include <sys/wait.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

GUESTFSD_EXT_CMD(str_zcat, zcat);
GUESTFSD_EXT_CMD(str_cpio, cpio);

char **
do_initrd_list (const char *path)
{
  FILE *fp;
  CLEANUP_FREE char *cmd = NULL;
  DECLARE_STRINGSBUF (filenames);
  CLEANUP_FREE char *filename = NULL;
  size_t allocsize;
  ssize_t len;

  /* "zcat /sysroot/<path> | cpio --quiet -it", but path must be quoted. */
  if (asprintf_nowarn (&cmd, "%s %R | %s --quiet -it", str_zcat, path, str_cpio) == -1) {
    reply_with_perror ("asprintf");
    return NULL;
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("popen: %s", cmd);
    return NULL;
  }

  allocsize = 0;
  while ((len = getline (&filename, &allocsize, fp)) != -1) {
    if (len > 0 && filename[len-1] == '\n')
      filename[len-1] = '\0';
    if (add_string (&filenames, filename) == -1) {
      pclose (fp);
      return NULL;
    }
  }

  if (end_stringsbuf (&filenames) == -1) {
    pclose (fp);
    return NULL;
  }

  if (pclose (fp) != 0) {
    reply_with_perror ("pclose");
    free_stringslen (filenames.argv, filenames.size);
    return NULL;
  }

  return filenames.argv;
}

char *
do_initrd_cat (const char *path, const char *filename, size_t *size_r)
{
  char tmpdir[] = "/tmp/initrd-cat-XXXXXX";
  CLEANUP_FREE char *cmd = NULL;
  struct stat statbuf;
  int fd, r;
  char *ret = NULL;
  CLEANUP_FREE char *fullpath = NULL;

  if (mkdtemp (tmpdir) == NULL) {
    reply_with_perror ("mkdtemp");
    return NULL;
  }

  /* Extract file into temporary directory.  This may create subdirs.
   * It's also possible that this doesn't create anything at all
   * (eg. if the named file does not exist in the cpio archive) --
   * cpio is silent in this case.
   */
  /* "zcat /sysroot/<path> | cpio --quiet -id file", but paths must be quoted */
  if (asprintf_nowarn (&cmd, "cd %Q && zcat %R | cpio --quiet -id %Q",
                       tmpdir, path, filename) == -1) {
    reply_with_perror ("asprintf");
    rmdir (tmpdir);
    return NULL;
  }

  r = system (cmd);
  if (r == -1) {
    reply_with_perror ("command failed: %s", cmd);
    rmdir (tmpdir);
    return NULL;
  }
  if (WEXITSTATUS (r) != 0) {
    reply_with_perror ("command failed with return code %d",
                       WEXITSTATUS (r));
    rmdir (tmpdir);
    return NULL;
  }

  /* Construct the expected name of the extracted file. */
  if (asprintf (&fullpath, "%s/%s", tmpdir, filename) == -1) {
    reply_with_perror ("asprintf");
    rmdir (tmpdir);
    return NULL;
  }

  /* See if we got a file. */
  fd = open (fullpath, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("open: %s:%s", path, filename);
    rmdir (tmpdir);
    return NULL;
  }

  /* From this point, we know the file exists, so we require full
   * cleanup.
   */
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
    fprintf (stderr, "unlink: %s: %m\n", fullpath);
    /* non-fatal */
  }

  /* Remove the directories up to and including the temp directory. */
  do {
    char *p = strrchr (fullpath, '/');
    if (!p) break;
    *p = '\0';
    if (rmdir (fullpath) == -1) {
      fprintf (stderr, "rmdir: %s: %m\n", fullpath);
      /* non-fatal */
    }
  } while (STRNEQ (fullpath, tmpdir));

  return ret;
}
