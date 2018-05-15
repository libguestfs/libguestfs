/* libguestfs - the guestfsd daemon
 * Copyright (C) 2016 Red Hat Inc.
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
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <rpc/types.h>
#include <rpc/xdr.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#ifdef HAVE_LIBTSK

#include <tsk/libtsk.h>

enum tsk_dirent_flags {
  DIRENT_UNALLOC = 0x00,
  DIRENT_ALLOC = 0x01,
  DIRENT_REALLOC = 0x02,
  DIRENT_COMPRESSED = 0x04
};

static int open_filesystem (const char *, TSK_IMG_INFO **, TSK_FS_INFO **);
static TSK_WALK_RET_ENUM fswalk_callback (TSK_FS_FILE *, const char *, void *);
static TSK_WALK_RET_ENUM findino_callback (TSK_FS_FILE *, const char *, void *);
static int send_dirent_info (TSK_FS_FILE *, const char *);
static char file_type (TSK_FS_FILE *);
static int file_flags (TSK_FS_FILE *fsfile);
static void file_metadata (TSK_FS_META *, guestfs_int_tsk_dirent *);
static void reply_with_tsk_error (const char *);
static int entry_is_dot (TSK_FS_FILE *);

int
do_internal_filesystem_walk (const mountable_t *mountable)
{
  int ret = -1;
  TSK_FS_INFO *fs = NULL;
  TSK_IMG_INFO *img = NULL;  /* Used internally by tsk_fs_dir_walk */
  const int flags =
    TSK_FS_DIR_WALK_FLAG_ALLOC | TSK_FS_DIR_WALK_FLAG_UNALLOC |
    TSK_FS_DIR_WALK_FLAG_RECURSE | TSK_FS_DIR_WALK_FLAG_NOORPHAN;

  ret = open_filesystem (mountable->device, &img, &fs);
  if (ret < 0)
    return ret;

  reply (NULL, NULL);  /* Reply message. */

  ret = tsk_fs_dir_walk (fs, fs->root_inum, flags, fswalk_callback, NULL);
  if (ret == 0)
    ret = send_file_end (0);  /* File transfer end. */
  else
    send_file_end (1);  /* Cancel file transfer. */

  fs->close (fs);
  img->close (img);

  return ret;
}

int
do_internal_find_inode (const mountable_t *mountable, int64_t inode)
{
  int ret = -1;
  TSK_FS_INFO *fs = NULL;
  TSK_IMG_INFO *img = NULL;  /* Used internally by tsk_fs_dir_walk */
  const int flags =
    TSK_FS_DIR_WALK_FLAG_ALLOC | TSK_FS_DIR_WALK_FLAG_UNALLOC |
    TSK_FS_DIR_WALK_FLAG_RECURSE | TSK_FS_DIR_WALK_FLAG_NOORPHAN;

  ret = open_filesystem (mountable->device, &img, &fs);
  if (ret < 0)
    return ret;

  reply (NULL, NULL);  /* Reply message. */

  ret = tsk_fs_dir_walk (fs, fs->root_inum, flags,
                         findino_callback, (void *) &inode);
  if (ret == 0)
    ret = send_file_end (0);  /* File transfer end. */
  else
    send_file_end (1);  /* Cancel file transfer. */

  fs->close (fs);
  img->close (img);

  return ret;
}

/* Inspect the device and initialises the img and fs structures.
 * Return 0 on success, -1 on error.
 */
static int
open_filesystem (const char *device, TSK_IMG_INFO **img, TSK_FS_INFO **fs)
{
  const char *images[] = { device };

  *img = tsk_img_open (1, images, TSK_IMG_TYPE_DETECT, 0);
  if (*img == NULL) {
    reply_with_tsk_error ("tsk_image_open");
    return -1;
  }

  *fs = tsk_fs_open_img (*img, 0, TSK_FS_TYPE_DETECT);
  if (*fs == NULL) {
    reply_with_tsk_error ("tsk_fs_open_img");
    (*img)->close (*img);
    return -1;
  }

  return 0;
}

/* Filesystem walk callback, it gets called on every FS node.
 * Parse the node, encode it into an XDR structure and send it to the library.
 * Return TSK_WALK_CONT on success, TSK_WALK_ERROR on error.
 */
static TSK_WALK_RET_ENUM
fswalk_callback (TSK_FS_FILE *fsfile, const char *path, void *data)
{
  int ret = 0;

  if (entry_is_dot (fsfile))
    return TSK_WALK_CONT;

  ret = send_dirent_info (fsfile, path);

  return (ret == 0) ? TSK_WALK_CONT : TSK_WALK_ERROR;
}

/* Find inode, it gets called on every FS node.
 * If the FS node address is the given one, parse it,
 * encode it into an XDR structure and send it to the library.
 * Return TSK_WALK_CONT on success, TSK_WALK_ERROR on error.
 */
static TSK_WALK_RET_ENUM
findino_callback (TSK_FS_FILE *fsfile, const char *path, void *data)
{
  int ret = 0;
  uint64_t *inode = (uint64_t *) data;

  if (*inode != fsfile->name->meta_addr)
    return TSK_WALK_CONT;

  if (entry_is_dot (fsfile))
    return TSK_WALK_CONT;

  ret = send_dirent_info (fsfile, path);

  return (ret == 0) ? TSK_WALK_CONT : TSK_WALK_ERROR;
}

/* Extract the information from the entry, serialize and send it out.
 * Return 0 on success, -1 on error.
 */
static int
send_dirent_info (TSK_FS_FILE *fsfile, const char *path)
{
  XDR xdr;
  int ret = 0;
  size_t len = 0;
  struct guestfs_int_tsk_dirent dirent;
  CLEANUP_FREE char *buf = NULL, *fname = NULL;

  /* Set dirent fields */
  memset (&dirent, 0, sizeof dirent);

  /* Build the full relative path of the entry */
  ret = asprintf (&fname, "%s%s", path, fsfile->name->name);
  if (ret < 0) {
    perror ("asprintf");
    return -1;
  }

  dirent.tsk_inode = fsfile->name->meta_addr;
  dirent.tsk_type = file_type (fsfile);
  dirent.tsk_name = fname;
  dirent.tsk_flags = file_flags (fsfile);

  file_metadata (fsfile->meta, &dirent);

  /* Serialize tsk_dirent struct. */
  buf = malloc (GUESTFS_MAX_CHUNK_SIZE);
  if (buf == NULL) {
    perror ("malloc");
    return -1;
  }

  xdrmem_create (&xdr, buf, GUESTFS_MAX_CHUNK_SIZE, XDR_ENCODE);

  ret = xdr_guestfs_int_tsk_dirent (&xdr, &dirent);
  if (ret == 0) {
    perror ("xdr_guestfs_int_tsk_dirent");
    return -1;
  }

  len = xdr_getpos (&xdr);

  xdr_destroy (&xdr);

  /* Send serialised tsk_dirent out. */
  return send_file_write (buf, len);
}

/* Inspect fsfile to identify its type. */
static char
file_type (TSK_FS_FILE *fsfile)
{
  if (fsfile->name->type < TSK_FS_NAME_TYPE_STR_MAX)
    switch (fsfile->name->type) {
    case TSK_FS_NAME_TYPE_UNDEF: return 'u';
    case TSK_FS_NAME_TYPE_FIFO: return 'f';
    case TSK_FS_NAME_TYPE_CHR: return 'c';
    case TSK_FS_NAME_TYPE_DIR: return 'd';
    case TSK_FS_NAME_TYPE_BLK: return 'b';
    case TSK_FS_NAME_TYPE_REG: return 'r';
    case TSK_FS_NAME_TYPE_LNK: return 'l';
    case TSK_FS_NAME_TYPE_SOCK: return 's';
    case TSK_FS_NAME_TYPE_SHAD: return 'h';
    case TSK_FS_NAME_TYPE_WHT: return 'w';
    case TSK_FS_NAME_TYPE_VIRT: return 'u';  /* Temp files created by TSK */
#if TSK_VERSION_NUM >= 0x040500ff
    case TSK_FS_NAME_TYPE_VIRT_DIR: return 'u';  /* Temp files created by TSK */
#endif
    }
  else if (fsfile->meta != NULL &&
           fsfile->meta->type < TSK_FS_META_TYPE_STR_MAX)
    switch (fsfile->name->type) {
    case TSK_FS_NAME_TYPE_UNDEF: return 'u';
    case TSK_FS_META_TYPE_REG: return 'r';
    case TSK_FS_META_TYPE_DIR: return 'd';
    case TSK_FS_META_TYPE_FIFO: return 'f';
    case TSK_FS_META_TYPE_CHR: return 'c';
    case TSK_FS_META_TYPE_BLK: return 'b';
    case TSK_FS_META_TYPE_LNK: return 'l';
    case TSK_FS_META_TYPE_SHAD: return 'h';
    case TSK_FS_META_TYPE_SOCK: return 's';
    case TSK_FS_META_TYPE_WHT: return 'w';
    case TSK_FS_META_TYPE_VIRT: return 'u';  /* Temp files created by TSK */
#if TSK_VERSION_NUM >= 0x040500ff
    case TSK_FS_META_TYPE_VIRT_DIR: return 'u';  /* Temp files created by TSK */
#endif
    }

  return 'u';
}

/* Inspect fsfile to retrieve file flags. */
static int
file_flags (TSK_FS_FILE *fsfile)
{
  int flags = DIRENT_UNALLOC;

  if (fsfile->name->flags & TSK_FS_NAME_FLAG_UNALLOC) {
    if (fsfile->meta && fsfile->meta->flags & TSK_FS_META_FLAG_ALLOC)
      flags |= DIRENT_REALLOC;
  }
  else
    flags |= DIRENT_ALLOC;

  if (fsfile->meta && fsfile->meta->flags & TSK_FS_META_FLAG_COMP)
    flags |= DIRENT_COMPRESSED;

  return flags;
}

/* Inspect fsfile to retrieve file metadata. */
static void
file_metadata (TSK_FS_META *fsmeta, guestfs_int_tsk_dirent *dirent)
{
  if (fsmeta != NULL) {
    dirent->tsk_size = fsmeta->size;
    dirent->tsk_nlink = fsmeta->nlink;
    dirent->tsk_atime_sec = fsmeta->atime;
    dirent->tsk_atime_nsec = fsmeta->atime_nano;
    dirent->tsk_mtime_sec = fsmeta->mtime;
    dirent->tsk_mtime_nsec = fsmeta->mtime_nano;
    dirent->tsk_ctime_sec = fsmeta->ctime;
    dirent->tsk_ctime_nsec = fsmeta->ctime_nano;
    dirent->tsk_crtime_sec = fsmeta->crtime;
    dirent->tsk_crtime_nsec = fsmeta->crtime_nano;
    /* tsk_link never changes */
    dirent->tsk_link = (fsmeta->link != NULL) ? fsmeta->link : (char *) "";
  }
  else {
    dirent->tsk_size = -1;
    /* tsk_link never changes */
    dirent->tsk_link = (char *) "";
  }
}

/* Parse TSK error and send it to the appliance. */
static void
reply_with_tsk_error (const char *funcname)
{
  int ret = 0;
  const char *buf = NULL;

  ret = tsk_error_get_errno ();
  if (ret != 0) {
    buf = tsk_error_get ();
    reply_with_error ("%s: %s", funcname, buf);
  }
  else
    reply_with_error ("%s: unknown error", funcname);
}

/* Check whether the entry is dot and is not Root.
 * Return 1 if it is dot, 0 otherwise or if it is the Root entry.
 */
static int
entry_is_dot (TSK_FS_FILE *fsfile)
{
  return (TSK_FS_ISDOT (fsfile->name->name) &&
          !(fsfile->fs_info->root_inum == fsfile->name->meta_addr &&  /* Root */
            STREQ (fsfile->name->name, ".")));  /* Avoid 'bin/..' 'etc/..' */
}

int
optgroup_libtsk_available (void)
{
  return 1;
}

#else   /* !HAVE_LIBTSK */

OPTGROUP_LIBTSK_NOT_AVAILABLE

#endif  /* !HAVE_LIBTSK */
