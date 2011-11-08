/* guestfish - the filesystem interactive shell
 * Copyright (C) 2010-2011 Red Hat Inc.
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
#include <signal.h>
#include <string.h>
#include <sys/wait.h>

#include "fish.h"

/* guestfish man command */

int
run_man (const char *cmd, size_t argc, char *argv[])
{
  if (argc != 0) {
    fprintf (stderr, _("use 'man' without parameters to open the manual\n"));
    return -1;
  }

  /* We have to restore SIGPIPE to the default action around the
   * external 'man' command to avoid the warning 'gzip: stdout: Broken pipe'.
   */
  struct sigaction sa, old_sa;
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = SIG_DFL;
  sigaction (SIGPIPE, &sa, &old_sa);

  int r = system ("man 1 guestfish");

  sigaction (SIGPIPE, &old_sa, NULL);

  if (r != 0)
    return -1;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    fprintf (stderr, _("the external 'man' program failed\n"));
    return -1;
  }

  return 0;
}
