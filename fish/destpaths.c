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
#include <stddef.h>
#include <string.h>

#ifdef HAVE_LIBREADLINE
#include <readline/readline.h>
#endif

#include <guestfs.h>

#include "fish.h"

// From gnulib's xalloc.h:
/* Return 1 if an array of N objects, each of size S, cannot exist due
   to size arithmetic overflow.  S must be positive and N must be
   nonnegative.  This is a macro, not an inline function, so that it
   works correctly even when SIZE_MAX < N.

   By gnulib convention, SIZE_MAX represents overflow in size
   calculations, so the conservative dividend to use here is
   SIZE_MAX - 1, since SIZE_MAX might represent an overflowed value.
   However, malloc (SIZE_MAX) fails on all known hosts where
   sizeof (ptrdiff_t) <= sizeof (size_t), so do not bother to test for
   exactly-SIZE_MAX allocations on such hosts; this avoids a test and
   branch when S is known to be 1.  */
# define xalloc_oversized(n, s) \
    ((size_t) (sizeof (ptrdiff_t) <= sizeof (size_t) ? -1 : -2) / (s) < (n))

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

  static size_t len, index;
  static char **words = NULL;
  static size_t nr_words = 0;
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

    len = strlen (text);
    index = 0;

    if (words) {
      size_t i;
      /* NB. 'words' array is NOT NULL-terminated. */
      for (i = 0; i < nr_words; ++i)
	free (words[i]);
      free (words);
    }

    words = NULL;
    nr_words = 0;

    SAVE_ERROR_CB

/* Silently do nothing if an allocation fails */
#define APPEND_STRS_AND_FREE						\
  do {									\
    if (strs) {								\
      size_t n = count_strings (strs);					\
      if ( ! xalloc_oversized (nr_words + n, sizeof (char *))) {	\
	char *w = realloc (words, sizeof (char *) * (nr_words + n));	\
	if (w == NULL) {						\
	  free (words);							\
	  words = NULL;							\
	  nr_words = 0;							\
	} else {							\
	  size_t i;							\
	  for (i = 0; i < n; ++i)					\
	    words[nr_words++] = strs[i];				\
	}								\
	free (strs);							\
      }									\
    }									\
  } while (0)

    /* Is it a device? */
    if (len < 5 || strncmp (text, "/dev/", 5) == 0) {
      /* Get a list of everything that can possibly begin with /dev/ */
      strs = guestfs_list_devices (g);
      APPEND_STRS_AND_FREE;

      strs = guestfs_list_partitions (g);
      APPEND_STRS_AND_FREE;

      strs = guestfs_lvs (g);
      APPEND_STRS_AND_FREE;
    }

    if (len < 1 || text[0] == '/') {
      /* If we've got a partial path already, we need to list everything
       * in that directory, otherwise list everything in /
       */
      char *p, *dir;

      p = strrchr (text, '/');
      dir = p && p > text ? strndup (text, p - text) : strdup ("/");
      if (dir) {
	strs = guestfs_ls (g, dir);

	/* Prepend directory to names. */
	if (strs) {
	  size_t i;
	  for (i = 0; strs[i]; ++i) {
	    int err;
	    if (strcmp (dir, "/") == 0)
	      err = asprintf (&p, "/%s", strs[i]);
	    else
	      err = asprintf (&p, "%s/%s", dir, strs[i]);
	    if (0 <= err) {
	      free (strs[i]);
	      strs[i] = p;
	    }
	  }
	}

	free (dir);
	APPEND_STRS_AND_FREE;
      }
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
