/* guestfish - the filesystem interactive shell
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

#define _GNU_SOURCE		// for strndup, asprintf

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef HAVE_LIBREADLINE
#include <readline/readline.h>
#endif

#include <guestfs.h>

#include "fish.h"

/* Readline completion for paths on the guest filesystem, also for
 * devices and LVM names.
 */

int complete_dest_paths = 0; /* SEE NOTE */

/* NOTE: This is currently disabled by default (with no way to
 * enable it).  That's because it's not particularly natural.
 *
 * Also there is a quite serious performance problem.  When listing
 * even moderately long directories, this takes many seconds.  The
 * reason is because it calls guestfs_is_dir on each directory
 * entry, thus lots of round trips to the server.  We could have
 * a "readdir and stat each entry" call to ease this.
 */

char *
complete_dest_paths_generator (const char *text, int state)
{
#ifdef HAVE_LIBREADLINE

  static int len, index;
  static char **words = NULL;
  static int nr_words = 0;
  char *word;
  guestfs_error_handler_cb old_error_cb;
  void *old_error_cb_data;

  /* Temporarily replace the error handler so that messages don't
   * get printed to stderr while we are issuing commands.
   */
#define SAVE_ERROR_CB							\
  old_error_cb = guestfs_get_error_handler (g, &old_error_cb_data);	\
  guestfs_set_error_handler (g, NULL, NULL);

  /* Restore error handler. */
#define RESTORE_ERROR_CB						\
  guestfs_set_error_handler (g, old_error_cb, old_error_cb_data);

  if (!state) {
    char **strs;
    int i, n;

    len = strlen (text);
    index = 0;

    if (words) {
      /* NB. 'words' array is NOT NULL-terminated. */
      for (i = 0; i < nr_words; ++i)
	free (words[i]);
      free (words);
    }

    words = NULL;
    nr_words = 0;

    SAVE_ERROR_CB

#define APPEND_STRS_AND_FREE						\
    if (strs) {								\
      n = count_strings (strs);						\
      words = realloc (words, sizeof (char *) * (nr_words + n));	\
      for (i = 0; i < n; ++i)						\
	words[nr_words++] = strs[i];					\
      free (strs);							\
    }

    /* Is it a device? */
    if (len < 5 || strncmp (text, "/dev/", 5) == 0) {
      /* Get a list of everything that can possibly begin with /dev/ */
      strs = guestfs_list_devices (g);
      APPEND_STRS_AND_FREE

      strs = guestfs_list_partitions (g);
      APPEND_STRS_AND_FREE

      strs = guestfs_lvs (g);
      APPEND_STRS_AND_FREE
    }

    if (len < 1 || text[0] == '/') {
      /* If we've got a partial path already, we need to list everything
       * in that directory, otherwise list everything in /
       */
      char *p, *dir;

      p = strrchr (text, '/');
      dir = p && p > text ? strndup (text, p - text) : strdup ("/");

      strs = guestfs_ls (g, dir);

      /* Prepend directory to names. */
      if (strs) {
	for (i = 0; strs[i]; ++i) {
	  p = NULL;
	  if (strcmp (dir, "/") == 0)
	    asprintf (&p, "/%s", strs[i]);
	  else
	    asprintf (&p, "%s/%s", dir, strs[i]);
	  free (strs[i]);
	  strs[i] = p;
	}
      }

      free (dir);
      APPEND_STRS_AND_FREE
    }

    /* else ...  In theory we could complete other things here such as VG
     * names.  At the moment we don't do that.
     */

    RESTORE_ERROR_CB
  }

  /* This inhibits ordinary (local filename) completion. */
  rl_attempted_completion_over = 1;

  /* Complete the string. */
  while (index < nr_words) {
    word = words[index];
    index++;
    if (strncasecmp (word, text, len) == 0) {
      /* Is it a directory? */
      if (strncmp (word, "/dev/", 5) != 0) {
	SAVE_ERROR_CB
	if (guestfs_is_dir (g, word) > 0)
	  rl_completion_append_character = '/';
	RESTORE_ERROR_CB
      }

      return strdup (word);
    }
  }

#endif /* HAVE_LIBREADLINE */

  return NULL;
}
