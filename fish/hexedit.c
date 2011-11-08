/* guestfish - the filesystem interactive shell
 * Copyright (C) 2010 Red Hat Inc.
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

#define MAX_DOWNLOAD_SIZE (16 * 1024 * 1024)
#define MAX_DOWNLOAD_SIZE_TEXT "16MB"

static off_t get_size (const char *filename);

int
run_hexedit (const char *cmd, size_t argc, char *argv[])
{
  if (argc < 1 || argc > 3) {
    fprintf (stderr, _("hexedit (device|filename) [max | start max]\n"));
    return -1;
  }

  const char *filename = argv[0];
  off_t size = get_size (filename);
  if (size == -1)
    return -1;

  if (size == 0) {
    fprintf (stderr,
             _("hexedit: %s is a zero length file or device\n"), filename);
    return -1;
  }

  off_t start;
  off_t max;

  if (argc == 1) {              /* hexedit device */
    /* Check we're not going to download a huge file. */
    if (size > MAX_DOWNLOAD_SIZE) {
      fprintf (stderr,
         _("hexedit: %s is larger than %s. You must supply a limit using\n"
           "  'hexedit %s <max>' (eg. 'hexedit %s 1M') or a range using\n"
           "  'hexedit %s <start> <max>'.\n"),
               filename, MAX_DOWNLOAD_SIZE_TEXT,
               filename, filename,
               filename);
      return -1;
    }

    start = 0;
    max = size;
  }
  else {
    if (argc == 3) {            /* hexedit device start max */
      if (parse_size (argv[1], &start) == -1)
        return -1;
      if (parse_size (argv[2], &max) == -1)
        return -1;
    } else {                    /* hexedit device max */
      start = 0;
      if (parse_size (argv[1], &max) == -1)
        return -1;
    }

    if (start + max > size)
      max = size - start;
  }

  if (max <= 0) {
    fprintf (stderr, _("hexedit: invalid range\n"));
    return -1;
  }

  /* Download the requested range from the remote file|device into a
   * local temporary file.
   */
  const char *editor;
  int r;
  struct stat oldstat, newstat;
  char buf[BUFSIZ];
  TMP_TEMPLATE_ON_STACK (tmp);
  int fd = mkstemp (tmp);
  if (fd == -1) {
    perror ("mkstemp");
    return -1;
  }

  /* Choose an editor. */
  editor = getenv ("HEXEDITOR");
  if (editor == NULL)
    editor = "hexedit";

  snprintf (buf, sizeof buf, "/dev/fd/%d", fd);

  if (guestfs_download_offset (g, filename, buf, start, max) == -1) {
    unlink (tmp);
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    unlink (tmp);
    return -1;
  }

  /* Get the old stat. */
  if (stat (tmp, &oldstat) == -1) {
    perror (tmp);
    unlink (tmp);
    return -1;
  }

  /* Edit it. */
  snprintf (buf, sizeof buf, "%s %s", editor, tmp);

  r = system (buf);
  if (r != 0) {
    perror (buf);
    unlink (tmp);
    return -1;
  }

  /* Get the new stat. */
  if (stat (tmp, &newstat) == -1) {
    perror (tmp);
    unlink (tmp);
    return -1;
  }

  /* Changed? */
  if (oldstat.st_ctime == newstat.st_ctime &&
      oldstat.st_size == newstat.st_size) {
    unlink (tmp);
    return 0;
  }

  /* Write new content. */
  if (guestfs_upload_offset (g, tmp, filename, start) == -1) {
    unlink (tmp);
    return -1;
  }

  unlink (tmp);
  return 0;
}

/* Get the size of the file or block device. */
static off_t
get_size (const char *filename)
{
  int64_t size;

  if (STRPREFIX (filename, "/dev/")) {
    size = guestfs_blockdev_getsize64 (g, filename);
    if (size == -1)
      return -1;
  }
  else {
    size = guestfs_filesize (g, filename);
    if (size == -1)
      return -1;
  }

  /* This case should be safe because we always compile with
   * 64 bit file offsets.
   */
  return (off_t) size;
}
