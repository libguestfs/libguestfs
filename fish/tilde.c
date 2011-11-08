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
#include <string.h>
#include <unistd.h>
#include <assert.h>
#include <pwd.h>
#include <sys/types.h>

#include "fish.h"

static char *expand_home (char *orig, const char *append);
static const char *find_home_for_username (const char *, size_t);
static const char *find_home_for_current_user (void);

/* This is called from the script loop if we find a candidate for
 * ~username (tilde-expansion).
 */
char *
try_tilde_expansion (char *str)
{
  assert (str[0] == '~');

  /* Expand "~" to current user's home directory. */
  if (str[1] == '\0')		/* ~ */
    return expand_home (str, NULL);
  else if (str[1] == '/')	/* ~/... */
    return expand_home (str, &str[1]);

  /* Try expanding the part up to the following '\0' or '/' as a
   * username from the password file.
   */
  else {
    const char *home, *rest;
    size_t len = strcspn (&str[1], "/");
    rest = &str[1+len];

    home = find_home_for_username (&str[1], len);

    if (home) {
      len = strlen (home) + strlen (rest) + 1;
      str = malloc (len);
      if (str == NULL) {
        perror ("malloc");
        exit (EXIT_FAILURE);
      }
      strcpy (str, home);
      strcat (str, rest);
      return str;
    }
  }

  /* No match, return the orignal string. */
  return str;
}

/* Return $HOME + append string. */
static char *
expand_home (char *orig, const char *append)
{
  const char *home;
  int len;
  char *str;

  home = getenv ("HOME");
  if (!home) {
    /* $HOME not set, bash can look up the current user in the
     * password file and find their home that way.  (RHBZ#617440).
     */
    home = find_home_for_current_user ();
    if (!home)
      return orig;
  }

  len = strlen (home) + (append ? strlen (append) : 0) + 1;
  str = malloc (len);
  if (str == NULL) {
    perror ("malloc");
    exit (EXIT_FAILURE);
  }

  strcpy (str, home);
  if (append)
    strcat (str, append);

  return str;
}

/* Lookup username (of length ulen), return home directory if found,
 * or NULL if not found.
 */
static const char *
find_home_for_username (const char *username, size_t ulen)
{
  struct passwd *pw;

  setpwent ();
  while ((pw = getpwent ()) != NULL) {
    if (strlen (pw->pw_name) == ulen &&
        STREQLEN (username, pw->pw_name, ulen))
      return pw->pw_dir;
  }

  return NULL;
}

static const char *
find_home_for_current_user (void)
{
  struct passwd *pw;
  uid_t euid = geteuid ();

  setpwent ();
  while ((pw = getpwent ()) != NULL) {
    if (pw->pw_uid == euid)
      return pw->pw_dir;
  }

  return NULL;
}
