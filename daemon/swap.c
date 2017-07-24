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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <assert.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#include "ignore-value.h"

/* Confirmed this is true for Linux swap partitions from the Linux sources. */
#define SWAP_LABEL_MAX 16

int
optgroup_linuxfsuuid_available (void)
{
  return 1;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_mkswap (const char *device, const char *label, const char *uuid)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  size_t i = 0;
  int r;
  CLEANUP_FREE char *err = NULL;

  ADD_ARG (argv, i, "mkswap");
  ADD_ARG (argv, i, "-f");

  if (optargs_bitmask & GUESTFS_MKSWAP_LABEL_BITMASK) {
    assert (label != NULL); /* suppress a warning with -O3 */
    if (strlen (label) > SWAP_LABEL_MAX) {
      reply_with_error ("%s: Linux swap labels are limited to %d bytes",
                        label, SWAP_LABEL_MAX);
      return -1;
    }

    ADD_ARG (argv, i, "-L");
    ADD_ARG (argv, i, label);
  }

  if (optargs_bitmask & GUESTFS_MKSWAP_UUID_BITMASK) {
    ADD_ARG (argv, i, "-U");
    ADD_ARG (argv, i, uuid);
  }

  ADD_ARG (argv, i, device);
  ADD_ARG (argv, i, NULL);

  wipe_device_before_mkfs (device);

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_mkswap_L (const char *label, const char *device)
{
  optargs_bitmask = GUESTFS_MKSWAP_LABEL_BITMASK;
  return do_mkswap (device, label, NULL);
}

int
do_mkswap_U (const char *uuid, const char *device)
{
  optargs_bitmask = GUESTFS_MKSWAP_UUID_BITMASK;
  return do_mkswap (device, NULL, uuid);
}

int
do_mkswap_file (const char *path)
{
  CLEANUP_FREE char *buf = NULL, *err = NULL;
  int r;

  buf = sysroot_path (path);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = command (NULL, &err, "mkswap", "-f", buf, NULL);

  if (r == -1) {
    reply_with_error ("%s: %s", path, err);
    return -1;
  }

  return r;
}

static int
swaponoff (const char *cmd, const char *flag, const char *value)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  if (!flag)
    r = command (NULL, &err, cmd, value, NULL);
  else
    r = command (NULL, &err, cmd, flag, value, NULL);

  if (r == -1) {
    reply_with_error ("%s: %s", value, err);
    return -1;
  }

  /* Possible fix for RHBZ#516096.  It probably doesn't hurt to do
   * this in any case.
   */
  udev_settle ();

  return 0;
}

int
do_swapon_device (const char *device)
{
  return swaponoff ("swapon", NULL, device);
}

int
do_swapoff_device (const char *device)
{
  return swaponoff ("swapoff", NULL, device);
}

int
do_swapon_file (const char *path)
{
  CLEANUP_FREE char *buf = NULL;

  buf = sysroot_path (path);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  return swaponoff ("swapon", NULL, buf);
}

int
do_swapoff_file (const char *path)
{
  CLEANUP_FREE char *buf = NULL;

  buf = sysroot_path (path);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  return swaponoff ("swapoff", NULL, buf);
}

int
do_swapon_label (const char *label)
{
  if (strlen (label) > SWAP_LABEL_MAX) {
    reply_with_error ("%s: Linux swap labels are limited to %d bytes",
                      label, SWAP_LABEL_MAX);
    return -1;
  }

  return swaponoff ("swapon", "-L", label);
}

int
do_swapoff_label (const char *label)
{
  if (strlen (label) > SWAP_LABEL_MAX) {
    reply_with_error ("%s: Linux swap labels are limited to %d bytes",
                      label, SWAP_LABEL_MAX);
    return -1;
  }

  return swaponoff ("swapoff", "-L", label);
}

int
do_swapon_uuid (const char *uuid)
{
  return swaponoff ("swapon", "-U", uuid);
}

int
do_swapoff_uuid (const char *uuid)
{
  return swaponoff ("swapoff", "-U", uuid);
}

int
swap_set_uuid (const char *device, const char *uuid)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  r = command (NULL, &err, "swaplabel", "-U", uuid, device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

int
swap_set_label (const char *device, const char *label)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  if (strlen (label) > SWAP_LABEL_MAX) {
    reply_with_error ("%s: Linux swap labels are limited to %d bytes",
                      label, SWAP_LABEL_MAX);
    return -1;
  }

  r = command (NULL, &err, "swaplabel", "-L", label, device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}
