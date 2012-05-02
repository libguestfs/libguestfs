/* guestfish - the filesystem interactive shell
 * Copyright (C) 2009-2012 Red Hat Inc.
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
#include <errno.h>
#include <fnmatch.h>
#include <libintl.h>

#include "fish.h"

/* A bit tricky because in the case where there are multiple
 * paths we have to perform a Cartesian product.
 */

static char **expand_pathname (guestfs_h *g, const char *path);
static char **expand_devicename (guestfs_h *g, const char *device);
static int add_strings_matching (char **pp, const char *glob, char ***ret, size_t *size_r);
static int add_string (const char *str, char ***ret, size_t *size_r);
static char **single_element_list (const char *element);
static void glob_issue (char *cmd, size_t argc, char ***globs, size_t *posn, size_t *count, int *r);

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
  size_t posn[argc];
  size_t count[argc];
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

    /* If it begins with "/dev/" then treat it as a globbable device
     * name.
     */
    if (STRPREFIX (argv[i], "/dev/")) {
      pp = expand_devicename (g, argv[i]);
      if (pp == NULL) {
        r = -1;
        goto error;
      }
    }
    /* If it begins with "/" it might be a globbable pathname. */
    else if (argv[i][0] == '/') {
      pp = expand_pathname (g, argv[i]);
      if (pp == NULL) {
        r = -1;
        goto error;
      }
    }
    /* Doesn't begin with '/' */
    else {
      pp = single_element_list (argv[i]);
      if (pp == NULL) {
        r = -1;
        goto error;
      }
    }

    globs[i] = pp;
    count[i] = count_strings (pp);
  }

  /* Issue the commands. */
  glob_issue (argv[0], argc, globs, posn, count, &r);

  /* Free resources. */
 error:
  for (i = 1; i < argc; ++i)
    if (globs[i])
      free_strings (globs[i]);
  return r;
}

static char **
expand_pathname (guestfs_h *g, const char *path)
{
  char **pp;

  pp = guestfs_glob_expand (g, path);
  if (pp == NULL) {		/* real error in glob_expand */
    fprintf (stderr, _("glob: guestfs_glob_expand call failed: %s\n"), path);
    return NULL;
  }

  if (pp[0] != NULL)
    return pp; /* Return the non-empty list of matches. */

  /* If there were no matches, then we add a single element list
   * containing just the original string.
   */
  free (pp);
  return single_element_list (path);
}

/* Glob-expand device patterns, such as "/dev/sd*" (RHBZ#635971).
 *
 * There is no 'guestfs_glob_expand_device' function because the
 * equivalent can be implemented using functions like
 * 'guestfs_list_devices'.
 *
 * It's not immediately clear what it means to expand a pattern like
 * "/dev/sd*".  Should that include device name translation?  Should
 * the result include partitions as well as devices?
 *
 * Should "/dev/" + "*" return every possible device and filesystem?
 * How about VGs?  LVs?
 *
 * To solve this what we do is build up a list of every device,
 * partition, etc., then glob against that list.
 *
 * Notes for future work (XXX):
 * - This doesn't handle device name translation.  It wouldn't be
 *   too hard to add.
 * - Could have an API function for returning all device-like things.
 */
static char **
expand_devicename (guestfs_h *g, const char *device)
{
  char **pp = NULL;
  char **ret = NULL;
  size_t size = 0;

  pp = guestfs_list_devices (g);
  if (pp == NULL) goto error;
  if (add_strings_matching (pp, device, &ret, &size) == -1) goto error;
  free_strings (pp);

  pp = guestfs_list_partitions (g);
  if (pp == NULL) goto error;
  if (add_strings_matching (pp, device, &ret, &size) == -1) goto error;
  free_strings (pp);

  pp = guestfs_list_md_devices (g);
  if (pp == NULL) goto error;
  if (add_strings_matching (pp, device, &ret, &size) == -1) goto error;
  free_strings (pp);

  if (feature_available (g, "lvm2")) {
    pp = guestfs_lvs (g);
    if (pp == NULL) goto error;
    if (add_strings_matching (pp, device, &ret, &size) == -1) goto error;
    free_strings (pp);
    pp = NULL;
  }

  /* None matched?  Add the original glob pattern. */
  if (ret == NULL)
    ret = single_element_list (device);
  return ret;

 error:
  if (pp)
    free_strings (pp);
  if (ret)
    free_strings (ret);

  return NULL;
}

/* Using fnmatch, find strings in the list 'pp' which match pattern
 * 'glob'.  Add strings which match to the 'ret' array.  '*size_r' is
 * the current size of the 'ret' array, which is updated with the new
 * size.
 */
static int
add_strings_matching (char **pp, const char *glob,
                      char ***ret, size_t *size_r)
{
  size_t i;
  int r;

  for (i = 0; pp[i] != NULL; ++i) {
    errno = 0;
    r = fnmatch (glob, pp[i], FNM_PATHNAME);
    if (r == 0) {               /* matches - add it */
      if (add_string (pp[i], ret, size_r) == -1)
        return -1;
    }
    else if (r != FNM_NOMATCH) { /* error */
      /* I checked the glibc impl and it returns random negative
       * numbers for errors.  It doesn't always set errno.  Do our
       * best here to record the error state.
       */
      fprintf (stderr, "glob: fnmatch: error (r = %d, errno = %d)\n",
               r, errno);
      return -1;
    }
  }

  return 0;
}

static int
add_string (const char *str, char ***ret, size_t *size_r)
{
  char **new_ret = *ret;
  size_t size = *size_r;

  new_ret = realloc (new_ret, (size + 2) * (sizeof (char *)));
  if (!new_ret) {
    perror ("realloc");
    return -1;
  }
  *ret = new_ret;

  new_ret[size] = strdup (str);
  if (new_ret[size] == NULL) {
    perror ("strdup");
    return -1;
  }

  size++;
  new_ret[size] = NULL;
  *size_r = size;

  return 0;
}

/* Return a single element list containing 'element'. */
static char **
single_element_list (const char *element)
{
  char **pp;

  pp = malloc (sizeof (char *) * 2);
  if (pp == NULL) {
    perror ("malloc");
    return NULL;
  }
  pp[0] = strdup (element);
  if (pp[0] == NULL) {
    perror ("strdup");
    free (pp);
    return NULL;
  }
  pp[1] = NULL;

  return pp;
}

static void
glob_issue (char *cmd, size_t argc,
            char ***globs, size_t *posn, size_t *count,
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
