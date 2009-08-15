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

typedef int (*block_dev_func_t)(const char *dev,
                                char ***r, int *size, int *alloc);

/* Execute a given function for each discovered block device */
static char**
foreach_block_device (block_dev_func_t func)
{
  char **r = NULL;
  int size = 0, alloc = 0;

  DIR *dir;
  int err = 0;

  dir = opendir ("/sys/block");
  if (!dir) {
    reply_with_perror ("opendir: /sys/block");
    return NULL;
  }

  while(1) {
    errno = 0;
    struct dirent *d = readdir(dir);
    if(NULL == d) break;

    if (strncmp (d->d_name, "sd", 2) == 0 ||
        strncmp (d->d_name, "hd", 2) == 0 ||
        strncmp (d->d_name, "vd", 2) == 0 ||
        strncmp (d->d_name, "sr", 2) == 0) {
      char dev_path[256];
      snprintf (dev_path, sizeof dev_path, "/dev/%s", d->d_name);

      /* RHBZ#514505: Some versions of qemu <= 0.10 add a
       * CD-ROM device even though we didn't request it.  Try to
       * detect this by seeing if the device contains media.
       */
      int fd = open (dev_path, O_RDONLY);
      if (fd == -1) {
        perror (dev_path);
        continue;
      }
      close (fd);

      /* Call the map function for this device */
      if((*func)(d->d_name, &r, &size, &alloc) != 0) {
        err = 1;
        break;
      }
    }
  }

  /* Check readdir didn't fail */
  if(0 != errno) {
    reply_with_perror ("readdir: /sys/block");
    free_stringslen(r, size);
    return NULL;
  }

  /* Close the directory handle */
  if (closedir (dir) == -1) {
    reply_with_perror ("closedir: /sys/block");
    free_stringslen(r, size);
    return NULL;
  }

  /* Free the result list on error */
  if(err) {
    free_stringslen(r, size);
    return NULL;
  }

  /* Sort the devices */
  sort_strings (r, size);

  /* NULL terminate the list */
  if (add_string (&r, &size, &alloc, NULL) == -1) {
    return NULL;
  }

  return r;
}

/* Add a device to the list of devices */
static int
add_device(const char *device,
           char ***const r, int *const size, int *const alloc)
{
  char dev_path[256];
  snprintf (dev_path, sizeof dev_path, "/dev/%s", device);

  if (add_string (r, size, alloc, dev_path) == -1) {
    return -1;
  }

  return 0;
}

char **
do_list_devices (void)
{
  return foreach_block_device(add_device);
}

static int
add_partitions(const char *device,
               char ***const r, int *const size, int *const alloc)
{
  char devdir[256];

  /* Open the device's directory under /sys/block */
  snprintf (devdir, sizeof devdir, "/sys/block/%s", device);

  DIR *dir = opendir (devdir);
  if (!dir) {
    reply_with_perror ("opendir: %s", devdir);
    free_stringslen (*r, *size);
    return -1;
  }

  /* Look in /sys/block/<device>/ for entries starting with <device>
   * e.g. /sys/block/sda/sda1
   */
  errno = 0;
  struct dirent *d;
  while ((d = readdir (dir)) != NULL) {
    if (strncmp (d->d_name, device, strlen (device)) == 0) {
      char part[256];
      snprintf (part, sizeof part, "/dev/%s", d->d_name);

      if (add_string (r, size, alloc, part) == -1) {
        closedir (dir);
        return -1;
      }
    }
  }

  /* Check if readdir failed */
  if(0 != errno) {
      reply_with_perror ("readdir: %s", devdir);
      free_stringslen(*r, *size);
      return -1;
  }

  /* Close the directory handle */
  if (closedir (dir) == -1) {
    reply_with_perror ("closedir: /sys/block/%s", device);
    free_stringslen (*r, *size);
    return -1;
  }

  return 0;
}

char **
do_list_partitions (void)
{
  return foreach_block_device(add_partitions);
}
