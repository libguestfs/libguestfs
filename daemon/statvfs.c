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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#ifdef HAVE_WINDOWS_H
#include <windows.h>
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>

#ifdef HAVE_SYS_STATVFS_H
#include <sys/statvfs.h>
#endif

#include <fsusage.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

guestfs_int_statvfs *
do_statvfs (const char *path)
{
#ifdef HAVE_STATVFS
  int r;
  guestfs_int_statvfs *ret;
  struct statvfs statbuf;

  CHROOT_IN;
  r = statvfs (path, &statbuf);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("statvfs");
    return NULL;
  }

  ret = malloc (sizeof *ret);
  if (ret == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  ret->bsize = statbuf.f_bsize;
  ret->frsize = statbuf.f_frsize;
  ret->blocks = statbuf.f_blocks;
  ret->bfree = statbuf.f_bfree;
  ret->bavail = statbuf.f_bavail;
  ret->files = statbuf.f_files;
  ret->ffree = statbuf.f_ffree;
  ret->favail = statbuf.f_favail;
  ret->fsid = statbuf.f_fsid;
  ret->flag = statbuf.f_flag;
  ret->namemax = statbuf.f_namemax;

  return ret;

#else /* !HAVE_STATVFS */
#  if WIN32

  char *disk;
  guestfs_int_statvfs *ret;
  ULONGLONG free_bytes_available; /* for user - similar to bavail */
  ULONGLONG total_number_of_bytes;
  ULONGLONG total_number_of_free_bytes; /* for everyone - bfree */

  disk = sysroot_path (path);
  if (!disk) {
    reply_with_perror ("malloc");
    return NULL;
  }

  if (!GetDiskFreeSpaceEx (disk,
                           (PULARGE_INTEGER) &free_bytes_available,
                           (PULARGE_INTEGER) &total_number_of_bytes,
                           (PULARGE_INTEGER) &total_number_of_free_bytes)) {
    reply_with_perror ("GetDiskFreeSpaceEx");
    free (disk);
    return NULL;
  }
  free (disk);

  ret = malloc (sizeof *ret);
  if (ret == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  /* XXX I couldn't determine how to get block size.  MSDN has a
   * unhelpful hard-coded list here:
   *   http://support.microsoft.com/kb/140365
   * but this depends on the filesystem type, the size of the disk and
   * the version of Windows.  So this code assumes the disk is NTFS
   * and the version of Windows is >= Win2K.
   */
  if (total_number_of_bytes < UINT64_C(16) * 1024 * 1024 * 1024 * 1024)
    ret->bsize = 4096;
  else if (total_number_of_bytes < UINT64_C(32) * 1024 * 1024 * 1024 * 1024)
    ret->bsize = 8192;
  else if (total_number_of_bytes < UINT64_C(64) * 1024 * 1024 * 1024 * 1024)
    ret->bsize = 16384;
  else if (total_number_of_bytes < UINT64_C(128) * 1024 * 1024 * 1024 * 1024)
    ret->bsize = 32768;
  else
    ret->bsize = 65536;

  /* As with stat, -1 indicates a field is not known. */
  ret->frsize = ret->bsize;
  ret->blocks = total_number_of_bytes / ret->bsize;
  ret->bfree = total_number_of_free_bytes / ret->bsize;
  ret->bavail = free_bytes_available / ret->bsize;
  ret->files = -1;
  ret->ffree = -1;
  ret->favail = -1;
  ret->fsid = -1;
  ret->flag = -1;
  ret->namemax = FILENAME_MAX;

  return ret;

#  else /* !WIN32 */

  char *disk;
  int r;
  guestfs_int_statvfs *ret;
  struct fs_usage fsu;

  disk = sysroot_path (path);
  if (!disk) {
    reply_with_perror ("malloc");
    return NULL;
  }

  r = get_fs_usage (disk, disk, &fsu);
  free (disk);

  if (r == -1) {
    reply_with_perror ("get_fs_usage: %s", path);
    return NULL;
  }

  ret = malloc (sizeof *ret);
  if (ret == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  /* As with stat, -1 indicates a field is not known. */
  ret->bsize = fsu.f_bsize;
  ret->frsize = -1;
  ret->blocks = fsu.f_blocks;
  ret->bfree = fsu.f_bfree;
  ret->bavail = fsu.f_bavail;
  ret->files = fsu.f_files;
  ret->ffree = fsu.f_ffree;
  ret->favail = -1;
  ret->fsid = -1;
  ret->flag = -1;
  ret->namemax = -1;

  return ret;

#  endif /* !WIN32 */
#endif /* !HAVE_STATVFS */
}
