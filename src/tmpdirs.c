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

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

int
guestfs__set_tmpdir (guestfs_h *g, const char *tmpdir)
{
  free (g->int_tmpdir);
  g->int_tmpdir = tmpdir ? safe_strdup (g, tmpdir) : NULL;
  return 0;
}

/* Note this actually calculates the tmpdir, so it never returns NULL. */
char *
guestfs__get_tmpdir (guestfs_h *g)
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
guestfs__set_cachedir (guestfs_h *g, const char *cachedir)
{
  free (g->int_cachedir);
  g->int_cachedir = cachedir ? safe_strdup (g, cachedir) : NULL;
  return 0;
}

/* Note this actually calculates the cachedir, so it never returns NULL. */
char *
guestfs__get_cachedir (guestfs_h *g)
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
guestfs___lazy_make_tmpdir (guestfs_h *g)
{
  if (!g->tmpdir) {
    TMP_TEMPLATE_ON_STACK (g, dir_template);
    g->tmpdir = safe_strdup (g, dir_template);
    if (mkdtemp (g->tmpdir) == NULL) {
      perrorf (g, _("%s: cannot create temporary directory"), dir_template);
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
guestfs___recursive_remove_dir (guestfs_h *g, const char *dir)
{
  struct command *cmd;

  cmd = guestfs___new_command (g);
  guestfs___cmd_add_arg (cmd, "rm");
  guestfs___cmd_add_arg (cmd, "-rf");
  guestfs___cmd_add_arg (cmd, dir);
  /* Ignore failures. */
  guestfs___cmd_run (cmd);
  guestfs___cmd_close (cmd);
}

void
guestfs___remove_tmpdir (guestfs_h *g)
{
  if (g->tmpdir)
    guestfs___recursive_remove_dir (g, g->tmpdir);
}
