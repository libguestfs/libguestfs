/* libguestfs
 * Copyright (C) 2009-2012 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>

#if HAVE_FUSE
/* See <attr/xattr.h> */
#ifndef ENOATTR
#define ENOATTR ENODATA
#endif

#define FUSE_USE_VERSION 26

#include <fuse.h>
#include <fuse_lowlevel.h>
#endif

#include "cloexec.h"
#include "glthread/lock.h"
#include "hash.h"
#include "hash-pjw.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

#if HAVE_FUSE

/* Functions handling the directory cache. */
static int init_dir_caches (guestfs_h *);
static void free_dir_caches (guestfs_h *);
static void dir_cache_remove_all_expired (guestfs_h *, time_t now);
static void dir_cache_invalidate (guestfs_h *, const char *path);
static int lsc_insert (guestfs_h *, const char *path, const char *name, time_t now, struct stat const *statbuf);
static int xac_insert (guestfs_h *, const char *path, const char *name, time_t now, struct guestfs_xattr_list *xattrs);
static int rlc_insert (guestfs_h *, const char *path, const char *name, time_t now, char *link);
static const struct stat *lsc_lookup (guestfs_h *, const char *pathname);
static const struct guestfs_xattr_list *xac_lookup (guestfs_h *, const char *pathname);
static const char *rlc_lookup (guestfs_h *, const char *pathname);

/* This lock protects access to g->localmountpoint. */
gl_lock_define_initialized (static, mount_local_lock);

#define DECL_G() guestfs_h *g = fuse_get_context()->private_data
#define DEBUG_CALL(fs,...)                                              \
  if (g->ml_debug_calls) {                                              \
    debug (g,                                                           \
           "%s: %s (" fs ")\n",                                         \
           g->localmountpoint, __func__, ## __VA_ARGS__);               \
  }

#define RETURN_ERRNO return -guestfs_last_errno (g)

static struct guestfs_xattr_list *
copy_xattr_list (const struct guestfs_xattr *first, size_t num)
{
  struct guestfs_xattr_list *xattrs;

  xattrs = malloc (sizeof *xattrs);
  if (xattrs == NULL) {
    perror ("malloc");
    return NULL;
  }

  xattrs->len = num;
  xattrs->val = malloc (num * sizeof (struct guestfs_xattr));
  if (xattrs->val == NULL) {
    perror ("malloc");
    free (xattrs);
    return NULL;
  }

  size_t i;
  for (i = 0; i < num; ++i) {
    xattrs->val[i].attrname = strdup (first[i].attrname);
    xattrs->val[i].attrval_len = first[i].attrval_len;
    xattrs->val[i].attrval = malloc (first[i].attrval_len);
    memcpy (xattrs->val[i].attrval, first[i].attrval, first[i].attrval_len);
  }

  return xattrs;
}

static int
mount_local_readdir (const char *path, void *buf, fuse_fill_dir_t filler,
                     off_t offset, struct fuse_file_info *fi)
{
  DECL_G ();
  DEBUG_CALL ("%s, %p, %ld", path, buf, (long) offset);

  time_t now;
  time (&now);

  dir_cache_remove_all_expired (g, now);

  struct guestfs_dirent_list *ents;

  ents = guestfs_readdir (g, path);
  if (ents == NULL)
    RETURN_ERRNO;

  size_t i;
  for (i = 0; i < ents->len; ++i) {
    struct stat stat;
    memset (&stat, 0, sizeof stat);

    stat.st_ino = ents->val[i].ino;
    switch (ents->val[i].ftyp) {
    case 'b': stat.st_mode = S_IFBLK; break;
    case 'c': stat.st_mode = S_IFCHR; break;
    case 'd': stat.st_mode = S_IFDIR; break;
    case 'f': stat.st_mode = S_IFIFO; break;
    case 'l': stat.st_mode = S_IFLNK; break;
    case 'r': stat.st_mode = S_IFREG; break;
    case 's': stat.st_mode = S_IFSOCK; break;
    case 'u':
    case '?':
    default:  stat.st_mode = 0;
    }

    /* Copied from the example, which also ignores 'offset'.  I'm
     * not quite sure how this is ever supposed to work on large
     * directories. XXX
     */
    if (filler (buf, ents->val[i].name, &stat, 0))
      break;
  }

  /* Now prepopulate the directory caches.  This step is just an
   * optimization, don't worry if it fails.
   */
  char **names = malloc ((ents->len + 1) * sizeof (char *));
  if (names) {
    for (i = 0; i < ents->len; ++i)
      names[i] = ents->val[i].name;
    names[i] = NULL;

    struct guestfs_stat_list *ss = guestfs_lstatlist (g, path, names);
    if (ss) {
      for (i = 0; i < ss->len; ++i) {
        if (ss->val[i].ino >= 0) {
          struct stat statbuf;

          statbuf.st_dev = ss->val[i].dev;
          statbuf.st_ino = ss->val[i].ino;
          statbuf.st_mode = ss->val[i].mode;
          statbuf.st_nlink = ss->val[i].nlink;
          statbuf.st_uid = ss->val[i].uid;
          statbuf.st_gid = ss->val[i].gid;
          statbuf.st_rdev = ss->val[i].rdev;
          statbuf.st_size = ss->val[i].size;
          statbuf.st_blksize = ss->val[i].blksize;
          statbuf.st_blocks = ss->val[i].blocks;
          statbuf.st_atime = ss->val[i].atime;
          statbuf.st_mtime = ss->val[i].mtime;
          statbuf.st_ctime = ss->val[i].ctime;

          lsc_insert (g, path, names[i], now, &statbuf);
        }
      }
      guestfs_free_stat_list (ss);
    }

    struct guestfs_xattr_list *xattrs = guestfs_lxattrlist (g, path, names);
    if (xattrs) {
      size_t ni, num;
      struct guestfs_xattr *first;
      struct guestfs_xattr_list *copy;
      for (i = 0, ni = 0; i < xattrs->len; ++i, ++ni) {
        /* assert (strlen (xattrs->val[i].attrname) == 0); */
        if (xattrs->val[i].attrval_len > 0) {
          ++i;
          first = &xattrs->val[i];
          num = 0;
          for (; i < xattrs->len && strlen (xattrs->val[i].attrname) > 0; ++i)
            num++;

          copy = copy_xattr_list (first, num);
          if (copy)
            xac_insert (g, path, names[ni], now, copy);

          i--;
        }
      }
      guestfs_free_xattr_list (xattrs);
    }

    char **links = guestfs_readlinklist (g, path, names);
    if (links) {
      for (i = 0; names[i] != NULL; ++i) {
        if (links[i][0])
          /* Note that rlc_insert owns the string links[i] after this, */
          rlc_insert (g, path, names[i], now, links[i]);
        else
          /* which is why we have to free links[i] here. */
          free (links[i]);
      }
      free (links);             /* free the array, not the strings */
    }

    free (names);
  }

  guestfs_free_dirent_list (ents);

  return 0;
}

static int
mount_local_getattr (const char *path, struct stat *statbuf)
{
  DECL_G ();
  DEBUG_CALL ("%s, %p", path, statbuf);

  const struct stat *buf;

  buf = lsc_lookup (g, path);
  if (buf) {
    memcpy (statbuf, buf, sizeof *statbuf);
    return 0;
  }

  struct guestfs_stat *r;

  r = guestfs_lstat (g, path);
  if (r == NULL)
    RETURN_ERRNO;

  statbuf->st_dev = r->dev;
  statbuf->st_ino = r->ino;
  statbuf->st_mode = r->mode;
  statbuf->st_nlink = r->nlink;
  statbuf->st_uid = r->uid;
  statbuf->st_gid = r->gid;
  statbuf->st_rdev = r->rdev;
  statbuf->st_size = r->size;
  statbuf->st_blksize = r->blksize;
  statbuf->st_blocks = r->blocks;
  statbuf->st_atime = r->atime;
  statbuf->st_mtime = r->mtime;
  statbuf->st_ctime = r->ctime;

  guestfs_free_stat (r);

  return 0;
}

/* Nautilus loves to use access(2) to test everything about a file,
 * such as whether it's executable.  Therefore treat this a lot like
 * mount_local_getattr.
 */
static int
mount_local_access (const char *path, int mask)
{
  DECL_G ();
  DEBUG_CALL ("%s, %d", path, mask);

  struct stat statbuf;
  int r;

  if (g->ml_read_only && (mask & W_OK))
    return -EROFS;

  r = mount_local_getattr (path, &statbuf);
  if (r < 0 || mask == F_OK)
    return r;

  struct fuse_context *fuse = fuse_get_context ();
  int ok = 1;

  if (mask & R_OK)
    ok = ok &&
      (  fuse->uid == statbuf.st_uid ? statbuf.st_mode & S_IRUSR
       : fuse->gid == statbuf.st_gid ? statbuf.st_mode & S_IRGRP
       : statbuf.st_mode & S_IROTH);
  if (mask & W_OK)
    ok = ok &&
      (  fuse->uid == statbuf.st_uid ? statbuf.st_mode & S_IWUSR
       : fuse->gid == statbuf.st_gid ? statbuf.st_mode & S_IWGRP
       : statbuf.st_mode & S_IWOTH);
  if (mask & X_OK)
    ok = ok &&
      (  fuse->uid == statbuf.st_uid ? statbuf.st_mode & S_IXUSR
       : fuse->gid == statbuf.st_gid ? statbuf.st_mode & S_IXGRP
       : statbuf.st_mode & S_IXOTH);

  return ok ? 0 : -EACCES;
}

static int
mount_local_readlink (const char *path, char *buf, size_t size)
{
  DECL_G ();
  DEBUG_CALL ("%s, %p, %zu", path, buf, size);

  const char *r;
  int free_it = 0;

  r = rlc_lookup (g, path);
  if (!r) {
    r = guestfs_readlink (g, path);
    if (r == NULL)
      RETURN_ERRNO;
    free_it = 1;
  }

  /* Note this is different from the real readlink(2) syscall.  FUSE wants
   * the string to be always nul-terminated, even if truncated.
   */
  size_t len = strlen (r);
  if (len > size - 1)
    len = size - 1;

  memcpy (buf, r, len);
  buf[len] = '\0';

  if (free_it) {
    char *tmp = (char *) r;
    free (tmp);
  }

  return 0;
}

static int
mount_local_mknod (const char *path, mode_t mode, dev_t rdev)
{
  DECL_G ();
  DEBUG_CALL ("%s, 0%o, 0x%lx", path, mode, (long) rdev);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, path);

  r = guestfs_mknod (g, mode, major (rdev), minor (rdev), path);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

static int
mount_local_mkdir (const char *path, mode_t mode)
{
  DECL_G ();
  DEBUG_CALL ("%s, 0%o", path, mode);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, path);

  r = guestfs_mkdir_mode (g, path, mode);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

static int
mount_local_unlink (const char *path)
{
  DECL_G ();
  DEBUG_CALL ("%s", path);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, path);

  r = guestfs_rm (g, path);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

static int
mount_local_rmdir (const char *path)
{
  DECL_G ();
  DEBUG_CALL ("%s", path);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, path);

  r = guestfs_rmdir (g, path);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

static int
mount_local_symlink (const char *from, const char *to)
{
  DECL_G ();
  DEBUG_CALL ("%s, %s", from, to);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, to);

  r = guestfs_ln_s (g, from, to);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

static int
mount_local_rename (const char *from, const char *to)
{
  DECL_G ();
  DEBUG_CALL ("%s, %s", from, to);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, from);
  dir_cache_invalidate (g, to);

  /* XXX It's not clear how close the 'mv' command is to the
   * rename syscall.  We might need to add the rename syscall
   * to the guestfs(3) API.
   */
  r = guestfs_mv (g, from, to);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

static int
mount_local_link (const char *from, const char *to)
{
  DECL_G ();
  DEBUG_CALL ("%s, %s", from, to);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, from);
  dir_cache_invalidate (g, to);

  r = guestfs_ln (g, from, to);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

static int
mount_local_chmod (const char *path, mode_t mode)
{
  DECL_G ();
  DEBUG_CALL ("%s, 0%o", path, mode);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, path);

  r = guestfs_chmod (g, mode, path);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

static int
mount_local_chown (const char *path, uid_t uid, gid_t gid)
{
  DECL_G ();
  DEBUG_CALL ("%s, %ld, %ld", path, (long) uid, (long) gid);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, path);

  r = guestfs_lchown (g, uid, gid, path);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

static int
mount_local_truncate (const char *path, off_t size)
{
  DECL_G ();
  DEBUG_CALL ("%s, %ld", path, (long) size);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, path);

  r = guestfs_truncate_size (g, path, size);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

static int
mount_local_utimens (const char *path, const struct timespec ts[2])
{
  DECL_G ();
  DEBUG_CALL ("%s, [{ %ld, %ld }, { %ld, %ld }]",
              path, ts[0].tv_sec, ts[0].tv_nsec, ts[1].tv_sec, ts[1].tv_nsec);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, path);

  time_t atsecs = ts[0].tv_sec;
  long atnsecs = ts[0].tv_nsec;
  time_t mtsecs = ts[1].tv_sec;
  long mtnsecs = ts[1].tv_nsec;

#ifdef UTIME_NOW
  if (atnsecs == UTIME_NOW)
    atnsecs = -1;
#endif
#ifdef UTIME_OMIT
  if (atnsecs == UTIME_OMIT)
    atnsecs = -2;
#endif
#ifdef UTIME_NOW
  if (mtnsecs == UTIME_NOW)
    mtnsecs = -1;
#endif
#ifdef UTIME_OMIT
  if (mtnsecs == UTIME_OMIT)
    mtnsecs = -2;
#endif

  r = guestfs_utimens (g, path, atsecs, atnsecs, mtsecs, mtnsecs);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

/* All this function needs to do is to check that the requested open
 * flags are valid.  See the notes in <fuse/fuse.h>.
 */
static int
mount_local_open (const char *path, struct fuse_file_info *fi)
{
  DECL_G ();
  DEBUG_CALL ("%s, 0%o", path, fi->flags);

  int flags = fi->flags & O_ACCMODE;

  if (g->ml_read_only && flags != O_RDONLY)
    return -EROFS;

  return 0;
}

static int
mount_local_read (const char *path, char *buf, size_t size, off_t offset,
                  struct fuse_file_info *fi)
{
  DECL_G ();
  DEBUG_CALL ("%s, %p, %zu, %ld", path, buf, size, (long) offset);

  char *r;
  size_t rsize;

  /* The guestfs protocol limits size to somewhere over 2MB.  We just
   * reduce the requested size here accordingly and push the problem
   * up to every user.  http://www.jwz.org/doc/worse-is-better.html
   */
  const size_t limit = 2 * 1024 * 1024;
  if (size > limit)
    size = limit;

  r = guestfs_pread (g, path, size, offset, &rsize);
  if (r == NULL)
    RETURN_ERRNO;

  /* This should never happen, but at least it stops us overflowing
   * the output buffer if it does happen.
   */
  if (rsize > size)
    rsize = size;

  memcpy (buf, r, rsize);
  free (r);

  return rsize;
}

static int
mount_local_write (const char *path, const char *buf, size_t size,
                   off_t offset, struct fuse_file_info *fi)
{
  DECL_G ();
  DEBUG_CALL ("%s, %p, %zu, %ld", path, buf, size, (long) offset);

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, path);

  /* See mount_local_read. */
  const size_t limit = 2 * 1024 * 1024;
  if (size > limit)
    size = limit;

  int r;
  r = guestfs_pwrite (g, path, buf, size, offset);
  if (r == -1)
    RETURN_ERRNO;

  return r;
}

static int
mount_local_statfs (const char *path, struct statvfs *stbuf)
{
  DECL_G ();
  DEBUG_CALL ("%s, %p", path, stbuf);

  struct guestfs_statvfs *r;

  r = guestfs_statvfs (g, path);
  if (r == NULL)
    RETURN_ERRNO;

  stbuf->f_bsize = r->bsize;
  stbuf->f_frsize = r->frsize;
  stbuf->f_blocks = r->blocks;
  stbuf->f_bfree = r->bfree;
  stbuf->f_bavail = r->bavail;
  stbuf->f_files = r->files;
  stbuf->f_ffree = r->ffree;
  stbuf->f_favail = r->favail;
  stbuf->f_fsid = r->fsid;
  stbuf->f_flag = r->flag;
  stbuf->f_namemax = r->namemax;

  guestfs_free_statvfs (r);

  return 0;
}

static int
mount_local_release (const char *path, struct fuse_file_info *fi)
{
  DECL_G ();
  DEBUG_CALL ("%s", path);

  /* Just a stub. This method is optional and can safely be left
   * unimplemented.
   */
  return 0;
}

/* Emulate this by calling sync. */
static int
mount_local_fsync (const char *path, int isdatasync,
                   struct fuse_file_info *fi)
{
  DECL_G ();
  DEBUG_CALL ("%s, %d", path, isdatasync);

  int r;

  r = guestfs_sync (g);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

static int
mount_local_setxattr (const char *path, const char *name, const char *value,
             size_t size, int flags)
{
  DECL_G ();
  DEBUG_CALL ("%s, %s, %p, %zu", path, name, value, size);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, path);

  /* XXX Underlying guestfs(3) API doesn't understand the flags. */
  r = guestfs_lsetxattr (g, name, value, size, path);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

/* The guestfs(3) API for getting xattrs is much easier to use
 * than the real syscall.  Unfortunately we now have to emulate
 * the real syscall using that API :-(
 */
static int
mount_local_getxattr (const char *path, const char *name, char *value,
                      size_t size)
{
  DECL_G ();
  DEBUG_CALL ("%s, %s, %p, %zu", path, name, value, size);

  const struct guestfs_xattr_list *xattrs;
  int free_attrs = 0;

  xattrs = xac_lookup (g, path);
  if (xattrs == NULL) {
    xattrs = guestfs_lgetxattrs (g, path);
    if (xattrs == NULL)
      RETURN_ERRNO;
    free_attrs = 1;
  }

  /* Find the matching attribute (index in 'i'). */
  ssize_t r;
  size_t i;
  for (i = 0; i < xattrs->len; ++i) {
    if (STREQ (xattrs->val[i].attrname, name))
      break;
  }

  if (i == xattrs->len) {       /* not found */
    r = -ENOATTR;
    goto out;
  }

  /* The getxattr man page is unclear, but if value == NULL then we
   * return the space required (the caller then makes a second syscall
   * after allocating the required amount of space).  If value != NULL
   * then it's not clear what we should do, but it appears we should
   * copy as much as possible and return -ERANGE if there's not enough
   * space in the buffer.
   */
  size_t sz = xattrs->val[i].attrval_len;
  if (value == NULL) {
    r = sz;
    goto out;
  }

  if (sz <= size)
    r = sz;
  else {
    r = -ERANGE;
    sz = size;
  }
  memcpy (value, xattrs->val[i].attrval, sz);

out:
  if (free_attrs)
    guestfs_free_xattr_list ((struct guestfs_xattr_list *) xattrs);

  return r;
}

/* Ditto as above. */
static int
mount_local_listxattr (const char *path, char *list, size_t size)
{
  DECL_G ();
  DEBUG_CALL ("%s, %p, %zu", path, list, size);

  const struct guestfs_xattr_list *xattrs;
  int free_attrs = 0;

  xattrs = xac_lookup (g, path);
  if (xattrs == NULL) {
    xattrs = guestfs_lgetxattrs (g, path);
    if (xattrs == NULL)
      RETURN_ERRNO;
    free_attrs = 1;
  }

  /* Calculate how much space is required to hold the result. */
  size_t space = 0;
  size_t len;
  size_t i;
  for (i = 0; i < xattrs->len; ++i) {
    len = strlen (xattrs->val[i].attrname) + 1;
    space += len;
  }

  /* The listxattr man page is unclear, but if list == NULL then we
   * return the space required (the caller then makes a second syscall
   * after allocating the required amount of space).  If list != NULL
   * then it's not clear what we should do, but it appears we should
   * copy as much as possible and return -ERANGE if there's not enough
   * space in the buffer.
   */
  ssize_t r;
  if (list == NULL) {
    r = space;
    goto out;
  }

  r = 0;
  for (i = 0; i < xattrs->len; ++i) {
    len = strlen (xattrs->val[i].attrname) + 1;
    if (size >= len) {
      memcpy (list, xattrs->val[i].attrname, len);
      size -= len;
      list += len;
      r += len;
    } else {
      r = -ERANGE;
      break;
    }
  }

 out:
  if (free_attrs)
    guestfs_free_xattr_list ((struct guestfs_xattr_list *) xattrs);

  return r;
}

static int
mount_local_removexattr(const char *path, const char *name)
{
  DECL_G ();
  DEBUG_CALL ("%s, %s", path, name);

  int r;

  if (g->ml_read_only) return -EROFS;

  dir_cache_invalidate (g, path);

  r = guestfs_lremovexattr (g, name, path);
  if (r == -1)
    RETURN_ERRNO;

  return 0;
}

static struct fuse_operations mount_local_operations = {
  .getattr	= mount_local_getattr,
  .access	= mount_local_access,
  .readlink	= mount_local_readlink,
  .readdir	= mount_local_readdir,
  .mknod	= mount_local_mknod,
  .mkdir	= mount_local_mkdir,
  .symlink	= mount_local_symlink,
  .unlink	= mount_local_unlink,
  .rmdir	= mount_local_rmdir,
  .rename	= mount_local_rename,
  .link		= mount_local_link,
  .chmod	= mount_local_chmod,
  .chown	= mount_local_chown,
  .truncate	= mount_local_truncate,
  .utimens	= mount_local_utimens,
  .open		= mount_local_open,
  .read		= mount_local_read,
  .write	= mount_local_write,
  .statfs	= mount_local_statfs,
  .release	= mount_local_release,
  .fsync	= mount_local_fsync,
  .setxattr	= mount_local_setxattr,
  .getxattr	= mount_local_getxattr,
  .listxattr	= mount_local_listxattr,
  .removexattr	= mount_local_removexattr,
};

int
guestfs__mount_local (guestfs_h *g, const char *localmountpoint,
                      const struct guestfs_mount_local_argv *optargs)
{
  const char *t;
  struct fuse_args args = FUSE_ARGS_INIT (0, NULL);
  struct fuse_chan *ch;
  int fd;

  /* You can only mount each handle in one place in one thread. */
  gl_lock_lock (mount_local_lock);
  t = g->localmountpoint;
  gl_lock_unlock (mount_local_lock);
  if (t) {
    error (g, _("filesystem is already mounted in another thread"));
    return -1;
  }

  if (optargs->bitmask & GUESTFS_MOUNT_LOCAL_READONLY_BITMASK)
    g->ml_read_only = optargs->readonly;
  else
    g->ml_read_only = 0;
  if (optargs->bitmask & GUESTFS_MOUNT_LOCAL_CACHETIMEOUT_BITMASK)
    g->ml_dir_cache_timeout = optargs->cachetimeout;
  else
    g->ml_dir_cache_timeout = 60;
  if (optargs->bitmask & GUESTFS_MOUNT_LOCAL_DEBUGCALLS_BITMASK)
    g->ml_debug_calls = optargs->debugcalls;
  else
    g->ml_debug_calls = 0;

  /* Initialize the directory caches in the handle. */
  if (init_dir_caches (g) == -1)
    return -1;

  /* Create the FUSE 'args'. */
  /* XXX we don't have a program name */
  if (fuse_opt_add_arg (&args, "guestfs_mount_local") == -1) {
  arg_error:
    perrorf (g, _("fuse_opt_add_arg: %s"), localmountpoint);
    fuse_opt_free_args (&args);
    guestfs___free_fuse (g);
    return -1;
  }

  if (optargs->bitmask & GUESTFS_MOUNT_LOCAL_OPTIONS_BITMASK) {
    if (fuse_opt_add_arg (&args, "-o") == -1 ||
        fuse_opt_add_arg (&args, optargs->options) == -1)
      goto arg_error;
  }

  debug (g, "%s: fuse_mount %s", __func__, localmountpoint);

  /* Create the FUSE mountpoint. */
  ch = fuse_mount (localmountpoint, &args);
  if (ch == NULL) {
    perrorf (g, _("fuse_mount: %s"), localmountpoint);
    fuse_opt_free_args (&args);
    guestfs___free_fuse (g);
    return -1;
  }

  /* Set F_CLOEXEC on the channel.  XXX libfuse should do this. */
  fd = fuse_chan_fd (ch);
  if (fd >= 0)
    set_cloexec_flag (fd, 1);

  debug (g, "%s: fuse_new", __func__);

  /* Create the FUSE handle. */
  g->fuse = fuse_new (ch, &args,
                      &mount_local_operations, sizeof mount_local_operations,
                      g);
  if (!g->fuse) {
    perrorf (g, _("fuse_new: %s"), localmountpoint);
    fuse_unmount (localmountpoint, ch);
    fuse_opt_free_args (&args);
    guestfs___free_fuse (g);
    return -1;
  }

  fuse_opt_free_args (&args);

  debug (g, "%s: leaving fuse_mount_local", __func__);

  /* Set g->localmountpoint in the handle. */
  gl_lock_lock (mount_local_lock);
  g->localmountpoint = localmountpoint;
  gl_lock_unlock (mount_local_lock);

  return 0;
}

int
guestfs__mount_local_run (guestfs_h *g)
{
  int r, mounted;

  gl_lock_lock (mount_local_lock);
  mounted = g->localmountpoint != NULL;
  gl_lock_unlock (mount_local_lock);

  if (!mounted) {
    error (g, _("you must call guestfs_mount_local first"));
    return -1;
  }

  debug (g, "%s: entering fuse_loop", __func__);

  /* Enter the main loop. */
  r = fuse_loop (g->fuse);
  if (r != 0)
    perrorf (g, _("fuse_loop: %s"), g->localmountpoint);

  debug (g, "%s: leaving fuse_loop", __func__);

  guestfs___free_fuse (g);
  gl_lock_lock (mount_local_lock);
  g->localmountpoint = NULL;
  gl_lock_unlock (mount_local_lock);

  /* By inspection, I found that fuse_loop only returns 0 or -1, but
   * don't rely on this in future.
   */
  return r == 0 ? 0 : -1;
}

void
guestfs___free_fuse (guestfs_h *g)
{
  if (g->fuse)
    fuse_destroy (g->fuse);     /* also closes the channel */
  g->fuse = NULL;
  free_dir_caches (g);
}

static int do_fusermount (guestfs_h *g, const char *localmountpoint, int error_fd);

int
guestfs__umount_local (guestfs_h *g,
                       const struct guestfs_umount_local_argv *optargs)
{
  size_t i, tries;
  char *localmountpoint;
  char *fusermount_log = NULL;
  int error_fd = -1;
  int ret = -1;

  /* How many times should we try the fusermount command? */
  if (optargs->bitmask & GUESTFS_UMOUNT_LOCAL_RETRY_BITMASK)
    tries = optargs->retry ? 5 : 1;
  else
    tries = 1;

  /* Make a local copy of g->localmountpoint.  It could be freed from
   * under us by another thread, except when we are holding the lock.
   */
  gl_lock_lock (mount_local_lock);
  if (g->localmountpoint)
    localmountpoint = safe_strdup (g, g->localmountpoint);
  else
    localmountpoint = NULL;
  gl_lock_unlock (mount_local_lock);

  if (!localmountpoint) {
    error (g, _("no filesystem is mounted"));
    goto out;
  }

  /* Send all errors from fusermount to a temporary file.  Only after
   * all 'tries' have failed do we print the contents of this file.  A
   * temporary failure when retry == true will not cause any error.
   */
  fusermount_log = safe_asprintf (g, "%s/fusermount.log", g->tmpdir);
  error_fd = open (fusermount_log,
                   O_RDWR|O_CREAT|O_TRUNC|O_NOCTTY /* not O_CLOEXEC */,
                   0600);
  if (error_fd == -1) {
    perrorf (g, _("open: %s"), fusermount_log);
    goto out;
  }

  for (i = 0; i < tries; ++i) {
    int r;

    r = do_fusermount (g, localmountpoint, error_fd);
    if (r == -1)
      goto out;
    if (r) {
      /* External fusermount succeeded.  Note that the original thread
       * is responsible for setting g->localmountpoint to NULL.
       */
      ret = 0;
      break;
    }

    sleep (1);
  }

  if (ret == -1) {              /* fusermount failed */
    char error_message[4096];
    ssize_t n;

    /* Get the error message from the log file. */
    if (lseek (error_fd, 0, SEEK_SET) >= 0 &&
        (n = read (error_fd, error_message, sizeof error_message - 1)) > 0) {
      while (n > 0 && error_message[n-1] == '\n')
        n--;
      error_message[n] = '\0';
    } else {
      snprintf (error_message, sizeof error_message,
                "(fusermount error could not be preserved)");
    }

    error (g, _("fusermount failed: %s: %s"), localmountpoint, error_message);
    goto out;
  }

 out:
  if (error_fd >= 0) close (error_fd);
  if (fusermount_log) {
    unlink (fusermount_log);
    free (fusermount_log);
  }
  free (localmountpoint);
  return ret;
}

static int
do_fusermount (guestfs_h *g, const char *localmountpoint, int error_fd)
{
  pid_t pid;
  int status;

  pid = fork ();
  if (pid == -1) {
    perrorf (g, "fork");
    return -1;
  }

  if (pid == 0) {               /* child */
    /* Ensure stdout and stderr point to the error_fd. */
    dup2 (error_fd, STDOUT_FILENO);
    dup2 (error_fd, STDERR_FILENO);
    close (error_fd);
    execlp ("fusermount", "fusermount", "-u", localmountpoint, NULL);
    perror ("exec: fusermount");
    _exit (EXIT_FAILURE);
  }

  /* Parent. */
  if (waitpid (pid, &status, 0) == -1) {
    perrorf (g, "waitpid");
    return -1;
  }

  if (!WIFEXITED (status) || WEXITSTATUS (status) != EXIT_SUCCESS)
    return 0;                   /* it failed to unmount the mountpoint */

  return 1;                     /* unmount was successful */
}

/* Functions handling the directory cache.
 *
 * Note on attribute caching: FUSE can cache filesystem attributes for
 * short periods of time (configurable via -o attr_timeout).  It
 * doesn't cache xattrs, and in any case FUSE caching doesn't solve
 * the problem that we have to make a series of guestfs_lstat and
 * guestfs_lgetxattr calls when we first list a directory (thus, many
 * round trips).
 *
 * For this reason, we also implement a readdir cache here which is
 * invoked when a readdir call is made.  readdir is modified so that
 * as well as reading the directory, it also requests all the stat
 * structures, xattrs and readlinks of all entries in the directory,
 * and these are added to the cache here (for a short, configurable
 * period of time) in anticipation that they will be needed
 * immediately afterwards, which is usually the case when the user is
 * doing an "ls"-like operation.
 *
 * You can still use FUSE attribute caching on top of this mechanism
 * if you like.
 */

struct lsc_entry {              /* lstat cache entry */
  char *pathname;               /* full path to the file */
  time_t timeout;               /* when this entry expires */
  struct stat statbuf;          /* statbuf */
};

struct xac_entry {              /* xattr cache entry */
  /* NB first two fields must be same as lsc_entry */
  char *pathname;               /* full path to the file */
  time_t timeout;               /* when this entry expires */
  struct guestfs_xattr_list *xattrs;
};

struct rlc_entry {              /* readlink cache entry */
  /* NB first two fields must be same as lsc_entry */
  char *pathname;               /* full path to the file */
  time_t timeout;               /* when this entry expires */
  char *link;
};

static size_t
gen_hash (void const *x, size_t table_size)
{
  struct lsc_entry const *p = x;
  return hash_pjw (p->pathname, table_size);
}

static bool
gen_compare (void const *x, void const *y)
{
  struct lsc_entry const *a = x;
  struct lsc_entry const *b = y;
  return STREQ (a->pathname, b->pathname);
}

static void
lsc_free (void *x)
{
  if (x) {
    struct lsc_entry *p = x;

    free (p->pathname);
    free (p);
  }
}

static void
xac_free (void *x)
{
  if (x) {
    struct xac_entry *p = x;

    guestfs_free_xattr_list (p->xattrs);
    lsc_free (x);
  }
}

static void
rlc_free (void *x)
{
  if (x) {
    struct rlc_entry *p = x;

    free (p->link);
    lsc_free (x);
  }
}

static int
init_dir_caches (guestfs_h *g)
{
  g->lsc_ht = hash_initialize (1024, NULL, gen_hash, gen_compare, lsc_free);
  g->xac_ht = hash_initialize (1024, NULL, gen_hash, gen_compare, xac_free);
  g->rlc_ht = hash_initialize (1024, NULL, gen_hash, gen_compare, rlc_free);
  if (!g->lsc_ht || !g->xac_ht || !g->rlc_ht) {
    error (g, _("could not initialize dir cache hashtables"));
    return -1;
  }
  return 0;
}

static void
free_dir_caches (guestfs_h *g)
{
  if (g->lsc_ht)
    hash_free (g->lsc_ht);
  if (g->xac_ht)
    hash_free (g->xac_ht);
  if (g->rlc_ht)
    hash_free (g->rlc_ht);
  g->lsc_ht = NULL;
  g->xac_ht = NULL;
  g->rlc_ht = NULL;
}

struct gen_remove_data {
  time_t now;
  Hash_table *ht;
  Hash_data_freer freer;
};

static bool
gen_remove_if_expired (void *x, void *data)
{
  /* XXX hash_do_for_each was observed calling this function
   * with x == NULL.
   */
  if (x) {
    struct lsc_entry *p = x;
    struct gen_remove_data *d = data;

    if (p->timeout < d->now)
      d->freer (hash_delete (d->ht, x));
  }

  return 1;
}

static void
gen_remove_all_expired (Hash_table *ht, Hash_data_freer freer, time_t now)
{
  struct gen_remove_data data;
  data.now = now;
  data.ht = ht;
  data.freer = freer;

  /* Careful reading of the documentation to hash _seems_ to indicate
   * that this is safe, _provided_ we use the default thresholds (in
   * particular, no shrink threshold).
   */
  hash_do_for_each (ht, gen_remove_if_expired, &data);
}

static void
dir_cache_remove_all_expired (guestfs_h *g, time_t now)
{
  gen_remove_all_expired (g->lsc_ht, lsc_free, now);
  gen_remove_all_expired (g->xac_ht, xac_free, now);
  gen_remove_all_expired (g->rlc_ht, rlc_free, now);
}

static int
gen_replace (Hash_table *ht, struct lsc_entry *new_entry, Hash_data_freer freer)
{
  struct lsc_entry *old_entry;

  old_entry = hash_delete (ht, new_entry);
  freer (old_entry);

  old_entry = hash_insert (ht, new_entry);
  if (old_entry == NULL) {
    perror ("hash_insert");
    freer (new_entry);
    return -1;
  }
  /* assert (old_entry == new_entry); */

  return 0;
}

static int
lsc_insert (guestfs_h *g,
            const char *path, const char *name, time_t now,
            struct stat const *statbuf)
{
  struct lsc_entry *entry;

  entry = malloc (sizeof *entry);
  if (entry == NULL) {
    perror ("malloc");
    return -1;
  }

  size_t len = strlen (path) + strlen (name) + 2;
  entry->pathname = malloc (len);
  if (entry->pathname == NULL) {
    perror ("malloc");
    free (entry);
    return -1;
  }
  if (STREQ (path, "/"))
    snprintf (entry->pathname, len, "/%s", name);
  else
    snprintf (entry->pathname, len, "%s/%s", path, name);

  memcpy (&entry->statbuf, statbuf, sizeof entry->statbuf);

  entry->timeout = now + g->ml_dir_cache_timeout;

  return gen_replace (g->lsc_ht, entry, lsc_free);
}

static int
xac_insert (guestfs_h *g,
            const char *path, const char *name, time_t now,
            struct guestfs_xattr_list *xattrs)
{
  struct xac_entry *entry;

  entry = malloc (sizeof *entry);
  if (entry == NULL) {
    perror ("malloc");
    return -1;
  }

  size_t len = strlen (path) + strlen (name) + 2;
  entry->pathname = malloc (len);
  if (entry->pathname == NULL) {
    perror ("malloc");
    free (entry);
    return -1;
  }
  if (STREQ (path, "/"))
    snprintf (entry->pathname, len, "/%s", name);
  else
    snprintf (entry->pathname, len, "%s/%s", path, name);

  entry->xattrs = xattrs;

  entry->timeout = now + g->ml_dir_cache_timeout;

  return gen_replace (g->xac_ht, (struct lsc_entry *) entry, xac_free);
}

static int
rlc_insert (guestfs_h *g,
            const char *path, const char *name, time_t now,
            char *link)
{
  struct rlc_entry *entry;

  entry = malloc (sizeof *entry);
  if (entry == NULL) {
    perror ("malloc");
    return -1;
  }

  size_t len = strlen (path) + strlen (name) + 2;
  entry->pathname = malloc (len);
  if (entry->pathname == NULL) {
    perror ("malloc");
    free (entry);
    return -1;
  }
  if (STREQ (path, "/"))
    snprintf (entry->pathname, len, "/%s", name);
  else
    snprintf (entry->pathname, len, "%s/%s", path, name);

  entry->link = link;

  entry->timeout = now + g->ml_dir_cache_timeout;

  return gen_replace (g->rlc_ht, (struct lsc_entry *) entry, rlc_free);
}

static const struct stat *
lsc_lookup (guestfs_h *g, const char *pathname)
{
  const struct lsc_entry key = { .pathname = (char *) pathname };
  struct lsc_entry *entry;
  time_t now;

  time (&now);

  entry = hash_lookup (g->lsc_ht, &key);
  if (entry && entry->timeout >= now)
    return &entry->statbuf;
  else
    return NULL;
}

static const struct guestfs_xattr_list *
xac_lookup (guestfs_h *g, const char *pathname)
{
  const struct xac_entry key = { .pathname = (char *) pathname };
  struct xac_entry *entry;
  time_t now;

  time (&now);

  entry = hash_lookup (g->xac_ht, &key);
  if (entry && entry->timeout >= now)
    return entry->xattrs;
  else
    return NULL;
}

static const char *
rlc_lookup (guestfs_h *g, const char *pathname)
{
  const struct rlc_entry key = { .pathname = (char *) pathname };
  struct rlc_entry *entry;
  time_t now;

  time (&now);

  entry = hash_lookup (g->rlc_ht, &key);
  if (entry && entry->timeout >= now)
    return entry->link;
  else
    return NULL;
}

static void
lsc_remove (Hash_table *ht, const char *pathname, Hash_data_freer freer)
{
  const struct lsc_entry key = { .pathname = (char *) pathname };
  struct lsc_entry *entry;

  entry = hash_delete (ht, &key);

  freer (entry);
}

static void
dir_cache_invalidate (guestfs_h *g, const char *path)
{
  lsc_remove (g->lsc_ht, path, lsc_free);
  lsc_remove (g->xac_ht, path, xac_free);
  lsc_remove (g->rlc_ht, path, rlc_free);
}

#else /* !HAVE_FUSE */

int
guestfs__mount_local (guestfs_h *g, const char *localmountpoint,
                      const struct guestfs_mount_local_argv *optargs)
{
  guestfs_error_errno (g, ENOTSUP, _("FUSE not supported"));
  return -1;
}

int
guestfs__mount_local_run (guestfs_h *g)
{
  guestfs_error_errno (g, ENOTSUP, _("FUSE not supported"));
  return -1;
}

int
guestfs__umount_local (guestfs_h *g,
                       const struct guestfs_umount_local_argv *optargs)
{
  guestfs_error_errno (g, ENOTSUP, _("FUSE not supported"));
  return -1;
}

#endif /* !HAVE_FUSE */
