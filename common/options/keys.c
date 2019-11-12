/* libguestfs - guestfish and guestmount shared option parsing
 * Copyright (C) 2010-2012 Red Hat Inc.
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
#include <unistd.h>
#include <termios.h>
#include <string.h>
#include <libintl.h>
#include <errno.h>
#include <error.h>
#include <assert.h>

#include "guestfs.h"

#include "options.h"

/**
 * Read a passphrase ('Key') from F</dev/tty> with echo off.
 *
 * The caller (F<fish/cmds.c>) will call free on the string
 * afterwards.  Based on the code in cryptsetup file F<lib/utils.c>.
 */
char *
read_key (const char *param)
{
  FILE *infp, *outfp;
  struct termios orig, temp;
  char *ret = NULL;
  int tty;
  int tcset = 0;
  size_t allocsize = 0;
  ssize_t len;

  /* Read and write to /dev/tty if available. */
  if (keys_from_stdin ||
      (infp = outfp = fopen ("/dev/tty", "w+")) == NULL) {
    infp = stdin;
    outfp = stdout;
  }

  /* Print the prompt and set no echo. */
  tty = isatty (fileno (infp));
  if (tty) {
    fprintf (outfp, _("Enter key or passphrase (\"%s\"): "), param);

    if (!echo_keys) {
      if (tcgetattr (fileno (infp), &orig) == -1) {
        perror ("tcgetattr");
        goto error;
      }
      memcpy (&temp, &orig, sizeof temp);
      temp.c_lflag &= ~ECHO;

      tcsetattr (fileno (infp), TCSAFLUSH, &temp);
      tcset = 1;
    }
  }

  len = getline (&ret, &allocsize, infp);
  if (len == -1) {
    perror ("getline");
    ret = NULL;
    goto error;
  }

  /* Remove the terminating \n if there is one. */
  if (len > 0 && ret[len-1] == '\n')
    ret[len-1] = '\0';

 error:
  /* Restore echo, close file descriptor. */
  if (tty && tcset) {
    printf ("\n");
    tcsetattr (fileno (infp), TCSAFLUSH, &orig);
  }

  if (infp != stdin)
    fclose (infp); /* outfp == infp, so this is closed also */

  return ret;
}

static char *
read_first_line_from_file (const char *filename)
{
  CLEANUP_FCLOSE FILE *fp = NULL;
  char *ret = NULL;
  size_t allocsize = 0;
  ssize_t len;

  fp = fopen (filename, "r");
  if (!fp)
    error (EXIT_FAILURE, errno, "fopen: %s", filename);

  len = getline (&ret, &allocsize, fp);
  if (len == -1)
    error (EXIT_FAILURE, errno, "getline: %s", filename);

  /* Remove the terminating \n if there is one. */
  if (len > 0 && ret[len-1] == '\n')
    ret[len-1] = '\0';

  return ret;
}

char *
get_key (struct key_store *ks, const char *device)
{
  size_t i;

  if (ks) {
    for (i = 0; i < ks->nr_keys; ++i) {
      struct key_store_key *key = &ks->keys[i];
      char *s;

      if (STRNEQ (key->device, device))
        continue;

      switch (key->type) {
      case key_string:
        s = strdup (key->string.s);
        if (!s)
          error (EXIT_FAILURE, errno, "strdup");
        return s;
      case key_file:
        return read_first_line_from_file (key->file.name);
      }

      /* Key not found in the key store, ask the user for it. */
      break;
    }
  }

  return read_key (device);
}

struct key_store *
key_store_add_from_selector (struct key_store *ks, const char *selector_orig)
{
  CLEANUP_FREE char *selector = strdup (selector_orig);
  const char *elem;
  char *saveptr;
  struct key_store_key key;

  if (!selector)
    error (EXIT_FAILURE, errno, "strdup");

  /* 1: device */
  elem = strtok_r (selector, ":", &saveptr);
  if (!elem) {
   invalid_selector:
    error (EXIT_FAILURE, 0, "invalid selector for --key: %s", selector_orig);
  }
  key.device = strdup (elem);
  if (!key.device)
    error (EXIT_FAILURE, errno, "strdup");

  /* 2: key type */
  elem = strtok_r (NULL, ":", &saveptr);
  if (!elem)
    goto invalid_selector;
  else if (STREQ (elem, "key"))
    key.type = key_string;
  else if (STREQ (elem, "file"))
    key.type = key_file;
  else
    goto invalid_selector;

  /* 3: actual key */
  elem = strtok_r (NULL, ":", &saveptr);
  if (!elem)
    goto invalid_selector;
  switch (key.type) {
  case key_string:
    key.string.s = strdup (elem);
    if (!key.string.s)
      error (EXIT_FAILURE, errno, "strdup");
    break;
  case key_file:
    key.file.name = strdup (elem);
    if (!key.file.name)
      error (EXIT_FAILURE, errno, "strdup");
    break;
  }

  return key_store_import_key (ks, &key);
}

struct key_store *
key_store_import_key (struct key_store *ks, const struct key_store_key *key)
{
  struct key_store_key *new_keys;

  if (!ks) {
    ks = calloc (1, sizeof (*ks));
    if (!ks)
      error (EXIT_FAILURE, errno, "strdup");
  }
  assert (ks != NULL);

  new_keys = realloc (ks->keys,
                      (ks->nr_keys + 1) * sizeof (struct key_store_key));
  if (!new_keys)
    error (EXIT_FAILURE, errno, "realloc");

  ks->keys = new_keys;
  ks->keys[ks->nr_keys] = *key;
  ++ks->nr_keys;

  return ks;
}

void
free_key_store (struct key_store *ks)
{
  size_t i;

  if (!ks)
    return;

  for (i = 0; i < ks->nr_keys; ++i) {
    struct key_store_key *key = &ks->keys[i];

    switch (key->type) {
    case key_string:
      free (key->string.s);
      break;
    case key_file:
      free (key->file.name);
      break;
    }
    free (key->device);
  }
}
