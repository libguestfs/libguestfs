/* libguestfs - shared file editing
 * Copyright (C) 2009-2019 Red Hat Inc.
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

/**
 * This file implements common file editing in a range of utilities
 * including L<guestfish(1)>, L<virt-edit(1)>, L<virt-customize(1)>
 * and L<virt-builder(1)>.
 *
 * It contains the code for both interactive-(editor-)based editing
 * and non-interactive editing using Perl snippets.
 */

#include <config.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <locale.h>
#include <langinfo.h>
#include <libintl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <assert.h>
#include <utime.h>
#include <sys/wait.h>

#include "guestfs-utils.h"

#include "file-edit.h"

static int do_download (guestfs_h *g, const char *filename, char **tempfile);
static int do_upload (guestfs_h *g, const char *filename, const char *tempfile,
                      const char *backup_extension);
static char *generate_random_name (const char *filename);
static char *generate_backup_name (const char *filename,
                                   const char *backup_extension);

/**
 * Edit C<filename> using the specified C<editor> application.
 *
 * If C<backup_extension> is not null, then a copy of C<filename> is
 * saved with C<backup_extension> appended to its file name.
 *
 * If C<editor> is null, then the C<$EDITOR> environment variable will
 * be queried for the editor application, leaving C<vi> as fallback if
 * not set.
 *
 * Returns C<-1> for failure, C<0> on success, C<1> if the editor did
 * not change the file (e.g. the user closed the editor without
 * saving).
 */
int
edit_file_editor (guestfs_h *g, const char *filename, const char *editor,
                  const char *backup_extension, int verbose)
{
  CLEANUP_UNLINK_FREE char *tmpfilename = NULL;
  CLEANUP_FREE char *cmd = NULL;
  struct stat oldstat, newstat;
  int r;
  struct utimbuf times;

  if (editor == NULL) {
    editor = getenv ("EDITOR");
    if (editor == NULL)
      editor = "vi";
  }

  /* Download the file and write it to a temporary. */
  if (do_download (g, filename, &tmpfilename) == -1)
    return -1;

  /* Set the time back a few seconds on the original file.  This is so
   * that if the user is very fast at editing, or if EDITOR is an
   * automatic editor, then the edit might happen within the 1 second
   * granularity of mtime, and we would think the file hasn't changed.
   */
  if (stat (tmpfilename, &oldstat) == -1) {
    perror (tmpfilename);
    return -1;
  }

  times.actime = oldstat.st_atime - 5;
  times.modtime = oldstat.st_mtime - 5;
  if (utime (tmpfilename, &times) == -1) {
    perror ("utimes");
    return -1;
  }

  /* Get the old stat. */
  if (stat (tmpfilename, &oldstat) == -1) {
    perror (tmpfilename);
    return -1;
  }

  /* Edit it. */
  if (asprintf (&cmd, "%s %s", editor, tmpfilename) == -1) {
    perror ("asprintf");
    return -1;
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  r = system (cmd);
  if (r == -1 || WEXITSTATUS (r) != 0) {
    perror (cmd);
    return -1;
  }

  /* Get the new stat. */
  if (stat (tmpfilename, &newstat) == -1) {
    perror (tmpfilename);
    return -1;
  }

  /* Changed? */
  if (oldstat.st_ctime == newstat.st_ctime &&
      oldstat.st_size == newstat.st_size)
    return 1;

  if (do_upload (g, filename, tmpfilename, backup_extension) == -1)
    return -1;

  return 0;
}

/**
 * Edit C<filename> running the specified C<perl_expr> using Perl.
 *
 * If C<backup_extension> is not null, then a copy of C<filename> is
 * saved with C<backup_extension> appended to its file name.
 *
 * Returns C<-1> for failure, C<0> on success.
 */
int
edit_file_perl (guestfs_h *g, const char *filename, const char *perl_expr,
                const char *backup_extension, int verbose)
{
  CLEANUP_UNLINK_FREE char *tmpfilename = NULL;
  CLEANUP_FREE char *cmd = NULL;
  CLEANUP_FREE char *outfile = NULL;
  int r;

  /* Download the file and write it to a temporary. */
  if (do_download (g, filename, &tmpfilename) == -1)
    return -1;

  if (asprintf (&outfile, "%s.out", tmpfilename) == -1) {
    perror ("asprintf");
    return -1;
  }

  /* Pass the expression to Perl via the environment.  This sidesteps
   * any quoting problems with the already complex Perl command line.
   */
  setenv ("virt_edit_expr", perl_expr, 1);

  /* Call out to a canned Perl script. */
  if (asprintf (&cmd,
                "perl -e '"
                "$lineno = 0; "
                "$expr = $ENV{virt_edit_expr}; "
                "while (<STDIN>) { "
                "  $lineno++; "
                "  eval $expr; "
                "  die if $@; "
                "  print STDOUT $_ or die \"print: $!\"; "
                "} "
                "close STDOUT or die \"close: $!\"; "
                "' < %s > %s",
                tmpfilename, outfile) == -1) {
    perror ("asprintf");
    return -1;
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  r = system (cmd);
  if (r == -1 || WEXITSTATUS (r) != 0)
    return -1;

  if (rename (outfile, tmpfilename) == -1) {
    perror ("rename");
    return -1;
  }

  if (do_upload (g, filename, tmpfilename, backup_extension) == -1)
    return -1;

  return 0;
}

static int
do_download (guestfs_h *g, const char *filename, char **tempfile)
{
  CLEANUP_FREE char *tmpdir = guestfs_get_tmpdir (g);
  CLEANUP_UNLINK_FREE char *tmpfilename = NULL;
  char buf[256];
  int fd;

  /* Download the file and write it to a temporary. */
  if (asprintf (&tmpfilename, "%s/libguestfsXXXXXX", tmpdir) == -1) {
    perror ("asprintf");
    return -1;
  }

  fd = mkstemp (tmpfilename);
  if (fd == -1) {
    perror ("mkstemp");
    return -1;
  }

  snprintf (buf, sizeof buf, "/dev/fd/%d", fd);

  if (guestfs_download (g, filename, buf) == -1) {
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    perror (tmpfilename);
    return -1;
  }

  /* Hand over the temporary file. */
  *tempfile = tmpfilename;
  tmpfilename = NULL;

  return 0;
}

static int
do_upload (guestfs_h *g, const char *fn, const char *tempfile,
           const char *backup_extension)
{
  CLEANUP_FREE char *filename = NULL;
  CLEANUP_FREE char *newname = NULL;

  /* Resolve the file name and write to the actual target, since
   * that is the file it was opened earlier; otherwise, if it is
   * a symlink it will be overwritten by a regular file with the
   * new content.
   *
   * Theoretically realpath should work, but just check again
   * to be safe.
   */
  filename = guestfs_realpath (g, fn);
  if (filename == NULL)
    return -1;

  /* Upload to a new file in the same directory, so if it fails we
   * don't end up with a partially written file.  Give the new file
   * a completely random name so we have only a tiny chance of
   * overwriting some existing file.
   */
  newname = generate_random_name (filename);
  if (!newname)
    return -1;

  /* Write new content. */
  if (guestfs_upload (g, tempfile, newname) == -1)
    return -1;

  /* Set the permissions, UID, GID and SELinux context of the new
   * file to match the old file (RHBZ#788641).
   */
  if (guestfs_copy_attributes (g, filename, newname,
			       GUESTFS_COPY_ATTRIBUTES_ALL, 1, -1) == -1)
    return -1;

  /* Backup or overwrite the file. */
  if (backup_extension) {
    CLEANUP_FREE char *backupname = NULL;

    backupname = generate_backup_name (filename, backup_extension);
    if (backupname == NULL)
      return -1;

    if (guestfs_mv (g, filename, backupname) == -1)
      return -1;
  }
  if (guestfs_mv (g, newname, filename) == -1)
    return -1;

  return 0;
}

static char *
generate_random_name (const char *filename)
{
  char *ret, *p;

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
   * output buffer to write 8 random characters here plus the
   * trailing \0.
   */
  if (guestfs_int_random_string (p, 8) == -1) {
    perror ("guestfs_int_random_string");
    free (ret);
    return NULL;
  }

  return ret; /* caller will free */
}

static char *
generate_backup_name (const char *filename, const char *backup_extension)
{
  char *ret;

  assert (backup_extension != NULL);

  if (asprintf (&ret, "%s%s", filename, backup_extension) == -1) {
    perror ("asprintf");
    return NULL;
  }

  return ret; /* caller will free */
}
