/* guestfish - guest filesystem shell
 * Copyright (C) 2010-2023 Red Hat Inc.
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
 * The file implements the guestfish C<help> command.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libintl.h>

#include "fish.h"

/**
 * The C<help> command.
 *
 * This used to just list all commands, but that's not very useful.
 * Instead display some useful context-sensitive help.  This could be
 * improved if we knew how many drives had been added already, and
 * whether anything was mounted.
 */
int
display_help (const char *cmd, size_t argc, char *argv[])
{
  if (argc == 0) {
    if (guestfs_is_config (g))
      printf (_(
"Add disk images to examine using the ‘-a’ or ‘-d’ options, or the ‘add’\n"
"command.\n"
"Or create a new disk image using ‘-N’, or the ‘alloc’ or ‘sparse’ commands.\n"
"Once you have done this, use the ‘run’ command.\n"
                ));
    else
      printf (_(
"Find out what filesystems are available using ‘list-filesystems’ and then\n"
"mount them to examine or modify the contents using ‘mount-ro’ or\n"
"‘mount’.\n"
                ));

    printf ("\n");

    printf (_(
"For more information about a command, use ‘help cmd’.\n"
"\n"
"To read the manual, type ‘man’.\n"
              ));

    printf ("\n");

    return 0;
  }
  else if (argc == 1) {
    if (STREQ (argv[0], "--list") || STREQ (argv[0], "-l")) {
      /* List all commands. */
      list_commands ();
      return 0;
    }
    else
      return display_command (argv[0]);
  }
  else {
    fprintf (stderr, _("use 'help', 'help <cmd>' or 'help -l|--list' to list all commands\n"));
    return -1;
  }
}
