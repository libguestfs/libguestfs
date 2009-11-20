/* guestmount - mount guests using libguestfs and FUSE
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
 *
 * Derived from the example program 'fusexmp.c':
 * Copyright (C) 2001-2007  Miklos Szeredi <miklos@szeredi.hu>
 *
 * This program can be distributed under the terms of the GNU GPL.
 * See the file COPYING.
 */

#define FUSE_USE_VERSION 26

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <fcntl.h>
#include <dirent.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <assert.h>
#include <sys/time.h>
#include <sys/types.h>

#include <fuse.h>
#include <guestfs.h>

#include "progname.h"

#include "guestmount.h"
#include "dircache.h"

/* See <attr/xattr.h> */
#ifndef ENOATTR
#define ENOATTR ENODATA
#endif

static guestfs_h *g = NULL;
static int read_only = 0;
int verbose = 0;
int dir_cache_timeout = 60;

/* This is ugly: guestfs errors are strings, FUSE wants -errno.  We
 * have to do the conversion as best we can.
 */
#define MAX_ERRNO 256

static int
error (void)
{
  int i;
  const char *err = guestfs_last_error (g);

  if (!err)
    return -EINVAL;

  if (verbose)
    fprintf (stderr, "%s\n", err);

  /* Add a few of our own ... */

  /* This indicates guestfsd died.  Translate into a hard EIO error.
   * Arguably we could relaunch the guest if we hit this error.
   */
  if (strstr (err, "call launch before using this function"))
    return -EIO;

  /* See if it matches an errno string in the host. */
  for (i = 0; i < MAX_ERRNO; ++i) {
    const char *e = strerror (i);
    if (e && strstr (err, e) != NULL)
      return -i;
  }

  /* Too bad, return a generic error. */
  return -EINVAL;
}

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
fg_readdir (const char *path, void *buf, fuse_fill_dir_t filler,
            off_t offset, struct fuse_file_info *fi)
{
  time_t now;
  time (&now);

  dir_cache_remove_all_expired (now);

  struct guestfs_dirent_list *ents;

  ents = guestfs_readdir (g, path);
  if (ents == NULL)
    return error ();

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

          lsc_insert (path, names[i], now, &statbuf);
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
        assert (strlen (xattrs->val[i].attrname) == 0);
        if (xattrs->val[i].attrval_len > 0) {
          ++i;
          first = &xattrs->val[i];
          num = 0;
          for (; i < xattrs->len && strlen (xattrs->val[i].attrname) > 0; ++i)
            num++;

          copy = copy_xattr_list (first, num);
          if (copy)
            xac_insert (path, names[ni], now, copy);

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
          rlc_insert (path, names[i], now, links[i]);
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
fg_getattr (const char *path, struct stat *statbuf)
{
  const struct stat *buf;

  buf = lsc_lookup (path);
  if (buf) {
    memcpy (statbuf, buf, sizeof *statbuf);
    return 0;
  }

  struct guestfs_stat *r;

  r = guestfs_lstat (g, path);
  if (r == NULL)
    return error ();

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
 * fg_getattr.
 */
static int
fg_access (const char *path, int mask)
{
  struct stat statbuf;
  int r;

  if (read_only && (mask & W_OK))
    return -EROFS;

  r = fg_getattr (path, &statbuf);
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
fg_readlink (const char *path, char *buf, size_t size)
{
  const char *r;
  int free_it = 0;

  r = rlc_lookup (path);
  if (!r) {
    r = guestfs_readlink (g, path);
    if (r == NULL)
      return error ();
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
fg_mknod (const char *path, mode_t mode, dev_t rdev)
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (path);

  r = guestfs_mknod (g, mode, major (rdev), minor (rdev), path);
  if (r == -1)
    return error ();

  return 0;
}

static int
fg_mkdir (const char *path, mode_t mode)
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (path);

  r = guestfs_mkdir_mode (g, path, mode);
  if (r == -1)
    return error ();

  return 0;
}

static int
fg_unlink (const char *path)
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (path);

  r = guestfs_rm (g, path);
  if (r == -1)
    return error ();

  return 0;
}

static int
fg_rmdir (const char *path)
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (path);

  r = guestfs_rmdir (g, path);
  if (r == -1)
    return error ();

  return 0;
}

static int
fg_symlink (const char *from, const char *to)
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (to);

  r = guestfs_ln_s (g, from, to);
  if (r == -1)
    return error ();

  return 0;
}

static int
fg_rename (const char *from, const char *to)
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (from);
  dir_cache_invalidate (to);

  /* XXX It's not clear how close the 'mv' command is to the
   * rename syscall.  We might need to add the rename syscall
   * to the guestfs(3) API.
   */
  r = guestfs_mv (g, from, to);
  if (r == -1)
    return error ();

  return 0;
}

static int
fg_link (const char *from, const char *to)
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (from);
  dir_cache_invalidate (to);

  r = guestfs_ln (g, from, to);
  if (r == -1)
    return error ();

  return 0;
}

static int
fg_chmod (const char *path, mode_t mode)
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (path);

  r = guestfs_chmod (g, mode, path);
  if (r == -1)
    return error ();

  return 0;
}

static int
fg_chown (const char *path, uid_t uid, gid_t gid)
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (path);

  r = guestfs_lchown (g, uid, gid, path);
  if (r == -1)
    return error ();

  return 0;
}

static int
fg_truncate (const char *path, off_t size)
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (path);

  r = guestfs_truncate_size (g, path, size);
  if (r == -1)
    return error ();

  return 0;
}

static int
fg_utimens (const char *path, const struct timespec ts[2])
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (path);

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
    return error ();

  return 0;
}

/* This call is quite hard to emulate through the guestfs(3) API.  In
 * one sense it's a little like access (see above) because it tests
 * whether opening a file would succeed given the flags.  But it also
 * has side effects such as truncating the file if O_TRUNC is given.
 * Therefore we need to emulate it ... painfully.
 */
static int
fg_open (const char *path, struct fuse_file_info *fi)
{
  int r, exists;

  if (fi->flags & O_WRONLY) {
    if (read_only)
      return -EROFS;
  }

  exists = guestfs_exists (g, path);
  if (exists == -1)
    return error ();

  if (fi->flags & O_CREAT) {
    if (read_only)
      return -EROFS;

    dir_cache_invalidate (path);

    /* Exclusive?  File must not exist already. */
    if (fi->flags & O_EXCL) {
      if (exists)
        return -EEXIST;
    }

    /* Create?  Touch it and optionally truncate it. */
    r = guestfs_touch (g, path);
    if (r == -1)
      return error ();

    if (fi->flags & O_TRUNC) {
      r = guestfs_truncate (g, path);
      if (r == -1)
        return error ();
    }
  } else {
    /* Not create, just check it exists. */
    if (!exists)
      return -ENOENT;
  }

  return 0;
}

static int
fg_read (const char *path, char *buf, size_t size, off_t offset,
         struct fuse_file_info *fi)
{
  char *r;
  size_t rsize;

  if (verbose)
    fprintf (stderr, "fg_read: %s: size %zu offset %ju\n",
             path, size, offset);

  /* The guestfs protocol limits size to somewhere over 2MB.  We just
   * reduce the requested size here accordingly and push the problem
   * up to every user.  http://www.jwz.org/doc/worse-is-better.html
   */
  const size_t limit = 2 * 1024 * 1024;
  if (size > limit)
    size = limit;

  r = guestfs_pread (g, path, size, offset, &rsize);
  if (r == NULL)
    return error ();

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
fg_write (const char *path, const char *buf, size_t size,
          off_t offset, struct fuse_file_info *fi)
{
  if (read_only) return -EROFS;

  dir_cache_invalidate (path);

  return -ENOSYS;               /* XXX */
}

static int
fg_statfs (const char *path, struct statvfs *stbuf)
{
  struct guestfs_statvfs *r;

  r = guestfs_statvfs (g, path);
  if (r == NULL)
    return error ();

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
fg_release (const char *path, struct fuse_file_info *fi)
{
  /* Just a stub. This method is optional and can safely be left
   * unimplemented.
   */
  return 0;
}

/* Emulate this by calling sync. */
static int fg_fsync(const char *path, int isdatasync,
                     struct fuse_file_info *fi)
{
  int r;

  r = guestfs_sync (g);
  if (r == -1)
    return error ();

  return 0;
}

static int
fg_setxattr (const char *path, const char *name, const char *value,
             size_t size, int flags)
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (path);

  /* XXX Underlying guestfs(3) API doesn't understand the flags. */
  r = guestfs_lsetxattr (g, name, value, size, path);
  if (r == -1)
    return error ();

  return 0;
}

/* The guestfs(3) API for getting xattrs is much easier to use
 * than the real syscall.  Unfortunately we now have to emulate
 * the real syscall using that API :-(
 */
static int
fg_getxattr (const char *path, const char *name, char *value,
             size_t size)
{
  const struct guestfs_xattr_list *xattrs;
  int free_attrs = 0;

  xattrs = xac_lookup (path);
  if (xattrs == NULL) {
    xattrs = guestfs_lgetxattrs (g, path);
    if (xattrs == NULL)
      return error ();
    free_attrs = 1;
  }

  size_t i;
  int r = -ENOATTR;
  for (i = 0; i < xattrs->len; ++i) {
    if (STREQ (xattrs->val[i].attrname, name)) {
      size_t sz = xattrs->val[i].attrval_len;
      if (sz > size)
        sz = size;
      memcpy (value, xattrs->val[i].attrval, sz);
      r = 0;
      break;
    }
  }

  if (free_attrs)
    guestfs_free_xattr_list ((struct guestfs_xattr_list *) xattrs);

  return r;
}

/* Ditto as above. */
static int
fg_listxattr (const char *path, char *list, size_t size)
{
  const struct guestfs_xattr_list *xattrs;
  int free_attrs = 0;

  xattrs = xac_lookup (path);
  if (xattrs == NULL) {
    xattrs = guestfs_lgetxattrs (g, path);
    if (xattrs == NULL)
      return error ();
    free_attrs = 1;
  }

  size_t i;
  ssize_t copied = 0;
  for (i = 0; i < xattrs->len; ++i) {
    size_t len = strlen (xattrs->val[i].attrname) + 1;
    if (size >= len) {
      memcpy (list, xattrs->val[i].attrname, len);
      size -= len;
      list += len;
      copied += len;
    } else {
      copied = -ERANGE;
      break;
    }
  }

  if (free_attrs)
    guestfs_free_xattr_list ((struct guestfs_xattr_list *) xattrs);

  return copied;
}

static int
fg_removexattr(const char *path, const char *name)
{
  int r;

  if (read_only) return -EROFS;

  dir_cache_invalidate (path);

  r = guestfs_lremovexattr (g, name, path);
  if (r == -1)
    return error ();

  return 0;
}

static struct fuse_operations fg_operations = {
  .getattr	= fg_getattr,
  .access	= fg_access,
  .readlink	= fg_readlink,
  .readdir	= fg_readdir,
  .mknod	= fg_mknod,
  .mkdir	= fg_mkdir,
  .symlink	= fg_symlink,
  .unlink	= fg_unlink,
  .rmdir	= fg_rmdir,
  .rename	= fg_rename,
  .link		= fg_link,
  .chmod	= fg_chmod,
  .chown	= fg_chown,
  .truncate	= fg_truncate,
  .utimens	= fg_utimens,
  .open		= fg_open,
  .read		= fg_read,
  .write	= fg_write,
  .statfs	= fg_statfs,
  .release	= fg_release,
  .fsync	= fg_fsync,
  .setxattr	= fg_setxattr,
  .getxattr	= fg_getxattr,
  .listxattr	= fg_listxattr,
  .removexattr	= fg_removexattr,
};

struct drv {
  struct drv *next;
  char *filename;
};

struct mp {
  struct mp *next;
  char *device;
  char *mountpoint;
};

static void add_drives (struct drv *);
static void mount_mps (struct mp *);

static void __attribute__((noreturn))
fuse_help (void)
{
  const char *tmp_argv[] = { program_name, "--help", NULL };
  fuse_main (2, (char **) tmp_argv, &fg_operations, NULL);
  exit (EXIT_SUCCESS);
}

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n"),
             program_name);
  else {
    fprintf (stdout,
           _("%s: FUSE module for libguestfs\n"
             "%s lets you mount a virtual machine filesystem\n"
             "Copyright (C) 2009 Red Hat Inc.\n"
             "Usage:\n"
             "  %s [--options] [-- [--FUSE-options]] mountpoint\n"
             "Options:\n"
             "  -a|--add image       Add image\n"
             "  --dir-cache-timeout  Set readdir cache timeout (default 5 sec)\n"
             "  --fuse-help          Display extra FUSE options\n"
             "  --help               Display help message and exit\n"
             "  -m|--mount dev[:mnt] Mount dev on mnt (if omitted, /)\n"
             "  -n|--no-sync         Don't autosync\n"
             "  -o|--option opt      Pass extra option to FUSE\n"
             "  -r|--ro              Mount read-only\n"
             "  --selinux            Enable SELinux support\n"
             "  --trace              Trace guestfs API calls (to stderr)\n"
             "  -v|--verbose         Verbose messages\n"
             "  -V|--version         Display version and exit\n"
             ),
             program_name, program_name, program_name);
  }
  exit (status);
}

int
main (int argc, char *argv[])
{
  enum { HELP_OPTION = CHAR_MAX + 1 };

  /* The command line arguments are broadly compatible with (a subset
   * of) guestfish.  Thus we have to deal mainly with -a, -m and --ro.
   */
  static const char *options = "a:m:no:rv?V";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "dir-cache-timeout", 1, 0, 0 },
    { "fuse-help", 0, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "mount", 1, 0, 'm' },
    { "no-sync", 0, 0, 'n' },
    { "option", 1, 0, 'o' },
    { "ro", 0, 0, 'r' },
    { "selinux", 0, 0, 0 },
    { "trace", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };

  struct drv *drvs = NULL;
  struct drv *drv;
  struct mp *mps = NULL;
  struct mp *mp;
  char *p;
  int c, i, r;
  int option_index;
  struct sigaction sa;

  int fuse_argc = 0;
  const char **fuse_argv = NULL;

#define ADD_FUSE_ARG(str)                                               \
  do {                                                                  \
    fuse_argc ++;                                                       \
    fuse_argv = realloc (fuse_argv, (1+fuse_argc) * sizeof (char *));   \
    if (!fuse_argv) {                                                   \
      perror ("realloc");                                               \
      exit (EXIT_FAILURE);                                                         \
    }                                                                   \
    fuse_argv[fuse_argc-1] = (str);                                     \
    fuse_argv[fuse_argc] = NULL;                                        \
  } while (0)

  /* LC_ALL=C is required so we can parse error messages. */
  setenv ("LC_ALL", "C", 1);

  /* Set global program name that is not polluted with libtool artifacts.  */
  set_program_name (argv[0]);

  memset (&sa, 0, sizeof sa);
  sa.sa_handler = SIG_IGN;
  sa.sa_flags = SA_RESTART;
  sigaction (SIGPIPE, &sa, NULL);

  /* Various initialization. */
  init_dir_caches ();

  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, _("guestfs_create: failed to create handle\n"));
    exit (EXIT_FAILURE);
  }

  guestfs_set_autosync (g, 1);
  guestfs_set_recovery_proc (g, 0);

  ADD_FUSE_ARG (program_name);
  /* MUST be single-threaded.  You cannot have two threads accessing the
   * same libguestfs handle, and opening more than one handle is likely
   * to be very expensive.
   */
  ADD_FUSE_ARG ("-s");

  /* If developing, add ./appliance to the path.  Note that libtools
   * interferes with this because uninstalled guestfish is a shell
   * script that runs the real program with an absolute path.  Detect
   * that too.
   *
   * BUT if LIBGUESTFS_PATH environment variable is already set by
   * the user, then don't override it.
   */
  if (getenv ("LIBGUESTFS_PATH") == NULL &&
      argv[0] &&
      (argv[0][0] != '/' || strstr (argv[0], "/.libs/lt-") != NULL))
    guestfs_set_path (g, "appliance:" GUESTFS_DEFAULT_PATH);

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "dir-cache-timeout"))
        dir_cache_timeout = atoi (optarg);
      else if (STREQ (long_options[option_index].name, "fuse-help"))
        fuse_help ();
      else if (STREQ (long_options[option_index].name, "selinux"))
        guestfs_set_selinux (g, 1);
      else if (STREQ (long_options[option_index].name, "trace")) {
        ADD_FUSE_ARG ("-f");
        guestfs_set_trace (g, 1);
        guestfs_set_recovery_proc (g, 1);
      }
      else {
        fprintf (stderr, _("%s: unknown long option: %s (%d)\n"),
                 program_name, long_options[option_index].name, option_index);
        exit (EXIT_FAILURE);
      }
      break;

    case 'a':
      if (access (optarg, R_OK) != 0) {
        perror (optarg);
        exit (EXIT_FAILURE);
      }
      drv = malloc (sizeof (struct drv));
      if (!drv) {
        perror ("malloc");
        exit (EXIT_FAILURE);
      }
      drv->filename = optarg;
      drv->next = drvs;
      drvs = drv;
      break;

    case 'm':
      mp = malloc (sizeof (struct mp));
      if (!mp) {
        perror ("malloc");
        exit (EXIT_FAILURE);
      }
      p = strchr (optarg, ':');
      if (p) {
        *p = '\0';
        mp->mountpoint = p+1;
      } else
        mp->mountpoint = bad_cast ("/");
      mp->device = optarg;
      mp->next = mps;
      mps = mp;
      break;

    case 'n':
      guestfs_set_autosync (g, 0);
      break;

    case 'o':
      ADD_FUSE_ARG ("-o");
      ADD_FUSE_ARG (optarg);
      break;

    case 'r':
      read_only = 1;
      break;

    case 'v':
      verbose++;
      guestfs_set_verbose (g, verbose);
      break;

    case 'V':
      printf ("%s %s\n", program_name, PACKAGE_VERSION);
      exit (EXIT_SUCCESS);

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  /* We must have at least one -a and at least one -m. */
  if (!drvs || !mps) {
    fprintf (stderr,
             _("%s: must have at least one -a and at least one -m option\n"),
             program_name);
    exit (EXIT_FAILURE);
  }

  /* We'd better have a mountpoint. */
  if (optind+1 != argc) {
    fprintf (stderr,
             _("%s: you must specify a mountpoint in the host filesystem\n"),
             program_name);
    exit (EXIT_FAILURE);
  }

  /* Do the guest drives and mountpoints. */
  add_drives (drvs);
  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);
  mount_mps (mps);

  /* FUSE example does this, not clear if it's necessary, but ... */
  if (guestfs_umask (g, 0) == -1)
    exit (EXIT_FAILURE);

  /* At the last minute, remove the libguestfs error handler.  In code
   * above this point, the default error handler has been used which
   * sends all errors to stderr.  Now before entering FUSE itself we
   * want to silence errors so we can convert them (see error()
   * function above).
   */
  guestfs_set_error_handler (g, NULL, NULL);

  /* Finish off FUSE args. */
  ADD_FUSE_ARG (argv[optind]);

  /*
    It says about the line containing the for-statement:
    error: assuming signed overflow does not occur when simplifying conditional to constant [-Wstrict-overflow]

  if (verbose) {
    fprintf (stderr, "guestmount: invoking FUSE with args [");
    for (i = 0; i < fuse_argc; ++i) {
      if (i > 0) fprintf (stderr, ", ");
      fprintf (stderr, "%s", fuse_argv[i]);
    }
    fprintf (stderr, "]\n");
  }
  */

  r = fuse_main (fuse_argc, (char **) fuse_argv, &fg_operations, NULL);

  /* Cleanup. */
  guestfs_close (g);
  free_dir_caches ();

  exit (r == -1 ? 1 : 0);
}

/* List is built in reverse order, so add them in reverse order. */
static void
add_drives (struct drv *drv)
{
  int r;

  if (drv) {
    add_drives (drv->next);
    if (!read_only)
      r = guestfs_add_drive (g, drv->filename);
    else
      r = guestfs_add_drive_ro (g, drv->filename);
    if (r == -1)
      exit (EXIT_FAILURE);
  }
}

/* List is built in reverse order, so mount them in reverse order. */
static void
mount_mps (struct mp *mp)
{
  int r;

  if (mp) {
    mount_mps (mp->next);
    if (!read_only)
      r = guestfs_mount (g, mp->device, mp->mountpoint);
    else
      r = guestfs_mount_ro (g, mp->device, mp->mountpoint);
    if (r == -1)
      exit (EXIT_FAILURE);
  }
}
