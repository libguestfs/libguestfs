/* libguestfs - the guestfsd daemon
 * Copyright (C) 2012 Red Hat Inc.
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
#include <inttypes.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/stat.h>

#ifdef HAVE_LINUX_FS_H
#include <linux/fs.h>
#endif

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#if defined(HAVE_LINUX_FS_H) && defined(FITRIM)

static int64_t get_filesystem_size (const char *path);

int
optgroup_fstrim_available (void)
{
  return 1;
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_fstrim (const char *path,
           int64_t offset, int64_t length, int64_t minimumfreeextent)
{
  int64_t r = do_fstrim_estimate (path, offset, length, minimumfreeextent);
  return r >= 0 ? 0 : r;
}

/* Takes optional arguments, consult optargs_bitmask. */
int64_t
do_fstrim_estimate (const char *path,
                    int64_t offset, int64_t length, int64_t minimumfreeextent)
{
  CLEANUP_CLOSE int fd = -1;
  int i;
  struct stat sb;
  struct fstrim_range range = { .len = UINT64_MAX };
  int64_t ret = 0;
  int64_t fs_size;

  fs_size = get_filesystem_size (path); /* ignore errors */

  /* XXX util-linux uses realpath here, but it's unclear why that is
   * necessary.  In this code I just open the path directly.
   */
  CHROOT_IN;
  fd = open (path, O_RDONLY);
  CHROOT_OUT;
  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }

  /* The util-linux code also refuses to run unless path is a directory. */
  if (fstat (fd, &sb) == -1) {
    reply_with_perror ("fstat: %s", path);
    return -1;
  }
  if (!S_ISDIR (sb.st_mode)) {
    reply_with_error ("fstrim: %s is not a directory", path);
    return -1;
  }

  /* Suggested by Paolo Bonzini to fix fstrim problem.
   * https://lists.gnu.org/archive/html/qemu-devel/2014-03/msg02978.html
   */
  sync_disks ();

  if ((optargs_bitmask & GUESTFS_FSTRIM_OFFSET_BITMASK)) {
    if (offset < 0) {
      reply_with_error ("offset < 0");
      return -1;
    }
    range.start = offset;
  }

  if ((optargs_bitmask & GUESTFS_FSTRIM_LENGTH_BITMASK)) {
    if (length <= 0) {
      reply_with_error ("length <= 0");
      return -1;
    }
    range.len = length;
  }

  if ((optargs_bitmask & GUESTFS_FSTRIM_MINIMUMFREEEXTENT_BITMASK)) {
    if (minimumfreeextent <= 0) {
      reply_with_error ("minimumfreeextent <= 0");
      return -1;
    }
    range.minlen = minimumfreeextent;
  }

  /* Run the FITRIM operation twice to workaround
   * https://issues.redhat.com/browse/RHEL-88450
   */
  for (i = 0; i < 2; ++i) {
    if (ioctl (fd, FITRIM, &range) == -1) {
      if (errno == EOPNOTSUPP)
        errno = ENOTSUP;
      reply_with_perror ("fstrim: %s", path);
      return -1;
    }
    /* range.len is an estimate of the amount trimmed.  However XFS
     * returns the full device size here, unhelpfully, so ignore that.
     * (XFS brokenness caused by kernel commit 410e8a18f8 ("xfs: don't
     * bother reporting blocks trimmed via FITRIM")).  We can't easily
     * get the device size, but we can get the filesystem size (which
     * is smaller).  Note that fs_size == -1 if there was an error
     * getting the filesystem size, which we ignore.
     */
    if (fs_size == -1 || range.len < fs_size)
      ret += range.len;
  }

  /* Simulate what util-linux fstrim -v prints. */
  if (verbose) {
    if (ret > 0)
      fprintf (stderr, "%s: %" PRIi64 " bytes trimmed\n",
               path, ret);
    else
      fprintf (stderr, "%s: unknown number of bytes trimmed\n", path);
  }

  /* Sync the disks again.  In practice we always call fstrim
   * expecting that afterwards the results are visible in the qemu
   * devices backing the guest.  Depending on the Linux filesystem,
   * fstrim may issue asynch discard requests, so it's not necessarily
   * true that everything has been written out before this point.
   */
  sync_disks ();

  return ret;
}

static int64_t
get_filesystem_size (const char *path)
{
  CLEANUP_FREE char *buf = sysroot_path (path);
  CLEANUP_FREE char *out = NULL, *err = NULL;
  uint64_t size;
  int r;

  if (buf == NULL) {
    perror ("get_device_size: malloc");
    return -1;
  }

  r = command (&out, &err,
               "findmnt",       /* part of util-linux */
               "-n", "-o", "SIZE", "--bytes",
               "--target", buf,
               NULL);
  if (r == -1) {
    fprintf (stderr, "get_device_size: findmnt: %s\n", err);
    return -1;
  }

  if (sscanf (out, "%" SCNu64, &size) != 1) {
    fprintf (stderr, "get_device_size: cannot parse: %s\n", out);
    return -1;
  }

  return size;
}

#else /* ioctl FITRIM not supported */

int
optgroup_fstrim_available (void)
{
  return 0;
}

int
do_fstrim (const char *path,
           int64_t offset, int64_t length, int64_t minimumfreeextent)
{
  reply_with_error_erno (ENOTSUP, "fstrim");
  return -1;
}

int
do_fstrim_estimate (const char *path,
                    int64_t offset, int64_t length, int64_t minimumfreeextent)
{
  reply_with_error_erno (ENOTSUP, "fstrim");
  return -1;
}

#endif
