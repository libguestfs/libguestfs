/* guestfish - guest filesystem shell
 * Copyright (C) 2009-2023 Red Hat Inc.
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
 * guestfish C<edit> command, suggested by Ján Ondrej.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <inttypes.h>
#include <libintl.h>

#include "fish.h"
#include "file-edit.h"

int
run_edit (const char *cmd, size_t argc, char *argv[])
{
  const char *editor;
  CLEANUP_FREE char *remotefilename = NULL;
  int r;

  if (argc != 1) {
    fprintf (stderr, _("use '%s filename' to edit a file\n"), cmd);
    return -1;
  }

  /* Choose an editor. */
  if (STRCASEEQ (cmd, "vi"))
    editor = "vi";
  else if (STRCASEEQ (cmd, "emacs"))
    editor = "emacs -nw";
  else
    editor = NULL; /* use $EDITOR */

  /* Handle 'win:...' prefix. */
  remotefilename = win_prefix (argv[0]);
  if (remotefilename == NULL)
    return -1;

  r = edit_file_editor (g, remotefilename, editor, NULL, 0 /* not verbose */);

  return r == -1 ? -1 : 0;
}
