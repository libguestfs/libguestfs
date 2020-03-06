/* libguestfs - the guestfsd daemon
 * Copyright (C) 2011 Red Hat Inc.
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
#include <limits.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <fcntl.h>

#include "ignore-value.h"

#include "daemon.h"
#include "actions.h"

#define BUS_PATH "/sys/bus/virtio/drivers/9pnet_virtio"

static void
modprobe_9pnet_virtio (void)
{
  /* Required with Linux 5.6 and maybe earlier kernels.  For unclear
   * reasons the module is not an automatic dependency of the 9p
   * module so doesn't get loaded automatically.
   */
  ignore_value (command (NULL, NULL, "modprobe", "9pnet_virtio", NULL));
}

/* https://bugzilla.redhat.com/show_bug.cgi?id=714981#c1 */
char **
do_list_9p (void)
{
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (r);
  DIR *dir;

  modprobe_9pnet_virtio ();

  dir = opendir (BUS_PATH);
  if (!dir) {
    perror ("opendir: " BUS_PATH);
    if (errno != ENOENT) {
      reply_with_perror ("opendir: " BUS_PATH);
      return NULL;
    }

    /* If this directory doesn't exist, it probably means that
     * the virtio driver isn't loaded.  Don't return an error
     * in this case, but return an empty list.
     */
    if (end_stringsbuf (&r) == -1)
      return NULL;

    return take_stringsbuf (&r);
  }

  while (1) {
    struct dirent *d;

    errno = 0;
    d = readdir (dir);
    if (d == NULL) break;

    if (STRPREFIX (d->d_name, "virtio")) {
      CLEANUP_FREE char *mount_tag_path = NULL;
      if (asprintf (&mount_tag_path, BUS_PATH "/%s/mount_tag",
                    d->d_name) == -1) {
        reply_with_perror ("asprintf");
        closedir (dir);
        return NULL;
      }

      /* A bit unclear, but it looks like the virtio transport allows
       * the mount tag length to be unlimited (or up to 65536 bytes).
       * See: linux/include/linux/virtio_9p.h
       */
      CLEANUP_FREE char *mount_tag = read_whole_file (mount_tag_path, NULL);
      if (mount_tag == 0)
        continue;

      if (add_string (&r, mount_tag) == -1) {
        closedir (dir);
        return NULL;
      }
    }
  }

  /* Check readdir didn't fail */
  if (errno != 0) {
    reply_with_perror ("readdir: /sys/block");
    closedir (dir);
    return NULL;
  }

  /* Close the directory handle */
  if (closedir (dir) == -1) {
    reply_with_perror ("closedir: /sys/block");
    return NULL;
  }

  /* Sort the tags. */
  if (r.size > 0)
    sort_strings (r.argv, r.size);

  /* NULL terminate the list */
  if (end_stringsbuf (&r) == -1)
    return NULL;

  return take_stringsbuf (&r);
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_mount_9p (const char *mount_tag, const char *mountpoint, const char *options)
{
  CLEANUP_FREE char *mp = NULL, *opts = NULL, *err = NULL;
  struct stat statbuf;
  int r;

  ABS_PATH (mountpoint, 0, return -1);

  mp = sysroot_path (mountpoint);
  if (!mp) {
    reply_with_perror ("malloc");
    return -1;
  }

  /* Check the mountpoint exists and is a directory. */
  if (stat (mp, &statbuf) == -1) {
    reply_with_perror ("%s", mountpoint);
    return -1;
  }
  if (!S_ISDIR (statbuf.st_mode)) {
    reply_with_perror ("%s: mount point is not a directory", mountpoint);
    return -1;
  }

  /* Add trans=virtio to the options. */
  if ((optargs_bitmask & GUESTFS_MOUNT_9P_OPTIONS_BITMASK) &&
      STRNEQ (options, "")) {
    if (asprintf (&opts, "trans=virtio,%s", options) == -1) {
      reply_with_perror ("asprintf");
      return -1;
    }
  }
  else {
    opts = strdup ("trans=virtio");
    if (opts == NULL) {
      reply_with_perror ("strdup");
      return -1;
    }
  }

  modprobe_9pnet_virtio ();
  r = command (NULL, &err,
               "mount", "-o", opts, "-t", "9p", mount_tag, mp, NULL);
  if (r == -1) {
    reply_with_error ("%s on %s: %s", mount_tag, mountpoint, err);
    return -1;
  }

  return 0;
}
