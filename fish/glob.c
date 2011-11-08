/* guestfish - the filesystem interactive shell
 * Copyright (C) 2009-2010 Red Hat Inc.
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

#include "fish.h"

/* A bit tricky because in the case where there are multiple
 * paths we have to perform a Cartesian product.
 */
static void glob_issue (char *cmd, size_t argc, char ***globs, int *posn, int *count, int *r);

int
run_glob (const char *cmd, size_t argc, char *argv[])
{
  /* For 'glob cmd foo /s* /usr/s*' this could be:
   *
   * (globs[0]) globs[1]  globs[1]  globs[2]
   * (cmd)      foo       /sbin     /usr/sbin
   *                      /srv      /usr/share
   *                      /sys      /usr/src
   *
   * and then we call every combination (ie. 1x3x3) of
   * argv[1-].
   */
  char **globs[argc];
  int posn[argc];
  int count[argc];
  size_t i;
  int r = 0;

  if (argc < 1) {
    fprintf (stderr, _("use 'glob command [args...]'\n"));
    return -1;
  }

  /* This array will record the current execution position
   * in the Cartesian product.
   * NB. globs[0], posn[0], count[0] are ignored.
   */
  for (i = 1; i < argc; ++i)
    posn[i] = 0;
  for (i = 1; i < argc; ++i)
    globs[i] = NULL;

  for (i = 1; i < argc; ++i) {
    char **pp;

    /* Only if it begins with '/' can it possibly be a globbable path. */
    if (argv[i][0] == '/') {
      pp = guestfs_glob_expand (g, argv[i]);
      if (pp == NULL) {		/* real error in glob_expand */
        fprintf (stderr, _("glob: guestfs_glob_expand call failed: %s\n"),
                 argv[i]);
        goto error0;
      }

      /* If there were no matches, then we add a single element list
       * containing just the original argv[i] string.
       */
      if (pp[0] == NULL) {
        char **pp2;

        pp2 = realloc (pp, sizeof (char *) * 2);
        if (pp2 == NULL) {
          perror ("realloc");
          free (pp);
          goto error0;
        }
        pp = pp2;

        pp[0] = strdup (argv[i]);
        if (pp[0] == NULL) {
          perror ("strdup");
          free (pp);
          goto error0;
        }
        pp[1] = NULL;
      }
    }
    /* Doesn't begin with '/' */
    else {
      pp = malloc (sizeof (char *) * 2);
      if (pp == NULL) {
        perror ("malloc");
        goto error0;
      }
      pp[0] = strdup (argv[i]);
      if (pp[0] == NULL) {
        perror ("strdup");
        free (pp);
        goto error0;
      }
      pp[1] = NULL;
    }

    globs[i] = pp;
    count[i] = count_strings (pp);
  }

  /* Issue the commands. */
  glob_issue (argv[0], argc, globs, posn, count, &r);

  /* Free resources. */
 error0:
  for (i = 1; i < argc; ++i)
    if (globs[i])
      free_strings (globs[i]);
  return r;
}

static void
glob_issue (char *cmd, size_t argc,
            char ***globs, int *posn, int *count,
            int *r)
{
  size_t i;
  char *argv[argc+1];

  argv[0] = cmd;
  argv[argc] = NULL;

 again:
  for (i = 1; i < argc; ++i)
    argv[i] = globs[i][posn[i]];

  if (issue_command (argv[0], &argv[1], NULL, 0) == -1)
    *r = -1;			/* ... but don't exit */

  for (i = argc-1; i >= 1; --i) {
    posn[i]++;
    if (posn[i] < count[i])
      break;
    posn[i] = 0;
  }
  if (i == 0)			/* All done. */
    return;

  goto again;
}
