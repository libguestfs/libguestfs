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
#include <sys/types.h>
#include <sys/stat.h>
#include <libintl.h>
#include <unistd.h>

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

/* We need to make all tmpdir paths absolute because lots of places in
 * the code assume this.  Do it at the time we set the path or read
 * the environment variable (RHBZ#882417).
 */
static int
set_abs_path (guestfs_h *g, const char *tmpdir, char **tmpdir_ret)
{
  char *ret;
  struct stat statbuf;

  /* Free the old path, and set it to NULL so that if we fail below
   * we don't end up with a pointer to freed memory.
   */
  free (*tmpdir_ret);
  *tmpdir_ret = NULL;

  if (tmpdir == NULL)
    return 0;

  ret = realpath (tmpdir, NULL);
  if (ret == NULL) {
    perrorf (g, _("failed to set temporary directory: %s"), tmpdir);
    return -1;
  }

  if (stat (ret, &statbuf) == -1) {
    perrorf (g, _("failed to set temporary directory: %s"), tmpdir);
    return -1;
  }

  if (!S_ISDIR (statbuf.st_mode)) {
    error (g, _("temporary directory '%s' is not a directory"), tmpdir);
    return -1;
  }

  *tmpdir_ret = ret;
  return 0;
}

int
guestfs_int_set_env_tmpdir (guestfs_h *g, const char *tmpdir)
{
  return set_abs_path (g, tmpdir, &g->env_tmpdir);
}

int
guestfs_int_set_env_runtimedir (guestfs_h *g, const char *runtimedir)
{
  return set_abs_path (g, runtimedir, &g->env_runtimedir);
}

int
guestfs_impl_set_tmpdir (guestfs_h *g, const char *tmpdir)
{
  return set_abs_path (g, tmpdir, &g->int_tmpdir);
}

/* Note this actually calculates the tmpdir, so it never returns NULL. */
char *
guestfs_impl_get_tmpdir (guestfs_h *g)
{
  const char *str;

  if (g->int_tmpdir)
    str = g->int_tmpdir;
  else if (g->env_tmpdir)
    str = g->env_tmpdir;
  else
    str = "/tmp";

  return safe_strdup (g, str);
}

int
guestfs_impl_set_cachedir (guestfs_h *g, const char *cachedir)
{
  return set_abs_path (g, cachedir, &g->int_cachedir);
}

/* Note this actually calculates the cachedir, so it never returns NULL. */
char *
guestfs_impl_get_cachedir (guestfs_h *g)
{
  const char *str;

  if (g->int_cachedir)
    str = g->int_cachedir;
  else if (g->env_tmpdir)
    str = g->env_tmpdir;
  else
    str = "/var/tmp";

  return safe_strdup (g, str);
}

/* Note this actually calculates the sockdir, so it never returns NULL. */
char *
guestfs_impl_get_sockdir (guestfs_h *g)
{
  const char *str;
  uid_t euid = geteuid ();

  if (euid == 0) {
    /* Use /tmp exclusively for root, as otherwise qemu (running as
     * qemu.qemu when launched by libvirt) will not be able to access
     * the directory.
     */
    str = "/tmp";
  } else {
    if (g->env_runtimedir)
      str = g->env_runtimedir;
    else
      str = "/tmp";
  }

  return safe_strdup (g, str);
}

static int
lazy_make_tmpdir (guestfs_h *g, char *(*getdir) (guestfs_h *g), char **dest)
{
  if (!*dest) {
    CLEANUP_FREE char *tmpdir = getdir (g);
    char *tmppath = safe_asprintf (g, "%s/libguestfsXXXXXX", tmpdir);
    if (mkdtemp (tmppath) == NULL) {
      perrorf (g, _("%s: cannot create temporary directory"), tmppath);
      free (tmpdir);
      return -1;
    }
    /* Allow qemu (which may be running as qemu.qemu) to read in this
     * temporary directory; we are storing either sockets, or temporary
     * disks which qemu needs to access to.  (RHBZ#610880).
     * We do this only for root, as for normal users qemu will be run
     * under the same user.
     */
    if (geteuid () == 0 && chmod (tmppath, 0755) == -1) {
      perrorf (g, "chmod: %s", tmppath);
      free (tmppath);
      return -1;
    }
    *dest = tmppath;
  }
  return 0;
}

/* The g->tmpdir (per-handle temporary directory) is not created when
 * the handle is created.  Instead we create it lazily before the
 * first time it is used, or during launch.
 */
int
guestfs_int_lazy_make_tmpdir (guestfs_h *g)
{
  return lazy_make_tmpdir (g, guestfs_get_tmpdir, &g->tmpdir);
}

int
guestfs_int_lazy_make_sockdir (guestfs_h *g)
{
  return lazy_make_tmpdir (g, guestfs_get_sockdir, &g->sockdir);
}

/* Recursively remove a temporary directory.  If removal fails, just
 * return (it's a temporary directory so it'll eventually be cleaned
 * up by a temp cleaner).  This is done using "rm -rf" because that's
 * simpler and safer.
 */
void
guestfs_int_recursive_remove_dir (guestfs_h *g, const char *dir)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);

  guestfs_int_cmd_add_arg (cmd, "rm");
  guestfs_int_cmd_add_arg (cmd, "-rf");
  guestfs_int_cmd_add_arg (cmd, dir);
  ignore_value (guestfs_int_cmd_run (cmd));
}

void
guestfs_int_remove_tmpdir (guestfs_h *g)
{
  if (g->tmpdir)
    guestfs_int_recursive_remove_dir (g, g->tmpdir);
}

void
guestfs_int_remove_sockdir (guestfs_h *g)
{
  if (g->sockdir)
    guestfs_int_recursive_remove_dir (g, g->sockdir);
}
