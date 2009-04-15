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
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

guestfs_int_stat *
do_stat (const char *path)
{
  int r;
  guestfs_int_stat *ret;
  struct stat statbuf;

  NEED_ROOT (NULL);
  ABS_PATH (path, NULL);

  CHROOT_IN;
  r = stat (path, &statbuf);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("stat");
    return NULL;
  }

  ret = malloc (sizeof *ret);
  if (ret == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  ret->dev = statbuf.st_dev;
  ret->ino = statbuf.st_ino;
  ret->mode = statbuf.st_mode;
  ret->nlink = statbuf.st_nlink;
  ret->uid = statbuf.st_uid;
  ret->gid = statbuf.st_gid;
  ret->rdev = statbuf.st_rdev;
  ret->size = statbuf.st_size;
  ret->blksize = statbuf.st_blksize;
  ret->blocks = statbuf.st_blocks;
  ret->atime = statbuf.st_atime;
  ret->mtime = statbuf.st_mtime;
  ret->ctime = statbuf.st_ctime;

  return ret;
}

guestfs_int_stat *
do_lstat (const char *path)
{
  int r;
  guestfs_int_stat *ret;
  struct stat statbuf;

  NEED_ROOT (NULL);
  ABS_PATH (path, NULL);

  CHROOT_IN;
  r = lstat (path, &statbuf);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("stat");
    return NULL;
  }

  ret = malloc (sizeof *ret);
  if (ret == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  ret->dev = statbuf.st_dev;
  ret->ino = statbuf.st_ino;
  ret->mode = statbuf.st_mode;
  ret->nlink = statbuf.st_nlink;
  ret->uid = statbuf.st_uid;
  ret->gid = statbuf.st_gid;
  ret->rdev = statbuf.st_rdev;
  ret->size = statbuf.st_size;
  ret->blksize = statbuf.st_blksize;
  ret->blocks = statbuf.st_blocks;
  ret->atime = statbuf.st_atime;
  ret->mtime = statbuf.st_mtime;
  ret->ctime = statbuf.st_ctime;

  return ret;
}

guestfs_int_statvfs *
do_statvfs (const char *path)
{
  int r;
  guestfs_int_statvfs *ret;
  struct statvfs statbuf;

  NEED_ROOT (NULL);
  ABS_PATH (path, NULL);

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
}
