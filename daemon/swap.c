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

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#include "ignore-value.h"

/* Confirmed this is true for Linux swap partitions from the Linux sources. */
#define SWAP_LABEL_MAX 16

/* Convenient place to test for the later version of e2fsprogs
 * and util-linux which supports -U parameters to specify UUIDs.
 * (Not supported in RHEL 5).
 */
int
optgroup_linuxfsuuid_available (void)
{
  char *err;
  int av;

  /* Upstream util-linux have been gradually changing '--help' to go
   * from stderr to stdout, and changing the return code from 1 to 0.
   * Thus we need to fold stdout and stderr together, and ignore the
   * return code.
   */
  ignore_value (commandf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,
                          "mkswap", "--help", NULL));

  av = strstr (err, "-U") != NULL;
  free (err);
  return av;
}

static int
mkswap (const char *device, const char *flag, const char *value)
{
  char *err;
  int r;

  if (!flag)
    r = command (NULL, &err, "mkswap", "-f", device, NULL);
  else
    r = command (NULL, &err, "mkswap", "-f", flag, value, device, NULL);

  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);

  return 0;
}

int
do_mkswap (const char *device)
{
  return mkswap (device, NULL, NULL);
}

int
do_mkswap_L (const char *label, const char *device)
{
  if (strlen (label) > SWAP_LABEL_MAX) {
    reply_with_error ("%s: Linux swap labels are limited to %d bytes",
                      label, SWAP_LABEL_MAX);
    return -1;
  }

  return mkswap (device, "-L", label);
}

int
do_mkswap_U (const char *uuid, const char *device)
{
  return mkswap (device, "-U", uuid);
}

int
do_mkswap_file (const char *path)
{
  char *buf;
  int r;

  buf = sysroot_path (path);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = mkswap (buf, NULL, NULL);
  free (buf);
  return r;
}

static int
swaponoff (const char *cmd, const char *flag, const char *value)
{
  char *err;
  int r;

  if (!flag)
    r = command (NULL, &err, cmd, value, NULL);
  else
    r = command (NULL, &err, cmd, flag, value, NULL);

  if (r == -1) {
    reply_with_error ("%s: %s", value, err);
    free (err);
    return -1;
  }

  free (err);

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
  char *buf;
  int r;

  buf = sysroot_path (path);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = swaponoff ("swapon", NULL, buf);
  free (buf);
  return r;
}

int
do_swapoff_file (const char *path)
{
  char *buf;
  int r;

  buf = sysroot_path (path);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = swaponoff ("swapoff", NULL, buf);
  free (buf);
  return r;
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
