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

static guestfs_int_statns *
stat_to_statns (guestfs_int_statns *ret, const struct stat *statbuf)
{
  if (ret == NULL) {
    ret = malloc (sizeof *ret);
    if (ret == NULL) {
      reply_with_perror ("malloc");
      return NULL;
    }
  }

  ret->st_dev = statbuf->st_dev;
  ret->st_ino = statbuf->st_ino;
  ret->st_mode = statbuf->st_mode;
  ret->st_nlink = statbuf->st_nlink;
  ret->st_uid = statbuf->st_uid;
  ret->st_gid = statbuf->st_gid;
  ret->st_rdev = statbuf->st_rdev;
  ret->st_size = statbuf->st_size;
#ifdef HAVE_STRUCT_STAT_ST_BLKSIZE
  ret->st_blksize = statbuf->st_blksize;
#else
  ret->st_blksize = -1;
#endif
#ifdef HAVE_STRUCT_STAT_ST_BLOCKS
  ret->st_blocks = statbuf->st_blocks;
#else
  ret->st_blocks = -1;
#endif
  ret->st_atime_sec = statbuf->st_atime;
#ifdef HAVE_STRUCT_STAT_ST_ATIM_TV_NSEC
  ret->st_atime_nsec = statbuf->st_atim.tv_nsec;
#else
  ret->st_atime_nsec = 0;
#endif
  ret->st_mtime_sec = statbuf->st_mtime;
#ifdef HAVE_STRUCT_STAT_ST_MTIM_TV_NSEC
  ret->st_mtime_nsec = statbuf->st_mtim.tv_nsec;
#else
  ret->st_mtime_nsec = 0;
#endif
  ret->st_ctime_sec = statbuf->st_ctime;
#ifdef HAVE_STRUCT_STAT_ST_CTIM_TV_NSEC
  ret->st_ctime_nsec = statbuf->st_ctim.tv_nsec;
#else
  ret->st_ctime_nsec = 0;
#endif

  ret->st_spare1 = ret->st_spare2 = ret->st_spare3 =
    ret->st_spare4 = ret->st_spare5 = ret->st_spare6 = 0;

  return ret;
}

guestfs_int_statns *
do_statns (const char *path)
{
  int r;
  struct stat statbuf;

  CHROOT_IN;
  r = stat (path, &statbuf);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    return NULL;
  }

  return stat_to_statns (NULL, &statbuf);
}

guestfs_int_statns *
do_lstatns (const char *path)
{
  int r;
  struct stat statbuf;

  CHROOT_IN;
  r = lstat (path, &statbuf);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    return NULL;
  }

  return stat_to_statns (NULL, &statbuf);
}

guestfs_int_statns_list *
do_internal_lstatnslist (const char *path, char *const *names)
{
  int path_fd;
  guestfs_int_statns_list *ret;
  size_t i, nr_names;

  nr_names = guestfs_int_count_strings (names);

  ret = malloc (sizeof *ret);
  if (!ret) {
    reply_with_perror ("malloc");
    return NULL;
  }
  ret->guestfs_int_statns_list_len = nr_names;
  ret->guestfs_int_statns_list_val =
    calloc (nr_names, sizeof (guestfs_int_statns));
  if (ret->guestfs_int_statns_list_val == NULL) {
    reply_with_perror ("calloc");
    free (ret);
    return NULL;
  }

  CHROOT_IN;
  path_fd = open (path, O_RDONLY|O_DIRECTORY|O_CLOEXEC);
  CHROOT_OUT;

  if (path_fd == -1) {
    reply_with_perror ("%s", path);
    free (ret->guestfs_int_statns_list_val);
    free (ret);
    return NULL;
  }

  for (i = 0; names[i] != NULL; ++i) {
    int r;
    struct stat statbuf;

    r = fstatat (path_fd, names[i], &statbuf, AT_SYMLINK_NOFOLLOW);
    if (r == -1)
      ret->guestfs_int_statns_list_val[i].st_ino = -1;
    else
      stat_to_statns (&ret->guestfs_int_statns_list_val[i], &statbuf);
  }

  if (close (path_fd) == -1) {
    reply_with_perror ("close: %s", path);
    free (ret->guestfs_int_statns_list_val);
    free (ret);
    return NULL;
  }

  return ret;
}
