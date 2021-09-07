/* libguestfs - the guestfsd daemon
 * Copyright (C) 2010 Red Hat Inc.
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

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#define MAX_ARGS 64

int
optgroup_luks_available (void)
{
  return prog_exists ("cryptsetup");
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wanalyzer-possible-null-argument"
/* Callers must also call remove_temp (tempfile). */
static char *
write_key_to_temp (const char *key)
{
  char *tempfile;
  int fd;
  size_t len;

  tempfile = strdup ("/tmp/luksXXXXXX");
  if (!tempfile) {
    reply_with_perror ("strdup");
    return NULL;
  }

  fd = mkstemp (tempfile);
  if (fd == -1) {
    reply_with_perror ("mkstemp");
    goto error;
  }

  len = strlen (key);
  if (xwrite (fd, key, len) == -1) {
    reply_with_perror ("write");
    close (fd);
    goto error;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close");
    goto error;
  }

  return tempfile;

 error:
  unlink (tempfile);
  free (tempfile);
  return NULL;
}
#pragma GCC diagnostic pop

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wanalyzer-double-free"
static void
remove_temp (char *tempfile)
{
  unlink (tempfile);
  free (tempfile);
}
#pragma GCC diagnostic pop

static int
luks_format (const char *device, const char *key, int keyslot,
             const char *cipher)
{
  char *tempfile = write_key_to_temp (key);
  if (!tempfile)
    return -1;

  const char *argv[MAX_ARGS];
  char keyslot_s[16];
  size_t i = 0;

  ADD_ARG (argv, i, "cryptsetup");
  ADD_ARG (argv, i, "-q");
  if (cipher) {
    ADD_ARG (argv, i, "--cipher");
    ADD_ARG (argv, i, cipher);
  }
  ADD_ARG (argv, i, "--key-slot");
  snprintf (keyslot_s, sizeof keyslot_s, "%d", keyslot);
  ADD_ARG (argv, i, keyslot_s);
  ADD_ARG (argv, i, "luksFormat");
  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, tempfile);
  ADD_ARG (argv, i, NULL);

  CLEANUP_FREE char *err = NULL;
  int r = commandv (NULL, &err, (const char * const *) argv);
  remove_temp (tempfile);

  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_luks_format (const char *device, const char *key, int keyslot)
{
  return luks_format (device, key, keyslot, NULL);
}

int
do_luks_format_cipher (const char *device, const char *key, int keyslot,
                       const char *cipher)
{
  return luks_format (device, key, keyslot, cipher);
}

int
do_luks_add_key (const char *device, const char *key, const char *newkey,
                 int keyslot)
{
  char *keyfile = write_key_to_temp (key);
  if (!keyfile)
    return -1;

  char *newkeyfile = write_key_to_temp (newkey);
  if (!newkeyfile) {
    remove_temp (keyfile);
    return -1;
  }

  const char *argv[MAX_ARGS];
  char keyslot_s[16];
  size_t i = 0;

  ADD_ARG (argv, i, "cryptsetup");
  ADD_ARG (argv, i, "-q");
  ADD_ARG (argv, i, "-d");
  ADD_ARG (argv, i, keyfile);
  ADD_ARG (argv, i, "--key-slot");
  snprintf (keyslot_s, sizeof keyslot_s, "%d", keyslot);
  ADD_ARG (argv, i, keyslot_s);
  ADD_ARG (argv, i, "luksAddKey");
  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, newkeyfile);
  ADD_ARG (argv, i, NULL);

  CLEANUP_FREE char *err = NULL;
  int r = commandv (NULL, &err, (const char * const *) argv);
  remove_temp (keyfile);
  remove_temp (newkeyfile);

  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
do_luks_kill_slot (const char *device, const char *key, int keyslot)
{
  char *tempfile = write_key_to_temp (key);
  if (!tempfile)
    return -1;

  const char *argv[MAX_ARGS];
  char keyslot_s[16];
  size_t i = 0;

  ADD_ARG (argv, i, "cryptsetup");
  ADD_ARG (argv, i, "-q");
  ADD_ARG (argv, i, "-d");
  ADD_ARG (argv, i, tempfile);
  ADD_ARG (argv, i, "luksKillSlot");
  ADD_ARG (argv, i, device);
  snprintf (keyslot_s, sizeof keyslot_s, "%d", keyslot);
  ADD_ARG (argv, i, keyslot_s);
  ADD_ARG (argv, i, NULL);

  CLEANUP_FREE char *err = NULL;
  int r = commandv (NULL, &err, (const char * const *) argv);
  remove_temp (tempfile);

  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

char *
do_luks_uuid (const char *device)
{
  const char *argv[MAX_ARGS];
  size_t i = 0;

  ADD_ARG (argv, i, "cryptsetup");
  ADD_ARG (argv, i, "luksUUID");
  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  char *out = NULL;
  CLEANUP_FREE char *err = NULL;
  int r = commandv (&out, &err, (const char * const *) argv);

  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  trim (out);

  return out;
}
