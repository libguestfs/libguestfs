/* guestfish - the filesystem interactive shell
 * Copyright (C) 2010-2012 Red Hat Inc.
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
#include <limits.h>
#include <libintl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include "fish.h"

struct fd_pid {
  int fd;                       /* -1 == error */
  pid_t pid;
};

static struct fd_pid make_tar_from_local (const char *local);
static struct fd_pid make_tar_output (const char *local, const char *basename);
static int split_path (char *buf, size_t buf_size, const char *path, const char **dirname, const char **basename);

int
run_copy_in (const char *cmd, size_t argc, char *argv[])
{
  if (argc < 2) {
    fprintf (stderr,
             _("use 'copy-in <local> [<local>...] <remotedir>' to copy files into the image\n"));
    return -1;
  }

  /* Remote directory is always the last arg. */
  char *remote = argv[argc-1];

  /* Allow win: prefix on remote. */
  remote = win_prefix (remote);
  if (remote == NULL)
    return -1;

  int nr_locals = argc-1;

  int remote_is_dir = guestfs_is_dir (g, remote);
  if (remote_is_dir == -1) {
    free (remote);
    return -1;
  }

  if (!remote_is_dir) {
    fprintf (stderr, _("copy-in: target '%s' is not a directory\n"), remote);
    free (remote);
    return -1;
  }

  /* Upload each local one at a time using tar-in. */
  int i;
  for (i = 0; i < nr_locals; ++i) {
    struct fd_pid fdpid = make_tar_from_local (argv[i]);
    if (fdpid.fd == -1) {
      free (remote);
      return -1;
    }

    char fdbuf[64];
    snprintf (fdbuf, sizeof fdbuf, "/dev/fd/%d", fdpid.fd);

    int r = guestfs_tar_in (g, fdbuf, remote);

    if (close (fdpid.fd) == -1) {
      perror ("close (tar-from-local subprocess)");
      r = -1;
    }

    int status;
    if (waitpid (fdpid.pid, &status, 0) == -1) {
      perror ("wait (tar-from-local subprocess)");
      free (remote);
      return -1;
    }
    if (!(WIFEXITED (status) && WEXITSTATUS (status) == 0)) {
      free (remote);
      return -1;
    }

    if (r == -1) {
      free (remote);
      return -1;
    }
  }

  free (remote);

  return 0;
}

static void tar_create (const char *dir, const char *path) __attribute__((noreturn));

/* This creates a subprocess which feeds a tar file back to the
 * main guestfish process.
 */
static struct fd_pid
make_tar_from_local (const char *local)
{
  int fd[2];
  struct fd_pid r = { .fd = -1 };

  if (pipe (fd) == -1) {
    perror ("pipe");
    return r;
  }

  r.pid = fork ();
  if (r.pid == -1) {
    perror ("fork");
    return r;
  }

  if (r.pid > 0) {              /* Parent */
    close (fd[1]);
    r.fd = fd[0];
    return r;
  }

  /* Child. */
  close (fd[0]);
  dup2 (fd[1], 1);
  close (fd[1]);

  char buf[PATH_MAX];
  const char *dirname, *basename;
  if (split_path (buf, sizeof buf, local, &dirname, &basename) == -1)
    _exit (EXIT_FAILURE);

  tar_create (dirname, basename);
}

/* Split path into directory name and base name, using the buffer
 * provided as a working area.  If there is no directory name
 * (eg. path == "/") then this can return dirname as NULL.
 */
static int
split_path (char *buf, size_t buf_size,
            const char *path, const char **dirname, const char **basename)
{
  size_t len = strlen (path);
  if (len == 0 || len > buf_size - 1) {
    fprintf (stderr, _("error: argument is zero length or longer than maximum permitted\n"));
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

static void
tar_create (const char *dir, const char *path)
{
  if (dir)
    execlp ("tar", "tar", "-C", dir, "-cf", "-", path, NULL);
  else
    execlp ("tar", "tar", "-cf", "-", path, NULL);

  perror ("execlp: tar");
  _exit (EXIT_FAILURE);
}

int
run_copy_out (const char *cmd, size_t argc, char *argv[])
{
  if (argc < 2) {
    fprintf (stderr,
             _("use 'copy-out <remote> [<remote>...] <localdir>' to copy files out of the image\n"));
    return -1;
  }

  /* Local directory is always the last arg. */
  const char *local = argv[argc-1];
  int nr_remotes = argc-1;

  struct stat statbuf;
  if (stat (local, &statbuf) == -1 ||
      ! (S_ISDIR (statbuf.st_mode))) {
    fprintf (stderr, _("copy-out: target '%s' is not a directory\n"), local);
    return -1;
  }

  /* Download each remote one at a time using tar-out. */
  int i, r;
  for (i = 0; i < nr_remotes; ++i) {
    char *remote = argv[i];

    /* Allow win:... prefix on remotes. */
    remote = win_prefix (remote);
    if (remote == NULL)
      return -1;

    /* If the remote is a file, download it.  If it's a directory,
     * create the directory in local first before using tar-out.
     */
    r = guestfs_is_file (g, remote);
    if (r == -1) {
      free (remote);
      return -1;
    }
    if (r == 1) {               /* is file */
      char buf[PATH_MAX];
      const char *basename;
      if (split_path (buf, sizeof buf, remote, NULL, &basename) == -1) {
        free (remote);
        return -1;
      }

      char filename[PATH_MAX];
      snprintf (filename, sizeof filename, "%s/%s", local, basename);
      if (guestfs_download (g, remote, filename) == -1) {
        free (remote);
        return -1;
      }
    }
    else {                      /* not a regular file */
      r = guestfs_is_dir (g, remote);
      if (r == -1) {
        free (remote);
        return -1;
      }

      if (r == 0) {
        fprintf (stderr, _("copy-out: '%s' is not a file or directory\n"),
                 remote);
        free (remote);
        return -1;
      }

      char buf[PATH_MAX];
      const char *basename;
      if (split_path (buf, sizeof buf, remote, NULL, &basename) == -1) {
        free (remote);
        return -1;
      }

      struct fd_pid fdpid = make_tar_output (local, basename);
      if (fdpid.fd == -1) {
        free (remote);
        return -1;
      }

      char fdbuf[64];
      snprintf (fdbuf, sizeof fdbuf, "/dev/fd/%d", fdpid.fd);

      int r = guestfs_tar_out (g, remote, fdbuf);

      if (close (fdpid.fd) == -1) {
        perror ("close (tar-output subprocess)");
        free (remote);
        r = -1;
      }

      int status;
      if (waitpid (fdpid.pid, &status, 0) == -1) {
        perror ("wait (tar-output subprocess)");
        free (remote);
        return -1;
      }
      if (!(WIFEXITED (status) && WEXITSTATUS (status) == 0)) {
        free (remote);
        return -1;
      }

      if (r == -1) {
        free (remote);
        return -1;
      }
    }

    free (remote);
  }

  return 0;
}

/* This creates a subprocess which takes a tar file from the main
 * guestfish process and unpacks it into the 'local/basename'
 * directory.
 */
static struct fd_pid
make_tar_output (const char *local, const char *basename)
{
  int fd[2];
  struct fd_pid r = { .fd = -1 };

  if (pipe (fd) == -1) {
    perror ("pipe");
    return r;
  }

  r.pid = fork ();
  if (r.pid == -1) {
    perror ("fork");
    return r;
  }

  if (r.pid > 0) {              /* Parent */
    close (fd[0]);
    r.fd = fd[1];
    return r;
  }

  /* Child. */
  close (fd[1]);
  dup2 (fd[0], 0);
  close (fd[0]);

  if (chdir (local) == -1) {
    perror (local);
    _exit (EXIT_FAILURE);
  }

  mkdir (basename, 0777);

  if (chdir (basename) == -1) {
    perror (basename);
    _exit (EXIT_FAILURE);
  }

  execlp ("tar", "tar", "-xf", "-", NULL);
  perror ("execlp: tar");
  _exit (EXIT_FAILURE);
}
