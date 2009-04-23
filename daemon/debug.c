/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009 Red Hat Inc. 
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

/* This command exposes debugging information, internals and
 * status.  There is no comprehensive documentation for this
 * command.  You have to look at the source code in this file
 * to find out what you can do.
 *
 * Commands always output a freeform string.
 */

#if ENABLE_DEBUG_COMMAND
struct cmd {
  const char *cmd;
  char * (*f) (const char *subcmd, int argc, char *const *const argv);
};

static char *debug_help (const char *subcmd, int argc, char *const *const argv);
#if 0
static char *debug_fds (const char *subcmd, int argc, char *const *const argv);
static char *debug_free (const char *subcmd, int argc, char *const *const argv);
static char *debug_mem (const char *subcmd, int argc, char *const *const argv);
static char *debug_ps (const char *subcmd, int argc, char *const *const argv);
#endif

static struct cmd cmds[] = {
  { "help", debug_help },
#if 0
  { "fds", debug_fds },
  { "free", debug_free },
  { "mem", debug_mem },
  { "ps", debug_free },
#endif
  { NULL, NULL }
};
#endif

char *
do_debug (const char *subcmd, char *const *const argv)
{
#if ENABLE_DEBUG_COMMAND
  int argc, i;

  for (i = argc = 0; argv[i] != NULL; ++i)
    argc++;

  for (i = 0; cmds[i].cmd != NULL; ++i) {
    if (strcasecmp (subcmd, cmds[i].cmd) == 0)
      return cmds[i].f (subcmd, argc, argv);
  }

  reply_with_error ("use 'debug help' to list the supported commands");
  return NULL;
#else
  reply_with_error ("guestfsd was not configured with --enable-debug-command");
  return NULL;
#endif
}

#if ENABLE_DEBUG_COMMAND
static char *
debug_help (const char *subcmd, int argc, char *const *const argv)
{
  int len, i;
  char *r, *p;

  r = strdup ("Commands supported:");
  if (!r) {
    reply_with_perror ("strdup");
    return NULL;
  }

  len = strlen (r);
  for (i = 0; cmds[i].cmd != NULL; ++i) {
    len += strlen (cmds[i].cmd) + 1; /* space + new command */
    p = realloc (r, len + 1);	     /* +1 for the final NUL */
    if (p == NULL) {
      reply_with_perror ("realloc");
      free (r);
      return NULL;
    }
    r = p;

    strcat (r, " ");
    strcat (r, cmds[i].cmd);
  }

  return r;
}

#if 0
static char *
debug_fds (const char *subcmd, int argc, char *const *const argv)
{
}

static char *
debug_free (const char *subcmd, int argc, char *const *const argv)
{
}

static char *
debug_mem (const char *subcmd, int argc, char *const *const argv)
{
}

static char *
debug_ps (const char *subcmd, int argc, char *const *const argv)
{
}
#endif
#endif /* ENABLE_DEBUG_COMMAND */
