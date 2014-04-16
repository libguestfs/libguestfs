/* libguestfs - the guestfsd daemon
 * Copyright (C) 2014 Red Hat Inc.
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
#include <stdint.h>
#include <inttypes.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

#ifdef HAVE_LINUX_FS_H
#include <linux/fs.h>
#endif

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

/* http://rwmj.wordpress.com/2014/03/11/blkdiscard-blkzeroout-blkdiscardzeroes-blksecdiscard/ */

#ifdef BLKDISCARD

int
optgroup_blkdiscard_available (void)
{
  return 1;
}

int
do_blkdiscard (const char *device)
{
  /* XXX We could read /sys/block/<device>/queue/discard_* in order to
   * determine if discard is supported and the largest request size we
   * are allowed to make.  However:
   *
   * (1) Mapping the device name to /sys/block/<device> is quite hard
   * (cf. the lv_canonical function in daemon/lvm.c)
   *
   * (2) We don't really need to do this in modern libguestfs since
   * we're very likely to be using virtio-scsi, which supports
   * arbitrary block discards.
   *
   * Let's wait to see if it causes a problem in real world
   * situations.
   */
  uint64_t range[2];
  int64_t size;
  int fd;

  size = do_blockdev_getsize64 (device);
  if (size == -1)
    return -1;

  range[0] = 0;
  range[1] = (uint64_t) size;

  fd = open (device, O_WRONLY|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("open: %s", device);
    return -1;
  }

  if (ioctl (fd, BLKDISCARD, range) == -1) {
    reply_with_perror ("ioctl: %s: BLKDISCARD", device);
    close (fd);
    return -1;
  }

  close (fd);
  return 0;
}

#else /* !BLKDISCARD */
OPTGROUP_BLKDISCARD_NOT_AVAILABLE
#endif

#ifdef BLKDISCARDZEROES

int
optgroup_blkdiscardzeroes_available (void)
{
  return 1;
}

int
do_blkdiscardzeroes (const char *device)
{
  int fd;
  unsigned int arg;

  fd = open (device, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("open: %s", device);
    return -1;
  }

  if (ioctl (fd, BLKDISCARDZEROES, &arg) == -1) {
    reply_with_perror ("ioctl: %s: BLKDISCARDZEROES", device);
    close (fd);
    return -1;
  }

  close (fd);

  return arg != 0;
}

#else /* !BLKDISCARDZEROES */
OPTGROUP_BLKDISCARDZEROES_NOT_AVAILABLE
#endif
