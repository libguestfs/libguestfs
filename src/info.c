/* libguestfs
 * Copyright (C) 2012 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <limits.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static int run_qemu_img_info (guestfs_h *g, const char *filename, cmd_stdout_callback cb, void *data);

/* NB: For security reasons, the check_* callbacks MUST bail
 * after seeing the first line that matches /^backing file: /.  See:
 * https://lists.gnu.org/archive/html/qemu-devel/2012-09/msg00137.html
 * Eventually we should use the JSON output of qemu-img info.
 */

struct check_data {
  int stop, failed;
  union {
    char *ret;
    int reti;
    int64_t reti64;
  };
};

static void check_disk_format (guestfs_h *g, void *data, const char *line, size_t len);
static void check_disk_virtual_size (guestfs_h *g, void *data, const char *line, size_t len);
static void check_disk_has_backing_file (guestfs_h *g, void *data, const char *line, size_t len);

char *
guestfs__disk_format (guestfs_h *g, const char *filename)
{
  struct check_data data;

  memset (&data, 0, sizeof data);

  if (run_qemu_img_info (g, filename, check_disk_format, &data) == -1) {
    free (data.ret);
    return NULL;
  }

  if (data.ret == NULL)
    data.ret = safe_strdup (g, "unknown");

  return data.ret;
}

static void
check_disk_format (guestfs_h *g, void *datav, const char *line, size_t len)
{
  struct check_data *data = datav;
  const char *p;

  if (data->stop)
    return;

  if (STRPREFIX (line, "backing file: ")) {
    data->stop = 1;
    return;
  }

  if (STRPREFIX (line, "file format: ")) {
    p = &line[13];
    data->ret = safe_strdup (g, p);
    data->stop = 1;
  }
}

int64_t
guestfs__disk_virtual_size (guestfs_h *g, const char *filename)
{
  struct check_data data;

  memset (&data, 0, sizeof data);

  if (run_qemu_img_info (g, filename, check_disk_virtual_size, &data) == -1)
    return -1;

  if (data.failed)
    error (g, _("%s: cannot detect virtual size of disk image"), filename);

  return data.reti64;
}

static void
check_disk_virtual_size (guestfs_h *g, void *datav,
                         const char *line, size_t len)
{
  struct check_data *data = datav;
  const char *p;

  if (data->stop)
    return;

  if (STRPREFIX (line, "backing file: ")) {
    data->stop = 1;
    return;
  }

  if (STRPREFIX (line, "virtual size: ")) {
    /* "virtual size: 500M (524288000 bytes)\n" */
    p = &line[14];
    p = strchr (p, ' ');
    if (!p || p[1] != '(' || sscanf (&p[2], "%" SCNi64, &data->reti64) != 1)
      data->failed = 1;
    data->stop = 1;
  }
}

int
guestfs__disk_has_backing_file (guestfs_h *g, const char *filename)
{
  struct check_data data;

  memset (&data, 0, sizeof data);

  if (run_qemu_img_info (g, filename, check_disk_has_backing_file, &data) == -1)
    return -1;

  return data.reti;
}

static void
check_disk_has_backing_file (guestfs_h *g, void *datav,
                             const char *line, size_t len)
{
  struct check_data *data = datav;

  if (data->stop)
    return;

  if (STRPREFIX (line, "backing file: ")) {
    data->reti = 1;
    data->stop = 1;
  }
}

static int
run_qemu_img_info (guestfs_h *g, const char *filename,
                   cmd_stdout_callback fn, void *data)
{
  CLEANUP_FREE char *abs_filename = NULL;
  CLEANUP_FREE char *safe_filename = NULL;
  struct command *cmd;
  int r;

  if (guestfs___lazy_make_tmpdir (g) == -1)
    return -1;

  safe_filename = safe_asprintf (g, "%s/format.%d", g->tmpdir, ++g->unique);

  /* 'filename' must be an absolute path so we can link to it. */
  abs_filename = realpath (filename, NULL);
  if (abs_filename == NULL) {
    perrorf (g, "realpath");
    return -1;
  }

  if (symlink (abs_filename, safe_filename) == -1) {
    perrorf (g, "symlink");
    return -1;
  }

  cmd = guestfs___new_command (g);
  guestfs___cmd_add_arg (cmd, "qemu-img");
  guestfs___cmd_add_arg (cmd, "info");
  guestfs___cmd_add_arg (cmd, safe_filename);
  guestfs___cmd_set_stdout_callback (cmd, fn, data, 0);
  r = guestfs___cmd_run (cmd);
  guestfs___cmd_close (cmd);
  if (r == -1)
    return -1;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    error (g, _("qemu-img: %s: child process failed"), filename);
    return -1;
  }

  return 0;
}
