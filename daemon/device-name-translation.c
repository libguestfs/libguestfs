/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2017 Red Hat Inc.
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

#include "daemon.h"

/**
 * Perform device name translation.
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
  char *ret;

  fd = open (device, O_RDONLY|O_CLOEXEC);
  if (fd >= 0) {
    close (fd);
    return strdup (device);
  }

  if (errno != ENXIO && errno != ENOENT)
    return NULL;

  /* If the name begins with "/dev/sd" then try the alternatives. */
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
  char *ret;

  /* Currently a no-op. */
  ret = strdup (device);
  if (ret == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }

  return ret;
}
