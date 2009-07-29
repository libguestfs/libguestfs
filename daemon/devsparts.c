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
#include <fcntl.h>
#include <dirent.h>
#include <sys/stat.h>

#include "daemon.h"
#include "actions.h"

char **
do_list_devices (void)
{
  char **r = NULL;
  int size = 0, alloc = 0;
  DIR *dir;
  struct dirent *d;
  char buf[256];

  dir = opendir ("/sys/block");
  if (!dir) {
    reply_with_perror ("opendir: /sys/block");
    return NULL;
  }

  while ((d = readdir (dir)) != NULL) {
    if (strncmp (d->d_name, "sd", 2) == 0 ||
	strncmp (d->d_name, "hd", 2) == 0 ||
	strncmp (d->d_name, "vd", 2) == 0) {
      snprintf (buf, sizeof buf, "/dev/%s", d->d_name);

      /* RHBZ#514505: Some versions of qemu <= 0.10 add a
       * CD-ROM device even though we didn't request it.  Try to
       * detect this by seeing if the device contains media.
       */
      int fd = open (buf, O_RDONLY);
      if (fd == -1) {
	perror (buf);
	continue;
      }
      close (fd);

      if (add_string (&r, &size, &alloc, buf) == -1) {
	closedir (dir);
	return NULL;
      }
    }
  }

  if (add_string (&r, &size, &alloc, NULL) == -1) {
    closedir (dir);
    return NULL;
  }

  if (closedir (dir) == -1) {
    reply_with_perror ("closedir: /sys/block");
    free_strings (r);
    return NULL;
  }

  sort_strings (r, size-1);
  return r;
}

char **
do_list_partitions (void)
{
  char **r = NULL;
  int size = 0, alloc = 0;
  DIR *dir, *dir2;
  struct dirent *d;
  char buf[256], devname[256];

  dir = opendir ("/sys/block");
  if (!dir) {
    reply_with_perror ("opendir: /sys/block");
    return NULL;
  }

  while ((d = readdir (dir)) != NULL) {
    if (strncmp (d->d_name, "sd", 2) == 0 ||
	strncmp (d->d_name, "hd", 2) == 0 ||
	strncmp (d->d_name, "vd", 2) == 0) {
      snprintf (buf, sizeof buf, "/dev/%s", d->d_name);

      /* RHBZ#514505: Some versions of qemu <= 0.10 add a
       * CD-ROM device even though we didn't request it.  Try to
       * detect this by seeing if the device contains media.
       */
      int fd = open (buf, O_RDONLY);
      if (fd == -1) {
	perror (buf);
	continue;
      }
      close (fd);

      strncpy (devname, d->d_name, sizeof devname);
      devname[sizeof devname - 1] = '\0';

      snprintf (buf, sizeof buf, "/sys/block/%s", devname);

      dir2 = opendir (buf);
      if (!dir2) {
	reply_with_perror ("opendir: %s", buf);
	free_stringslen (r, size);
	return NULL;
      }
      while ((d = readdir (dir2)) != NULL) {
	if (strncmp (d->d_name, devname, strlen (devname)) == 0) {
	  snprintf (buf, sizeof buf, "/dev/%s", d->d_name);

	  if (add_string (&r, &size, &alloc, buf) == -1) {
	    closedir (dir2);
	    closedir (dir);
	    return NULL;
	  }
	}
      }

      if (closedir (dir2) == -1) {
	reply_with_perror ("closedir: /sys/block/%s", devname);
	free_stringslen (r, size);
	return NULL;
      }
    }
  }

  if (add_string (&r, &size, &alloc, NULL) == -1) {
    closedir (dir);
    return NULL;
  }

  if (closedir (dir) == -1) {
    reply_with_perror ("closedir: /sys/block");
    free_strings (r);
    return NULL;
  }

  sort_strings (r, size-1);
  return r;
}

int
do_mkfs (char *fstype, char *device)
{
  char *err;
  int r;

  IS_DEVICE (device, -1);

  r = command (NULL, &err, "/sbin/mkfs", "-t", fstype, device, NULL);
  if (r == -1) {
    reply_with_error ("mkfs: %s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}
