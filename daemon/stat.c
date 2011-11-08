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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

guestfs_int_stat *
do_stat (const char *path)
{
  int r;
  guestfs_int_stat *ret;
  struct stat statbuf;

  CHROOT_IN;
  r = stat (path, &statbuf);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
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
#ifdef HAVE_STRUCT_STAT_ST_BLKSIZE
  ret->blksize = statbuf.st_blksize;
#else
  ret->blksize = -1;
#endif
#ifdef HAVE_STRUCT_STAT_ST_BLOCKS
  ret->blocks = statbuf.st_blocks;
#else
  ret->blocks = -1;
#endif
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

  CHROOT_IN;
  r = lstat (path, &statbuf);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
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
#ifdef HAVE_STRUCT_STAT_ST_BLKSIZE
  ret->blksize = statbuf.st_blksize;
#else
  ret->blksize = -1;
#endif
#ifdef HAVE_STRUCT_STAT_ST_BLOCKS
  ret->blocks = statbuf.st_blocks;
#else
  ret->blocks = -1;
#endif
  ret->atime = statbuf.st_atime;
  ret->mtime = statbuf.st_mtime;
  ret->ctime = statbuf.st_ctime;

  return ret;
}

guestfs_int_stat_list *
do_lstatlist (const char *path, char *const *names)
{
  int path_fd;
  guestfs_int_stat_list *ret;
  size_t i, nr_names;

  nr_names = count_strings (names);

  ret = malloc (sizeof *ret);
  if (!ret) {
    reply_with_perror ("malloc");
    return NULL;
  }
  ret->guestfs_int_stat_list_len = nr_names;
  ret->guestfs_int_stat_list_val = calloc (nr_names, sizeof (guestfs_int_stat));
  if (ret->guestfs_int_stat_list_val == NULL) {
    reply_with_perror ("malloc");
    free (ret);
    return NULL;
  }

  CHROOT_IN;
  path_fd = open (path, O_RDONLY | O_DIRECTORY);
  CHROOT_OUT;

  if (path_fd == -1) {
    reply_with_perror ("%s", path);
    free (ret->guestfs_int_stat_list_val);
    free (ret);
    return NULL;
  }

  for (i = 0; names[i] != NULL; ++i) {
    int r;
    struct stat statbuf;

    r = fstatat (path_fd, names[i], &statbuf, AT_SYMLINK_NOFOLLOW);
    if (r == -1)
      ret->guestfs_int_stat_list_val[i].ino = -1;
    else {
      ret->guestfs_int_stat_list_val[i].dev = statbuf.st_dev;
      ret->guestfs_int_stat_list_val[i].ino = statbuf.st_ino;
      ret->guestfs_int_stat_list_val[i].mode = statbuf.st_mode;
      ret->guestfs_int_stat_list_val[i].nlink = statbuf.st_nlink;
      ret->guestfs_int_stat_list_val[i].uid = statbuf.st_uid;
      ret->guestfs_int_stat_list_val[i].gid = statbuf.st_gid;
      ret->guestfs_int_stat_list_val[i].rdev = statbuf.st_rdev;
      ret->guestfs_int_stat_list_val[i].size = statbuf.st_size;
#ifdef HAVE_STRUCT_STAT_ST_BLKSIZE
      ret->guestfs_int_stat_list_val[i].blksize = statbuf.st_blksize;
#else
      ret->guestfs_int_stat_list_val[i].blksize = -1;
#endif
#ifdef HAVE_STRUCT_STAT_ST_BLOCKS
      ret->guestfs_int_stat_list_val[i].blocks = statbuf.st_blocks;
#else
      ret->guestfs_int_stat_list_val[i].blocks = -1;
#endif
      ret->guestfs_int_stat_list_val[i].atime = statbuf.st_atime;
      ret->guestfs_int_stat_list_val[i].mtime = statbuf.st_mtime;
      ret->guestfs_int_stat_list_val[i].ctime = statbuf.st_ctime;
    }
  }

  if (close (path_fd) == -1) {
    reply_with_perror ("close: %s", path);
    free (ret->guestfs_int_stat_list_val);
    free (ret);
    return NULL;
  }

  return ret;
}
