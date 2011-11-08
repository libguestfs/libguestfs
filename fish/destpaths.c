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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>

#ifdef HAVE_LIBREADLINE
#include <readline/readline.h>
#endif

#include <guestfs.h>

#include "fish.h"

#ifdef HAVE_LIBREADLINE
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
#endif

/* Readline completion for paths on the guest filesystem, also for
 * devices and LVM names.
 */

int complete_dest_paths = 1;

struct word {
  char *name;
  int is_dir;
};

#ifdef HAVE_LIBREADLINE
static void
free_words (struct word *words, size_t nr_words)
{
  size_t i;

  /* NB. 'words' array is NOT NULL-terminated. */
  for (i = 0; i < nr_words; ++i)
    free (words[i].name);
  free (words);
}

static int
compare_words (const void *vp1, const void *vp2)
{
  const struct word *w1 = (const struct word *) vp1;
  const struct word *w2 = (const struct word *) vp2;
  return strcmp (w1->name, w2->name);
}
#endif

char *
complete_dest_paths_generator (const char *text, int state)
{
#ifdef HAVE_LIBREADLINE

  static size_t len, index;
  static struct word *words = NULL;
  static size_t nr_words = 0;
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

    if (words) free_words (words, nr_words);

    words = NULL;
    nr_words = 0;

    SAVE_ERROR_CB

/* Silently do nothing if an allocation fails */
#define APPEND_STRS_AND_FREE						\
  do {									\
    if (strs) {								\
      size_t i;								\
      size_t n = count_strings (strs);					\
                                                                        \
      if ( n > 0 && ! xalloc_oversized (nr_words + n, sizeof (struct word))) { \
        struct word *w;							\
        w = realloc (words, sizeof (struct word) * (nr_words + n));	\
                                                                        \
        if (w == NULL) {						\
          free_words (words, nr_words);					\
          words = NULL;							\
          nr_words = 0;							\
        } else {							\
          words = w;							\
          for (i = 0; i < n; ++i) {					\
            words[nr_words].name = strs[i];				\
            words[nr_words].is_dir = 0;					\
            nr_words++;							\
          }								\
        }								\
      }									\
      free (strs);							\
    }									\
  } while (0)

    /* Is it a device? */
    if (len < 5 || STREQLEN (text, "/dev/", 5)) {
      /* Get a list of everything that can possibly begin with /dev/ */
      strs = guestfs_list_devices (g);
      APPEND_STRS_AND_FREE;

      strs = guestfs_list_partitions (g);
      APPEND_STRS_AND_FREE;

      strs = guestfs_lvs (g);
      APPEND_STRS_AND_FREE;

      strs = guestfs_list_dm_devices (g);
      APPEND_STRS_AND_FREE;
    }

    if (len < 1 || text[0] == '/') {
      /* If we've got a partial path already, we need to list everything
       * in that directory, otherwise list everything in /
       */
      char *p, *dir;
      struct guestfs_dirent_list *dirents;

      p = strrchr (text, '/');
      dir = p && p > text ? strndup (text, p - text) : strdup ("/");
      if (dir) {
        dirents = guestfs_readdir (g, dir);

        /* Prepend directory to names before adding them to the list
         * of words.
         */
        if (dirents) {
          size_t i;

          for (i = 0; i < dirents->len; ++i) {
            int err;

            if (STRNEQ (dirents->val[i].name, ".") &&
                STRNEQ (dirents->val[i].name, "..")) {
              if (STREQ (dir, "/"))
                err = asprintf (&p, "/%s", dirents->val[i].name);
              else
                err = asprintf (&p, "%s/%s", dir, dirents->val[i].name);
              if (err >= 0) {
                if (!xalloc_oversized (nr_words+1, sizeof (struct word))) {
                  struct word *w;

                  w = realloc (words, sizeof (struct word) * (nr_words+1));
                  if (w == NULL) {
                    free_words (words, nr_words);
                    words = NULL;
                    nr_words = 0;
                  }
                  else {
                    words = w;
                    words[nr_words].name = p;
                    words[nr_words].is_dir = dirents->val[i].ftyp == 'd';
                    nr_words++;
                  }
                }
              }
            }
          }

          guestfs_free_dirent_list (dirents);
        }
      }
    }

    /* else ...  In theory we could complete other things here such as VG
     * names.  At the moment we don't do that.
     */

    RESTORE_ERROR_CB
  }

  /* This inhibits ordinary (local filename) completion. */
  rl_attempted_completion_over = 1;

  /* Sort the words so the list is stable over multiple calls. */
  qsort (words, nr_words, sizeof (struct word), compare_words);

  /* Complete the string. */
  while (index < nr_words) {
    struct word *word;

    word = &words[index];
    index++;

    /* Whether we should match case insensitively here or not is
     * determined by the value of the completion-ignore-case readline
     * variable.  Default to case insensitive.  (See: RHBZ#582993).
     */
    char *cic_var = rl_variable_value ("completion-ignore-case");
    int cic = 1;
    if (cic_var && STREQ (cic_var, "off"))
      cic = 0;

    int matches =
      cic ? STRCASEEQLEN (word->name, text, len)
          : STREQLEN (word->name, text, len);

    if (matches) {
      if (word->is_dir)
        rl_completion_append_character = '/';

      return strdup (word->name);
    }
  }

#endif /* HAVE_LIBREADLINE */

  return NULL;
}
