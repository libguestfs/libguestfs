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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

/* Convenient place to test for the later version of e2fsprogs
 * and util-linux which supports -U parameters to specify UUIDs.
 * (Not supported in RHEL 5).
 */
int
optgroup_linuxfsuuid_available (void)
{
  char *err;
  int av;

  /* Ignore return code - mkswap --help *will* fail. */
  command (NULL, &err, "/sbin/mkswap", "--help", NULL);

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
    r = command (NULL, &err, "/sbin/mkswap", "-f", device, NULL);
  else
    r = command (NULL, &err, "/sbin/mkswap", "-f", flag, value, device, NULL);

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

  return 0;
}

int
do_swapon_device (const char *device)
{
  return swaponoff ("/sbin/swapon", NULL, device);
}

int
do_swapoff_device (const char *device)
{
  return swaponoff ("/sbin/swapoff", NULL, device);
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

  r = swaponoff ("/sbin/swapon", NULL, buf);
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

  r = swaponoff ("/sbin/swapoff", NULL, buf);
  free (buf);
  return r;
}

int
do_swapon_label (const char *label)
{
  return swaponoff ("/sbin/swapon", "-L", label);
}

int
do_swapoff_label (const char *label)
{
  return swaponoff ("/sbin/swapoff", "-L", label);
}

int
do_swapon_uuid (const char *uuid)
{
  return swaponoff ("/sbin/swapon", "-U", uuid);
}

int
do_swapoff_uuid (const char *uuid)
{
  return swaponoff ("/sbin/swapoff", "-U", uuid);
}
