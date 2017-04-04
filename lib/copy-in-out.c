/* libguestfs
 * Copyright (C) 2015 Red Hat Inc.
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
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <errno.h>
#include <string.h>
#include <libintl.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

static int split_path (guestfs_h *g, char *buf, size_t buf_size, const char *path, const char **dirname, const char **basename);

int
guestfs_impl_copy_in (guestfs_h *g,
                      const char *localpath, const char *remotedir)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int fd;
  int r;
  char fdbuf[64];
  const size_t buf_len = strlen (localpath) + 1;
  CLEANUP_FREE char *buf = safe_malloc (g, buf_len);
  const char *dirname, *basename;
  struct stat statbuf;

  if (stat (localpath, &statbuf) == -1) {
    error (g, _("source ‘%s’ does not exist (or cannot be read)"), localpath);
    return -1;
  }

  const int remote_is_dir = guestfs_is_dir (g, remotedir);
  if (remote_is_dir == -1)
    return -1;

  if (!remote_is_dir) {
    error (g, _("target ‘%s’ is not a directory"), remotedir);
    return -1;
  }

  if (split_path (g, buf, buf_len, localpath, &dirname, &basename) == -1)
    return -1;

  guestfs_int_cmd_add_arg (cmd, "tar");
  if (dirname) {
    guestfs_int_cmd_add_arg (cmd, "-C");
    guestfs_int_cmd_add_arg (cmd, dirname);
  }
  guestfs_int_cmd_add_arg (cmd, "-cf");
  guestfs_int_cmd_add_arg (cmd, "-");
  guestfs_int_cmd_add_arg (cmd, basename);

  guestfs_int_cmd_clear_capture_errors (cmd);

  fd = guestfs_int_cmd_pipe_run (cmd, "r");
  if (fd == -1)
    return -1;

  snprintf (fdbuf, sizeof fdbuf, "/dev/fd/%d", fd);

  r = guestfs_tar_in (g, fdbuf, remotedir);

  if (close (fd) == -1) {
    perrorf (g, "close (tar subprocess)");
    return -1;
  }

  r = guestfs_int_cmd_pipe_wait (cmd);
  if (r == -1)
    return -1;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    CLEANUP_FREE char *errors = guestfs_int_cmd_get_pipe_errors (cmd);
    if (errors == NULL)
      return -1;
    error (g, "tar subprocess failed: %s", errors);
    return -1;
  }

  return 0;
}

struct copy_out_child_data {
  const char *localdir;
  const char *basename;
};

static int
child_setup (guestfs_h *g, void *data)
{
  struct copy_out_child_data d = *(struct copy_out_child_data *) data;

  if (chdir (d.localdir) == -1) {
    perror (d.localdir);
    return -1;
  }

  if (mkdir (d.basename, 0777) == -1 && errno != EEXIST) {
    perror (d.basename);
    return -1;
  }

  if (chdir (d.basename) == -1) {
    perror (d.basename);
    return -1;
  }

  return 0;
}

int
guestfs_impl_copy_out (guestfs_h *g,
                       const char *remotepath, const char *localdir)
{
  struct stat statbuf;
  int r;

  if (stat (localdir, &statbuf) == -1 ||
      ! (S_ISDIR (statbuf.st_mode))) {
    error (g, _("target ‘%s’ is not a directory"), localdir);
    return -1;
  }

  /* If the remote is a file, download it.  If it's a directory,
   * create the directory in localdir first before using tar-out.
   */
  r = guestfs_is_file (g, remotepath);
  if (r == -1)
    return -1;

  if (r == 1) {               /* is file */
    CLEANUP_FREE char *filename = NULL;
    const size_t buf_len = strlen (remotepath) + 1;
    CLEANUP_FREE char *buf = safe_malloc (g, buf_len);
    const char *basename;

    if (split_path (g, buf, buf_len, remotepath, NULL, &basename) == -1)
      return -1;

    if (asprintf (&filename, "%s/%s", localdir, basename) == -1) {
      perrorf (g, "asprintf");
      return -1;
    }
    if (guestfs_download (g, remotepath, filename) == -1)
      return -1;
  } else {                    /* not a regular file */
    CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
    struct copy_out_child_data data;
    char fdbuf[64];
    int fd;

    r = guestfs_is_dir (g, remotepath);
    if (r == -1)
      return -1;

    if (r == 0) {
      error (g, _("‘%s’ is not a file or directory"), remotepath);
      return -1;
    }

    const size_t buf_len = strlen (remotepath) + 1;
    CLEANUP_FREE char *buf = safe_malloc (g, buf_len);
    const char *basename;
    if (split_path (g, buf, buf_len, remotepath, NULL, &basename) == -1)
      return -1;

    /* RHBZ#845522: If remotepath == "/" then basename would be an empty
     * string.  Replace it with "." so that make_tar_output writes
     * to "localdir/."
     */
    if (STREQ (basename, ""))
      basename = ".";

    data.localdir = localdir;
    data.basename = basename;

    guestfs_int_cmd_set_child_callback (cmd, &child_setup, &data);

    guestfs_int_cmd_add_arg (cmd, "tar");
    guestfs_int_cmd_add_arg (cmd, "-xf");
    guestfs_int_cmd_add_arg (cmd, "-");

    guestfs_int_cmd_clear_capture_errors (cmd);

    fd = guestfs_int_cmd_pipe_run (cmd, "w");
    if (fd == -1)
      return -1;

    snprintf (fdbuf, sizeof fdbuf, "/dev/fd/%d", fd);

    r = guestfs_tar_out (g, remotepath, fdbuf);

    if (close (fd) == -1) {
      perrorf (g, "close (tar-output subprocess)");
      return -1;
    }

    r = guestfs_int_cmd_pipe_wait (cmd);
    if (r == -1)
      return -1;
    if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
      CLEANUP_FREE char *errors = guestfs_int_cmd_get_pipe_errors (cmd);
      if (errors == NULL)
        return -1;
      error (g, "tar subprocess failed: %s", errors);
      return -1;
    }
  }

  return 0;
}

/* Split path into directory name and base name, using the buffer
 * provided as a working area.  If there is no directory name
 * (eg. path == "/") then this can return dirname as NULL.
 */
static int
split_path (guestfs_h *g, char *buf, size_t buf_size,
            const char *path, const char **dirname, const char **basename)
{
  size_t len = strlen (path);
  if (len == 0 || len > buf_size - 1) {
    error (g, _("error: argument is zero length or longer than maximum permitted"));
    return -1;
  }

  strcpy (buf, path);

  if (len >= 2 && buf[len-1] == '/') {
    buf[len-1] = '\0';
    len--;
  }

  char *p = strrchr (buf, '/');
  if (p && p > buf) {           /* "foo/bar" */
    *p = '\0';
    p++;
    if (dirname) *dirname = buf;
    if (basename) *basename = p;
  } else if (p && p == buf) {   /* "/foo" */
    if (dirname) *dirname = "/";
    if (basename) *basename = buf+1;
  } else {
    if (dirname) *dirname = NULL;
    if (basename) *basename = buf;
  }

  return 0;
}
