/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2014 Red Hat Inc.
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
#include <fcntl.h>
#include <dirent.h>
#include <limits.h>
#include <sys/stat.h>

#include "c-ctype.h"

#include "daemon.h"
#include "actions.h"

typedef int (*block_dev_func_t) (const char *dev, struct stringsbuf *r);

/* Execute a given function for each discovered block device */
static char **
foreach_block_device (block_dev_func_t func)
{
  DECLARE_STRINGSBUF (r);
  DIR *dir;
  int err = 0;
  struct dirent *d;
  char dev_path[256];
  int fd;

  dir = opendir ("/sys/block");
  if (!dir) {
    reply_with_perror ("opendir: /sys/block");
    return NULL;
  }

  for (;;) {
    errno = 0;
    d = readdir(dir);
    if (!d) break;

    if (STREQLEN (d->d_name, "sd", 2) ||
        STREQLEN (d->d_name, "hd", 2) ||
        STREQLEN (d->d_name, "ubd", 3) ||
        STREQLEN (d->d_name, "vd", 2) ||
        STREQLEN (d->d_name, "sr", 2)) {
      snprintf (dev_path, sizeof dev_path, "/dev/%s", d->d_name);

      /* Ignore the root device. */
      if (is_root_device (dev_path))
        continue;

      /* RHBZ#514505: Some versions of qemu <= 0.10 add a
       * CD-ROM device even though we didn't request it.  Try to
       * detect this by seeing if the device contains media.
       */
      fd = open (dev_path, O_RDONLY|O_CLOEXEC);
      if (fd == -1) {
        perror (dev_path);
        continue;
      }
      close (fd);

      /* Call the map function for this device */
      if ((*func)(d->d_name, &r) != 0) {
        err = 1;
        break;
      }
    }
  }

  /* Check readdir didn't fail */
  if (errno != 0) {
    reply_with_perror ("readdir: /sys/block");
    free_stringslen (r.argv, r.size);
    closedir (dir);
    return NULL;
  }

  /* Close the directory handle */
  if (closedir (dir) == -1) {
    reply_with_perror ("closedir: /sys/block");
    free_stringslen (r.argv, r.size);
    return NULL;
  }

  /* Free the result list on error */
  if (err) {
    free_stringslen (r.argv, r.size);
    return NULL;
  }

  /* Sort the devices. */
  if (r.size > 0)
    sort_device_names (r.argv, r.size);

  /* NULL terminate the list */
  if (end_stringsbuf (&r) == -1) {
    return NULL;
  }

  return r.argv;
}

/* Add a device to the list of devices */
static int
add_device (const char *device, struct stringsbuf *r)
{
  char dev_path[256];
  snprintf (dev_path, sizeof dev_path, "/dev/%s", device);

  if (add_string (r, dev_path) == -1) {
    return -1;
  }

  return 0;
}

char **
do_list_devices (void)
{
  return foreach_block_device (add_device);
}

static int
add_partitions (const char *device, struct stringsbuf *r)
{
  char devdir[256];

  /* Open the device's directory under /sys/block */
  snprintf (devdir, sizeof devdir, "/sys/block/%s", device);

  DIR *dir = opendir (devdir);
  if (!dir) {
    reply_with_perror ("opendir: %s", devdir);
    free_stringslen (r->argv, r->size);
    return -1;
  }

  /* Look in /sys/block/<device>/ for entries starting with <device>
   * e.g. /sys/block/sda/sda1
   */
  errno = 0;
  struct dirent *d;
  while ((d = readdir (dir)) != NULL) {
    if (STREQLEN (d->d_name, device, strlen (device))) {
      char part[256];
      snprintf (part, sizeof part, "/dev/%s", d->d_name);

      if (add_string (r, part) == -1) {
        closedir (dir);
        return -1;
      }
    }
  }

  /* Check if readdir failed */
  if (0 != errno) {
      reply_with_perror ("readdir: %s", devdir);
      free_stringslen (r->argv, r->size);
      closedir (dir);
      return -1;
  }

  /* Close the directory handle */
  if (closedir (dir) == -1) {
    reply_with_perror ("closedir: /sys/block/%s", device);
    free_stringslen (r->argv, r->size);
    return -1;
  }

  return 0;
}

char **
do_list_partitions (void)
{
  return foreach_block_device (add_partitions);
}

char *
do_part_to_dev (const char *part)
{
  int err = 1;
  size_t n = strlen (part);

  while (n >= 1 && c_isdigit (part[n-1])) {
    err = 0;
    n--;
  }

  if (err) {
    reply_with_error ("device name is not a partition");
    return NULL;
  }

  char *r = strndup (part, n);
  if (r == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }

  return r;
}

int
do_part_to_partnum (const char *part)
{
  int err = 1;
  size_t n = strlen (part);

  while (n >= 1 && c_isdigit (part[n-1])) {
    err = 0;
    n--;
  }

  if (err) {
    reply_with_error ("device name is not a partition");
    return -1;
  }

  int r;
  if (sscanf (&part[n], "%d", &r) != 1) {
    reply_with_error ("could not parse number");
    return -1;
  }

  return r;
}

int
do_is_whole_device (const char *device)
{
  /* A 'whole' block device will have a symlink to the device in its
   * /sys/block directory */
  CLEANUP_FREE char *devpath = NULL;
  if (asprintf (&devpath, "/sys/block/%s/device",
                device + strlen ("/dev/")) == -1)
  {
    reply_with_perror ("asprintf");
    return -1;
  }

  struct stat statbuf;
  if (stat (devpath, &statbuf) == -1) {
    if (errno == ENOENT || errno == ENOTDIR) return 0;

    reply_with_perror ("stat");
    return -1;
  }

  return 1;
}

int
do_device_index (const char *device)
{
  size_t i;
  int ret = -1;
  CLEANUP_FREE_STRING_LIST char **devices = do_list_devices ();

  if (devices == NULL)
    return -1;

  for (i = 0; devices[i] != NULL; ++i) {
    if (STREQ (device, devices[i]))
      ret = (int) i;
  }

  if (ret == -1)
    reply_with_error ("device not found");

  return ret;
}

int
do_nr_devices (void)
{
  size_t i;
  CLEANUP_FREE_STRING_LIST char **devices = do_list_devices ();

  if (devices == NULL)
    return -1;

  for (i = 0; devices[i] != NULL; ++i)
    ;

  return (int) i;
}

#define GUESTFSDIR "/dev/disk/guestfs"

char **
do_list_disk_labels (void)
{
  DIR *dir = NULL;
  struct dirent *d;
  char *rawdev = NULL;
  DECLARE_STRINGSBUF (ret);

  dir = opendir (GUESTFSDIR);
  if (!dir) {
    reply_with_perror ("opendir: %s", GUESTFSDIR);
    return NULL;
  }

  errno = 0;
  while ((d = readdir (dir)) != NULL) {
    CLEANUP_FREE char *path = NULL;

    if (d->d_name[0] == '.')
      continue;

    if (asprintf (&path, "%s/%s", GUESTFSDIR, d->d_name) == -1) {
      reply_with_perror ("asprintf");
      free_stringslen (ret.argv, ret.size);
      goto error;
    }

    rawdev = realpath (path, NULL);
    if (rawdev == NULL) {
      reply_with_perror ("realpath: %s", path);
      free_stringslen (ret.argv, ret.size);
      goto error;
    }

    if (add_string (&ret, d->d_name) == -1)
      goto error;

    if (add_string_nodup (&ret, rawdev) == -1)
      goto error;
    rawdev = NULL;            /* buffer now owned by the stringsbuf */
  }

  /* Check readdir didn't fail */
  if (errno != 0) {
    reply_with_perror ("readdir: %s", GUESTFSDIR);
    free_stringslen (ret.argv, ret.size);
    goto error;
  }

  /* Close the directory handle */
  if (closedir (dir) == -1) {
    reply_with_perror ("closedir: %s", GUESTFSDIR);
    free_stringslen (ret.argv, ret.size);
    dir = NULL;
    goto error;
  }

  dir = NULL;

  if (end_stringsbuf (&ret) == -1)
    goto error;

  return ret.argv;              /* caller frees */

 error:
  if (dir)
    closedir (dir);
  free (rawdev);
  return NULL;
}
