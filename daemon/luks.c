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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "daemon.h"
#include "c-ctype.h"
#include "actions.h"
#include "optgroups.h"

int
optgroup_luks_available (void)
{
  return prog_exists ("cryptsetup");
}

static int
luks_open (const char *device, const char *key, const char *mapname,
           int readonly)
{
  /* Sanity check: /dev/mapper/mapname must not exist already.  Note
   * that the device-mapper control device (/dev/mapper/control) is
   * always there, so you can't ever have mapname == "control".
   */
  size_t len = strlen (mapname);
  char devmapper[len+32];
  snprintf (devmapper, len+32, "/dev/mapper/%s", mapname);
  if (access (devmapper, F_OK) == 0) {
    reply_with_error ("%s: device already exists", devmapper);
    return -1;
  }

  char tempfile[] = "/tmp/luksXXXXXX";
  int fd = mkstemp (tempfile);
  if (fd == -1) {
    reply_with_perror ("mkstemp");
    return -1;
  }

  len = strlen (key);
  if (xwrite (fd, key, len) == -1) {
    reply_with_perror ("write");
    close (fd);
    unlink (tempfile);
    return -1;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close");
    unlink (tempfile);
    return -1;
  }

  const char *argv[16];
  size_t i = 0;

  argv[i++] = "cryptsetup";
  argv[i++] = "-d";
  argv[i++] = tempfile;
  if (readonly) argv[i++] = "--readonly";
  argv[i++] = "luksOpen";
  argv[i++] = device;
  argv[i++] = mapname;
  argv[i++] = NULL;

  char *err;
  int r = commandv (NULL, &err, (const char * const *) argv);
  unlink (tempfile);

  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);

  udev_settle ();

  return 0;
}

int
do_luks_open (const char *device, const char *key, const char *mapname)
{
  return luks_open (device, key, mapname, 0);
}

int
do_luks_open_ro (const char *device, const char *key, const char *mapname)
{
  return luks_open (device, key, mapname, 1);
}

int
do_luks_close (const char *device)
{
  /* Must be /dev/mapper/... */
  if (! STRPREFIX (device, "/dev/mapper/")) {
    reply_with_error ("luks_close: you must call this on the /dev/mapper device created by luks_open");
    return -1;
  }

  const char *mapname = &device[12];

  char *err;
  int r = command (NULL, &err, "cryptsetup", "luksClose", mapname, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);

  udev_settle ();

  return 0;
}
