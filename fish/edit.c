/* guestfish - the filesystem interactive shell
 * Copyright (C) 2009-2012 Red Hat Inc.
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
#include <assert.h>

#include "fish.h"

static char *generate_random_name (const char *filename);
static int copy_attributes (const char *src, const char *dest);

/* guestfish edit command, suggested by Ján Ondrej, implemented by RWMJ */

int
run_edit (const char *cmd, size_t argc, char *argv[])
{
  TMP_TEMPLATE_ON_STACK (filename);
  char buf[256];
  const char *editor;
  char *remotefilename, *newname;
  struct stat oldstat, newstat;
  int r, fd;

  if (argc != 1) {
    fprintf (stderr, _("use '%s filename' to edit a file\n"), cmd);
    goto error0;
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
    goto error0;

  /* Download the file and write it to a temporary. */
  fd = mkstemp (filename);
  if (fd == -1) {
    perror ("mkstemp");
    goto error1;
  }

  snprintf (buf, sizeof buf, "/dev/fd/%d", fd);

  if (guestfs_download (g, remotefilename, buf) == -1) {
    close (fd);
    goto error2;
  }

  if (close (fd) == -1) {
    perror (filename);
    goto error2;
  }

  /* Get the old stat. */
  if (stat (filename, &oldstat) == -1) {
    perror (filename);
    goto error2;
  }

  /* Edit it. */
  /* XXX Safe? */
  snprintf (buf, sizeof buf, "%s %s", editor, filename);

  r = system (buf);
  if (r != 0) {
    perror (buf);
    goto error2;
  }

  /* Get the new stat. */
  if (stat (filename, &newstat) == -1) {
    perror (filename);
    goto error2;
  }

  /* Changed? */
  if (oldstat.st_ctime == newstat.st_ctime &&
      oldstat.st_size == newstat.st_size) {
    unlink (filename);
    free (remotefilename);
    return 0;
  }

  /* Upload to a new file in the same directory, so if it fails we
   * don't end up with a partially written file.  Give the new file
   * a completely random name so we have only a tiny chance of
   * overwriting some existing file.
   */
  newname = generate_random_name (remotefilename);
  if (!newname)
    goto error2;

  /* Write new content. */
  if (guestfs_upload (g, filename, newname) == -1)
    goto error3;

  /* Set the permissions, UID, GID and SELinux context of the new
   * file to match the old file (RHBZ#788641).
   */
  if (copy_attributes (remotefilename, newname) == -1)
    goto error3;

  if (guestfs_mv (g, newname, remotefilename) == -1)
    goto error3;

  free (newname);
  unlink (filename);
  free (remotefilename);
  return 0;

 error3:
  free (newname);
 error2:
  unlink (filename);
 error1:
  free (remotefilename);
 error0:
  return -1;
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

static int
copy_attributes (const char *src, const char *dest)
{
  struct guestfs_stat *stat;
  int has_linuxxattrs;
  char *selinux_context = NULL;
  size_t selinux_context_size;

  has_linuxxattrs = feature_available (g, "linuxxattrs");

  /* Get the mode. */
  stat = guestfs_stat (g, src);
  if (stat == NULL)
    return -1;

  /* Get the SELinux context.  XXX Should we copy over other extended
   * attributes too?
   */
  if (has_linuxxattrs) {
    guestfs_error_handler_cb old_error_cb;
    void *old_error_data;
    old_error_cb = guestfs_get_error_handler (g, &old_error_data);
    guestfs_set_error_handler (g, NULL, NULL);

    selinux_context = guestfs_getxattr (g, src, "security.selinux",
                                        &selinux_context_size);
    /* selinux_context could be NULL.  This isn't an error. */

    guestfs_set_error_handler (g, old_error_cb, old_error_data);
  }

  /* Set the permissions (inc. sticky and set*id bits), UID, GID. */
  if (guestfs_chmod (g, stat->mode & 07777, dest) == -1) {
    guestfs_free_stat (stat);
    return -1;
  }
  if (guestfs_chown (g, stat->uid, stat->gid, dest) == -1) {
    guestfs_free_stat (stat);
    return -1;
  }
  guestfs_free_stat (stat);

  /* Set the SELinux context. */
  if (has_linuxxattrs && selinux_context) {
    if (guestfs_setxattr (g, "security.selinux", selinux_context,
                          (int) selinux_context_size, dest) == -1) {
      free (selinux_context);
      return -1;
    }
  }
  free (selinux_context);

  return 0;
}
