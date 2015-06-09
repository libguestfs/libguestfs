/* virt-p2v
 * Copyright (C) 2015 Red Hat Inc.
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

/* Read /proc/cmdline.
 *
 * We only support double quoting, consistent with the Linux
 * documentation.
 * https://www.kernel.org/doc/Documentation/kernel-parameters.txt
 *
 * systemd supports single and double quoting and single character
 * escaping, but we don't support all that.
 *
 * Returns a list of key, value pairs, terminated by NULL.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#include "p2v.h"

static void
add_null (char ***argv, size_t *lenp)
{
  (*lenp)++;
  *argv = realloc (*argv, *lenp * sizeof (char *));
  if (*argv == NULL) {
    perror ("realloc");
    exit (EXIT_FAILURE);
  }
  (*argv)[(*lenp)-1] = NULL;
}

static void
add_string (char ***argv, size_t *lenp, const char *str, size_t len)
{
  add_null (argv, lenp);
  (*argv)[(*lenp)-1] = strndup (str, len);
  if ((*argv)[(*lenp)-1] == NULL) {
    perror ("strndup");
    exit (EXIT_FAILURE);
  }
}

char **
parse_cmdline_string (const char *cmdline)
{
  char **ret = NULL;
  size_t len = 0;
  const char *p, *key = NULL, *value = NULL;
  enum {
    KEY_START = 0,
    KEY,
    VALUE_START,
    VALUE,
    VALUE_QUOTED
  } state = 0;

  for (p = cmdline; *p; p++) {
    switch (state) {
    case KEY_START:             /* looking for the start of a key */
      if (*p == ' ') continue;
      key = p;
      state = KEY;
      break;

    case KEY:                   /* reading key */
      if (*p == ' ') {
        add_string (&ret, &len, key, p-key);
        add_string (&ret, &len, "", 0);
        state = KEY_START;
      }
      else if (*p == '=') {
        add_string (&ret, &len, key, p-key);
        state = VALUE_START;
      }
      break;

    case VALUE_START:           /* looking for the start of a value */
      if (*p == ' ') {
        add_string (&ret, &len, "", 0);
        state = KEY_START;
      }
      else if (*p == '"') {
        value = p+1;
        state = VALUE_QUOTED;
      }
      else {
        value = p;
        state = VALUE;
      }
      break;

    case VALUE:                 /* reading unquoted value */
      if (*p == ' ') {
        add_string (&ret, &len, value, p-value);
        state = KEY_START;
      }
      break;

    case VALUE_QUOTED:          /* reading quoted value */
      if (*p == '"') {
        add_string (&ret, &len, value, p-value);
        state = KEY_START;
      }
      break;
    }
  }

  switch (state) {
  case KEY_START: break;
  case KEY:                     /* key followed by end of string */
    add_string (&ret, &len, key, p-key);
    add_string (&ret, &len, "", 0);
    break;
  case VALUE_START:             /* key= followed by end of string */
    add_string (&ret, &len, "", 0);
    break;
  case VALUE:                   /* key=value followed by end of string */
    add_string (&ret, &len, value, p-value);
    break;
  case VALUE_QUOTED:            /* unterminated key="value" */
    fprintf (stderr, "%s: warning: unterminated quoted string on kernel command line\n",
             guestfs_int_program_name);
    add_string (&ret, &len, value, p-value);
  }

  add_null (&ret, &len);

  return ret;
}

char **
parse_proc_cmdline (void)
{
  CLEANUP_FCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *cmdline = NULL;
  size_t len = 0;

  fp = fopen ("/proc/cmdline", "re");
  if (fp == NULL) {
    perror ("/proc/cmdline");
    return NULL;
  }

  if (getline (&cmdline, &len, fp) == -1) {
    perror ("getline");
    return NULL;
  }

  /* 'len' is not the length of the string, but the length of the
   * buffer.  We need to chomp the string.
   */
  len = strlen (cmdline);

  if (len >= 1 && cmdline[len-1] == '\n')
    cmdline[len-1] = '\0';

  return parse_cmdline_string (cmdline);
}

const char *
get_cmdline_key (char **argv, const char *key)
{
  size_t i;

  for (i = 0; argv[i] != NULL; i += 2) {
    if (STREQ (argv[i], key))
      return argv[i+1];
  }

  /* Not found. */
  return NULL;
}
