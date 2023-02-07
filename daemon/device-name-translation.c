/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2023 Red Hat Inc.
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
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <limits.h>
#include <sys/stat.h>
#include <errno.h>
#include <error.h>

#include "c-ctype.h"

#include "daemon.h"

static char **cache;
static size_t cache_size;

/**
 * Cache daemon disk mapping.
 *
 * When the daemon starts up, populate a cache with the contents
 * of /dev/disk/by-path.  It's easiest to use C<ls -lv> here
 * since the names are sorted awkwardly.
 */
void
device_name_translation_init (void)
{
  const char *by_path = "/dev/disk/by-path";
  CLEANUP_FREE char *out = NULL, *err = NULL;
  CLEANUP_FREE_STRING_LIST char **lines = NULL;
  size_t i, j;
  int r;

  r = command (&out, &err, "ls", "-1v", by_path, NULL);
  if (r == -1)
    error (EXIT_FAILURE, 0,
           "failed to initialize device name translation cache: %s", err);

  lines = split_lines (out);
  if (lines == NULL)
    error (EXIT_FAILURE, errno, "split_lines");

  cache_size = guestfs_int_count_strings (lines);
  cache = calloc (cache_size, sizeof (char *));
  if (cache == NULL)
    error (EXIT_FAILURE, errno, "calloc");

  /* Look up each device name.  It should be a symlink to /dev/sdX. */
  for (i = j = 0; i < cache_size; ++i) {
    /* Ignore entries for partitions. */
    if (strstr (lines[i], "-part") == NULL) {
      CLEANUP_FREE char *full;
      char *device;

      if (asprintf (&full, "%s/%s", by_path, lines[i]) == -1)
        error (EXIT_FAILURE, errno, "asprintf");

      device = realpath (full, NULL);
      if (device == NULL)
        error (EXIT_FAILURE, errno, "realpath: %s", full);

      /* Ignore the root device. */
      if (is_root_device (device)) {
        free (device);
        continue;
      }

      cache[j++] = device;
    }
  }

  /* This is the final cache size because we deleted entries above. */
  cache_size = j;
}

/* Free the cache on program exit. */
static void device_name_translation_free (void) __attribute__((destructor));

static void
device_name_translation_free (void)
{
  size_t i;

  for (i = 0; i < cache_size; ++i)
    free (cache[i]);
  free (cache);
  cache = NULL;
  cache_size = 0;
}

/**
 * Perform device name translation.
 *
 * Libguestfs defines a few standard formats for device names.
 * (see also L<guestfs(3)/BLOCK DEVICE NAMING> and
 * L<guestfs(3)/guestfs_canonical_device_name>).  They are:
 *
 * =over 4
 *
 * =item F</dev/sdX[N]>
 *
 * =item F</dev/hdX[N]>
 *
 * =item F</dev/vdX[N]>
 *
 * These mean the Nth partition on the Xth device.  Because
 * Linux no longer enumerates devices in the order they are
 * passed to qemu, we must translate these by looking up
 * the actual device using /dev/disk/by-path/
 *
 * =item F</dev/mdX>
 *
 * =item F</dev/VG/LV>
 *
 * =item F</dev/mapper/...>
 *
 * =item F</dev/dm-N>
 *
 * These are not translated here.
 *
 * =back
 *
 * It returns a newly allocated string which the caller must free.
 *
 * It returns C<NULL> on error.  B<Note> it does I<not> call
 * C<reply_with_*>.
 *
 * We have to open the device and test for C<ENXIO>, because the
 * device nodes may exist in the appliance.
 */
char *
device_name_translation (const char *device)
{
  int fd;
  char *ret = NULL;
  size_t len;

  /* /dev/sdX[N] and aliases like /dev/vdX[N]. */
  if (STRPREFIX (device, "/dev/") &&
      strchr (device+5, '/') == NULL && /* not an LV name */
      device[5] != 'm' && /* not /dev/md - RHBZ#1414682 */
      ((len = strcspn (device+5, "d")) > 0 && len <= 2)) {
    ssize_t i;
    const char *start;
    char dev[16];

    /* Translate to a disk index in /dev/disk/by-path sorted numerically. */
    start = &device[5+len+1];
    len = strspn (start, "abcdefghijklmnopqrstuvwxyz");
    if (len >= sizeof dev - 1) {
      fprintf (stderr, "unparseable device name: %s\n", device);
      return NULL;
    }
    strcpy (dev, start);
    dev[len] = '\0';

    i = guestfs_int_drive_index (dev);
    if (i >= 0 && i < (ssize_t) cache_size) {
      /* Append the partition name if present. */
      if (asprintf (&ret, "%s%s", cache[i], start+len) == -1)
        return NULL;
    }
  }

  /* If we didn't translate it above, continue with the same name. */
  if (ret == NULL) {
    ret = strdup (device);
    if (ret == NULL)
      return NULL;
  }

  /* If the device name is different, print the translation. */
  if (STRNEQ (device, ret))
    fprintf (stderr, "device name translated: %s -> %s\n", device, ret);

  /* Now check the device is openable. */
  fd = open (ret, O_RDONLY|O_CLOEXEC);
  if (fd >= 0) {
    close (fd);
    return ret;
  }

  if (errno != ENXIO && errno != ENOENT) {
    perror (ret);
    free (ret);
    return NULL;
  }

  free (ret);

  /* If the original name begins with "/dev/sd" then try the alternatives. */
  if (!STRPREFIX (device, "/dev/sd"))
    return NULL;
  device += 7;                  /* device == "a1" etc. */

  /* /dev/vd (virtio-blk) */
  if (asprintf (&ret, "/dev/vd%s", device) == -1)
    return NULL;
  fd = open (ret, O_RDONLY|O_CLOEXEC);
  if (fd >= 0) {
    close (fd);
    return ret;
  }
  free (ret);

  /* /dev/hd (old IDE driver) */
  if (asprintf (&ret, "/dev/hd%s", device) == -1)
    return NULL;
  fd = open (ret, O_RDONLY|O_CLOEXEC);
  if (fd >= 0) {
    close (fd);
    return ret;
  }
  free (ret);

  /* User-Mode Linux */
  if (asprintf (&ret, "/dev/ubd%s", device) == -1)
    return NULL;
  fd = open (ret, O_RDONLY|O_CLOEXEC);
  if (fd >= 0) {
    close (fd);
    return ret;
  }
  free (ret);

  return NULL;
}

char *
reverse_device_name_translation (const char *device)
{
  char *ret = NULL;
  size_t i;

  /* Look it up in the cache, and if found return the canonical name.
   * If not found return a copy of the original string.
   */
  for (i = 0; i < cache_size; ++i) {
    const size_t len = strlen (cache[i]);

    if (STREQ (device, cache[i]) ||
        (STRPREFIX (device, cache[i]) && c_isdigit (device[len]))) {
      char drv[16];

      guestfs_int_drive_name (i, drv);
      if (asprintf (&ret, "/dev/sd%s%s", drv, &device[len]) == -1) {
        reply_with_perror ("asprintf");
        return NULL;
      }
      break;
    }
  }

  if (ret == NULL) {
    ret = strdup (device);
    if (ret == NULL) {
      reply_with_perror ("strdup");
      return NULL;
    }
  }

  /* If the device name is different, print the translation. */
  if (STRNEQ (device, ret))
    fprintf (stderr, "reverse device name translated: %s -> %s\n", device, ret);

  return ret;
}
