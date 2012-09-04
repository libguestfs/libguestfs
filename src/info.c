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
#include <limits.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

static int run_qemu_img_info (guestfs_h *g, const char *filename, int (*fn) (guestfs_h *g, char *line, void *data), void *data);
static int check_disk_format (guestfs_h *h, char *line, void *data);

char *
guestfs__disk_format (guestfs_h *g, const char *filename)
{
  char *ret = NULL;

  if (run_qemu_img_info (g, filename, check_disk_format, &ret) == -1) {
    free (ret);
    return NULL;
  }

  if (ret == NULL)
    ret = safe_strdup (g, "unknown");

  return ret;
}

static int
check_disk_format (guestfs_h *g, char *line, void *retpv)
{
  char **retp = retpv;
  char *p;
  size_t n;

  if (STRPREFIX (line, "file format: ")) {
    p = &line[13];
    n = strlen (p);
    if (n > 0 && p[n-1] == '\n')
      p[n-1] = '\0';
    *retp = safe_strdup (g, p);
    return 0;                   /* finish processing */
  }

  return 1;                     /* continue processing */
}

/* It's hard to use 'qemu-img info' safely.  See:
 * https://lists.gnu.org/archive/html/qemu-devel/2012-09/msg00137.html
 * Eventually we should switch to the JSON output format, when it
 * becomes available.  In the meantime: (1) make a symlink to ensure
 * we control the input filename, and (2) bail parsing as soon as
 * /^backing file: / is seen in the input.
 */
static int
run_qemu_img_info (guestfs_h *g, const char *filename,
                   int (*fn) (guestfs_h *g, char *line, void *data),
                   void *data)
{
  char *abs_filename = NULL;
  char *safe_filename = NULL;
  pid_t pid = 0;
  int fd[2] = { -1, -1 };
  FILE *fp = NULL;
  char *line = NULL;
  size_t len;
  int r;

  if (guestfs___lazy_make_tmpdir (g) == -1)
    return -1;

  safe_filename = safe_asprintf (g, "%s/format.%d", g->tmpdir, ++g->unique);

  /* 'filename' must be an absolute path so we can link to it. */
  abs_filename = realpath (filename, NULL);
  if (abs_filename == NULL) {
    perrorf (g, "realpath");
    goto error;
  }

  if (symlink (abs_filename, safe_filename) == -1) {
    perrorf (g, "symlink");
    goto error;
  }

  if (pipe2 (fd, O_CLOEXEC) == -1) {
    perrorf (g, "pipe2");
    goto error;
  }

  pid = fork ();
  if (pid == -1) {
    perrorf (g, "fork");
    goto error;
  }

  if (pid == 0) {               /* child */
    close (fd[0]);
    dup2 (fd[1], 1);
    close (fd[1]);

    setenv ("LANG", "C", 1);

    /* XXX stderr to event log */

    execlp ("qemu-img", "qemu-img", "info", safe_filename, NULL);
    perror ("could not execute 'qemu-img info' command");
    _exit (EXIT_FAILURE);
  }

  close (fd[1]);
  fd[1] = -1;

  fp = fdopen (fd[0], "r");
  if (fp == NULL) {
    perrorf (g, "fdopen: qemu-img info");
    goto error;
  }
  fd[0] = -1;

  while (getline (&line, &len, fp) != -1) {
    r = fn (g, line, data);
    if (r == -1)                /* error */
      goto error;
    if (r == 0)                 /* finished processing */
      break;

    /* This is for security reasons, see comment above. */
    if (STRPREFIX (line, "backing file: "))
      break;
  }

  if (fclose (fp) == -1) { /* also closes fd[0] */
    perrorf (g, "fclose");
    fp = NULL;
    goto error;
  }
  fp = NULL;

  if (waitpid (pid, &r, 0) == -1) {
    perrorf (g, "waitpid");
    pid = 0;
    goto error;
  }
  pid = 0;

  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    error (g, "qemu-img: %s: child process failed", filename);
    goto error;
  }

  free (safe_filename);
  free (abs_filename);
  free (line);
  return 0;

 error:
  if (fd[0] >= 0)
    close (fd[0]);
  if (fd[1] >= 0)
    close (fd[1]);
  if (fp != NULL)
    fclose (fp);
  if (pid > 0)
    waitpid (pid, NULL, 0);

  free (safe_filename);
  free (abs_filename);
  free (line);

  return -1;
}
