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
#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <sys/types.h>
#include <sys/stat.h>

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

/* The g->tmpdir (per-handle temporary directory) is not created when
 * the handle is created.  Instead we create it lazily before the
 * first time it is used, or during launch.
 */
int
guestfs_int_lazy_make_tmpdir (guestfs_h *g)
{
  if (!g->tmpdir) {
    CLEANUP_FREE char *tmpdir = guestfs_get_tmpdir (g);
    g->tmpdir = safe_asprintf (g, "%s/libguestfsXXXXXX", tmpdir);
    if (mkdtemp (g->tmpdir) == NULL) {
      perrorf (g, _("%s: cannot create temporary directory"), g->tmpdir);
      free (g->tmpdir);
      g->tmpdir = NULL;
      return -1;
    }
  }
  return 0;
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
