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
#include <unistd.h>
#include <dirent.h>

#include "daemon.h"
#include "actions.h"

guestfs_int_dirent_list *
do_readdir (const char *path)
{
  guestfs_int_dirent_list *ret;
  guestfs_int_dirent v;
  DIR *dir;
  struct dirent *d;
  int i;

  ret = malloc (sizeof *ret);
  if (ret == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  ret->guestfs_int_dirent_list_len = 0;
  ret->guestfs_int_dirent_list_val = NULL;

  CHROOT_IN;
  dir = opendir (path);
  CHROOT_OUT;

  if (dir == NULL) {
    reply_with_perror ("opendir: %s", path);
    free (ret);
    return NULL;
  }

  i = 0;
  while ((d = readdir (dir)) != NULL) {
    guestfs_int_dirent *p;

    p = realloc (ret->guestfs_int_dirent_list_val,
                 sizeof (guestfs_int_dirent) * (i+1));
    v.name = strdup (d->d_name);
    if (!p || !v.name) {
      reply_with_perror ("allocate");
      free (ret->guestfs_int_dirent_list_val);
      free (p);
      free (v.name);
      free (ret);
      closedir (dir);
      return NULL;
    }
    ret->guestfs_int_dirent_list_val = p;

    v.ino = d->d_ino;
#ifdef HAVE_STRUCT_DIRENT_D_TYPE
    switch (d->d_type) {
    case DT_BLK: v.ftyp = 'b'; break;
    case DT_CHR: v.ftyp = 'c'; break;
    case DT_DIR: v.ftyp = 'd'; break;
    case DT_FIFO: v.ftyp = 'f'; break;
    case DT_LNK: v.ftyp = 'l'; break;
    case DT_REG: v.ftyp = 'r'; break;
    case DT_SOCK: v.ftyp = 's'; break;
    case DT_UNKNOWN: v.ftyp = 'u'; break;
    default: v.ftyp = '?'; break;
    }
#else
    v.ftyp = 'u';
#endif

    ret->guestfs_int_dirent_list_val[i] = v;

    i++;
  }

  ret->guestfs_int_dirent_list_len = i;

  if (closedir (dir) == -1) {
    reply_with_perror ("closedir");
    free (ret->guestfs_int_dirent_list_val);
    free (ret);
    return NULL;
  }

  return ret;
}
