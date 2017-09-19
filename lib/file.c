/* libguestfs
 * Copyright (C) 2012 Red Hat Inc.
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
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <string.h>

#include "full-read.h"
#include "full-write.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "structs-cleanups.h"

static int
compare (const void *vp1, const void *vp2)
{
  char * const *p1 = (char * const *) vp1;
  char * const *p2 = (char * const *) vp2;
  return strcmp (*p1, *p2);
}

static void
sort_strings (char **argv, size_t len)
{
  qsort (argv, len, sizeof (char *), compare);
}

/* Take the first 'n' names, returning a newly allocated list.  The
 * strings themselves are not duplicated.  If 'lastp' is not NULL,
 * then it is updated with the pointer to the list of remaining names.
 */
static char **
take_strings (guestfs_h *g, char *const *names, size_t n, char *const **lastp)
{
  size_t i;

  char **ret = safe_malloc (g, (n+1) * sizeof (char *));

  for (i = 0; names[i] != NULL && i < n; ++i)
    ret[i] = names[i];

  ret[i] = NULL;

  if (lastp)
    *lastp = &names[i];

  return ret;
}

char *
guestfs_impl_cat (guestfs_h *g, const char *path)
{
  size_t size;

  return guestfs_read_file (g, path, &size);
}

char *
guestfs_impl_read_file (guestfs_h *g, const char *path, size_t *size_r)
{
  int fd = -1;
  size_t size;
  CLEANUP_UNLINK_FREE char *tmpfile = NULL;
  char *ret = NULL;
  struct stat statbuf;

  tmpfile = guestfs_int_make_temp_path (g, "cat", NULL);
  if (tmpfile == NULL)
    goto err;

  if (guestfs_download (g, path, tmpfile) == -1)
    goto err;

  fd = open (tmpfile, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    perrorf (g, "open: %s", tmpfile);
    goto err;
  }

  /* Read the whole file into memory. */
  if (fstat (fd, &statbuf) == -1) {
    perrorf (g, "stat: %s", tmpfile);
    goto err;
  }

  /* Don't use safe_malloc, because we want to return an errno to the caller. */
  size = statbuf.st_size;
  ret = malloc (size + 1);
  if (!ret) {
    perrorf (g, "malloc: %zu bytes", size + 1);
    goto err;
  }

  if (full_read (fd, ret, size) != size) {
    perrorf (g, "full-read: %s: %zu bytes", tmpfile, size + 1);
    goto err;
  }

  ret[size] = '\0';

  if (close (fd) == -1) {
    perrorf (g, "close: %s", tmpfile);
    goto err;
  }

  /* Mustn't touch *size_r until we are sure that we won't return any
   * error (RHBZ#589039).
   */
  *size_r = size;
  return ret;

 err:
  free (ret);
  if (fd >= 0)
    close (fd);
  return NULL;
}

char **
guestfs_impl_read_lines (guestfs_h *g, const char *file)
{
  size_t i, count, size, len;
  CLEANUP_FREE char *buf = NULL;
  char **ret = NULL;

  /* Read the whole file into memory. */
  buf = guestfs_read_file (g, file, &size);
  if (buf == NULL)
    return NULL;

  /* 'buf' contains the list of strings, separated by LF or CRLF
   * characters.  Convert this to a list of lines.  Note we have to
   * handle the cases where the buffer is zero length and where the
   * final string is not terminated.
   */
  count = 0;
  for (i = 0; i < size; ++i)
    if (buf[i] == '\n')
      count++;
  if (size > 0 && buf[size-1] != '\n')
    count++;

  ret = malloc ((count + 1) * sizeof (char *));
  if (!ret) {
    perrorf (g, "malloc");
    goto err;
  }

  count = 0;
  if (size > 0) {
    ret[count++] = buf;
    for (i = 0; i < size; ++i) {
      if (buf[i] == '\n') {
        buf[i] = '\0';
        if (i+1 < size)
          ret[count++] = &buf[i+1];
      }
    }
  }
  ret[count] = NULL;

  /* Duplicate the strings, and remove the trailing \r characters if any. */
  for (i = 0; ret[i] != NULL; ++i) {
    ret[i] = strdup (ret[i]);
    if (ret[i] == NULL) {
      perrorf (g, "strdup");
      while (i > 0)
        free (ret[--i]);
      goto err;
    }
    len = strlen (ret[i]);
    if (len > 0 && ret[i][len-1] == '\r')
      ret[i][len-1] = '\0';
  }

  return ret;

 err:
  free (ret);
  return NULL;
}

char **
guestfs_impl_find (guestfs_h *g, const char *directory)
{
  int fd = -1;
  struct stat statbuf;
  CLEANUP_UNLINK_FREE char *tmpfile = NULL;
  CLEANUP_FREE char *buf = NULL;
  char **ret = NULL;
  size_t i, count, size;

  tmpfile = guestfs_int_make_temp_path (g, "find", "txt");
  if (tmpfile == NULL)
    goto err;

  if (guestfs_find0 (g, directory, tmpfile) == -1)
    goto err;

  fd = open (tmpfile, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    perrorf (g, "open: %s", tmpfile);
    goto err;
  }

  /* Read the whole file into memory. */
  if (fstat (fd, &statbuf) == -1) {
    perrorf (g, "stat: %s", tmpfile);
    goto err;
  }

  /* Don't use safe_malloc, because we want to return an errno to the caller. */
  size = statbuf.st_size;
  buf = malloc (size);
  if (!buf) {
    perrorf (g, "malloc: %zu bytes", size);
    goto err;
  }

  if (full_read (fd, buf, size) != size) {
    perrorf (g, "full-read: %s: %zu bytes", tmpfile, size);
    goto err;
  }

  if (close (fd) == -1) {
    perrorf (g, "close: %s", tmpfile);
    goto err;
  }
  fd = -1;

  /* 'buf' contains the list of strings, separated (and terminated) by
   * '\0' characters.  Convert this to a list of lines.  Note we
   * handle the case where buf is completely empty (size == 0), even
   * though it is probably impossible.
   */
  count = 0;
  for (i = 0; i < size; ++i)
    if (buf[i] == '\0')
      count++;

  ret = malloc ((count + 1) * sizeof (char *));
  if (!ret) {
    perrorf (g, "malloc");
    goto err;
  }

  count = 0;
  ret[count++] = buf;
  for (i = 0; i < size; ++i) {
    if (buf[i] == '\0')
      ret[count++] = &buf[i+1];
  }
  ret[--count] = NULL;

  /* Finally we have to duplicate and sort the strings, since that's
   * what the caller is expecting.
   */
  for (i = 0; ret[i] != NULL; ++i) {
    ret[i] = strdup (ret[i]);
    if (ret[i] == NULL) {
      perrorf (g, "strdup");
      while (i > 0)
        free (ret[--i]);
      goto err;
    }
  }

  sort_strings (ret, count);

  return ret;                   /* caller frees */

 err:
  free (ret);
  if (fd >= 0)
    close (fd);
  return NULL;
}

static int
write_or_append (guestfs_h *g, const char *path,
                 const char *content, size_t size,
                 int append)
{
  CLEANUP_UNLINK_FREE char *tmpfile = NULL;
  int fd = -1;
  int64_t filesize;

  /* If the content is small enough, use guestfs_internal_write{,_append}
   * since that call is more efficient.
   */
  if (size <= 2*1024*1024)
    return
      (!append ? guestfs_internal_write : guestfs_internal_write_append)
      (g, path, content, size);

  /* Write the content out to a temporary file. */
  tmpfile = guestfs_int_make_temp_path (g, "write", NULL);
  if (tmpfile == NULL)
    goto err;

  fd = open (tmpfile, O_WRONLY|O_CREAT|O_NOCTTY|O_CLOEXEC, 0600);
  if (fd == -1) {
    perrorf (g, "open: %s", tmpfile);
    goto err;
  }

  if (full_write (fd, content, size) != size) {
    perrorf (g, "write: %s", tmpfile);
    goto err;
  }

  if (close (fd) == -1) {
    perrorf (g, "close: %s", tmpfile);
    goto err;
  }
  fd = -1;

  if (!append) {
    if (guestfs_upload (g, tmpfile, path) == -1)
      goto err;
  }
  else {
    /* XXX Should have an 'upload-append' call to make this atomic. */
    filesize = guestfs_filesize (g, path);
    if (filesize == -1)
      goto err;
    if (guestfs_upload_offset (g, tmpfile, path, filesize) == -1)
      goto err;
  }

  return 0;

 err:
  if (fd >= 0)
    close (fd);
  return -1;
}

int
guestfs_impl_write (guestfs_h *g, const char *path,
		    const char *content, size_t size)
{
  return write_or_append (g, path, content, size, 0);
}

int
guestfs_impl_write_append (guestfs_h *g, const char *path,
			   const char *content, size_t size)
{
  return write_or_append (g, path, content, size, 1);
}

#define LSTATNSLIST_MAX 1000

struct guestfs_statns_list *
guestfs_impl_lstatnslist (guestfs_h *g, const char *dir, char * const*names)
{
  size_t len = guestfs_int_count_strings (names);
  size_t old_len;
  struct guestfs_statns_list *ret;

  ret = safe_malloc (g, sizeof *ret);
  ret->len = 0;
  ret->val = NULL;

  while (len > 0) {
    CLEANUP_FREE_STATNS_LIST struct guestfs_statns_list *stats = NULL;

    /* Note we don't need to free up the strings because take_strings
     * does not do a deep copy.
     */
    CLEANUP_FREE char **first = take_strings (g, names, LSTATNSLIST_MAX, &names);

    len = len <= LSTATNSLIST_MAX ? 0 : len - LSTATNSLIST_MAX;

    stats = guestfs_internal_lstatnslist (g, dir, first);

    if (stats == NULL) {
      guestfs_free_statns_list (ret);
      return NULL;
    }

    /* Append stats to ret. */
    old_len = ret->len;
    ret->len += stats->len;
    ret->val = safe_realloc (g, ret->val,
                             ret->len * sizeof (struct guestfs_statns));
    memcpy (&ret->val[old_len], stats->val,
            stats->len * sizeof (struct guestfs_statns));
  }

  return ret;
}

#define LXATTRLIST_MAX 1000

struct guestfs_xattr_list *
guestfs_impl_lxattrlist (guestfs_h *g, const char *dir, char *const *names)
{
  size_t len = guestfs_int_count_strings (names);
  size_t i, old_len;
  struct guestfs_xattr_list *ret;

  ret = safe_malloc (g, sizeof *ret);
  ret->len = 0;
  ret->val = NULL;

  while (len > 0) {
    CLEANUP_FREE_XATTR_LIST struct guestfs_xattr_list *xattrs = NULL;

    /* Note we don't need to free up the strings because take_strings
     * does not do a deep copy.
     */
    CLEANUP_FREE char **first = take_strings (g, names, LXATTRLIST_MAX, &names);
    len = len <= LXATTRLIST_MAX ? 0 : len - LXATTRLIST_MAX;

    xattrs = guestfs_internal_lxattrlist (g, dir, first);

    if (xattrs == NULL) {
      guestfs_free_xattr_list (ret);
      return NULL;
    }

    /* Append xattrs to ret. */
    old_len = ret->len;
    ret->len += xattrs->len;
    ret->val = safe_realloc (g, ret->val,
                             ret->len * sizeof (struct guestfs_xattr));
    for (i = 0; i < xattrs->len; ++i, ++old_len) {
      /* We have to make a deep copy of the attribute name and value.
       */
      ret->val[old_len].attrname = safe_strdup (g, xattrs->val[i].attrname);
      ret->val[old_len].attrval = safe_malloc (g, xattrs->val[i].attrval_len);
      ret->val[old_len].attrval_len = xattrs->val[i].attrval_len;
      memcpy (ret->val[old_len].attrval, xattrs->val[i].attrval,
              xattrs->val[i].attrval_len);
    }
  }

  return ret;
}

#define READLINK_MAX 1000

char **
guestfs_impl_readlinklist (guestfs_h *g, const char *dir, char *const *names)
{
  size_t len = guestfs_int_count_strings (names);
  size_t old_len, ret_len = 0;
  char **ret = NULL;

  while (len > 0) {
    /* Note we don't need to free up the strings because the 'links'
     * strings are copied to ret, and 'take_strings' does not do a
     * deep copy.
     */
    CLEANUP_FREE char **links = NULL;
    CLEANUP_FREE char **first = take_strings (g, names, READLINK_MAX, &names);
    len = len <= READLINK_MAX ? 0 : len - READLINK_MAX;

    links = guestfs_internal_readlinklist (g, dir, first);

    if (links == NULL) {
      if (ret)
        guestfs_int_free_string_list (ret);
      return NULL;
    }

    /* Append links to ret. */
    old_len = ret_len;
    ret_len += guestfs_int_count_strings (links);
    ret = safe_realloc (g, ret, ret_len * sizeof (char *));
    memcpy (&ret[old_len], links, (ret_len-old_len) * sizeof (char *));
  }

  /* NULL-terminate the list. */
  ret = safe_realloc (g, ret, (ret_len+1) * sizeof (char *));
  ret[ret_len] = NULL;

  return ret;
}

char **
guestfs_impl_ls (guestfs_h *g, const char *directory)
{
  int fd = -1;
  struct stat statbuf;
  CLEANUP_UNLINK_FREE char *tmpfile = NULL;
  CLEANUP_FREE char *buf = NULL;
  char **ret = NULL;
  size_t i, count, size;

  tmpfile = guestfs_int_make_temp_path (g, "ls", "txt");
  if (tmpfile == NULL)
    goto err;

  if (guestfs_ls0 (g, directory, tmpfile) == -1)
    goto err;

  fd = open (tmpfile, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    perrorf (g, "open: %s", tmpfile);
    goto err;
  }

  /* Read the whole file into memory. */
  if (fstat (fd, &statbuf) == -1) {
    perrorf (g, "stat: %s", tmpfile);
    goto err;
  }

  /* Don't use safe_malloc, because we want to return an errno to the caller. */
  size = statbuf.st_size;
  buf = malloc (size);
  if (!buf) {
    perrorf (g, "malloc: %zu bytes", size);
    goto err;
  }

  if (full_read (fd, buf, size) != size) {
    perrorf (g, "full-read: %s: %zu bytes", tmpfile, size);
    goto err;
  }

  if (close (fd) == -1) {
    perrorf (g, "close: %s", tmpfile);
    goto err;
  }
  fd = -1;

  /* 'buf' contains the list of strings, separated (and terminated) by
   * '\0' characters.  Convert this to a list of lines.  Note we
   * handle the case where buf is completely empty (size == 0).
   */
  count = 0;
  for (i = 0; i < size; ++i)
    if (buf[i] == '\0')
      count++;

  ret = malloc ((count + 1) * sizeof (char *));
  if (!ret) {
    perrorf (g, "malloc");
    goto err;
  }

  count = 0;
  ret[count++] = buf;
  for (i = 0; i < size; ++i) {
    if (buf[i] == '\0')
      ret[count++] = &buf[i+1];
  }
  ret[--count] = NULL;

  /* Finally we have to duplicate and sort the strings, since that's
   * what the caller is expecting.
   */
  for (i = 0; ret[i] != NULL; ++i) {
    ret[i] = strdup (ret[i]);
    if (ret[i] == NULL) {
      perrorf (g, "strdup");
      while (i > 0)
        free (ret[--i]);
      goto err;
    }
  }

  sort_strings (ret, count);

  return ret;                   /* caller frees */

 err:
  free (ret);
  if (fd >= 0)
    close (fd);
  return NULL;
}

static void
statns_to_old_stat (struct guestfs_statns *a, struct guestfs_stat *r)
{
  r->dev = a->st_dev;
  r->ino = a->st_ino;
  r->mode = a->st_mode;
  r->nlink = a->st_nlink;
  r->uid = a->st_uid;
  r->gid = a->st_gid;
  r->rdev = a->st_rdev;
  r->size = a->st_size;
  r->blksize = a->st_blksize;
  r->blocks = a->st_blocks;
  r->atime = a->st_atime_sec;
  r->mtime = a->st_mtime_sec;
  r->ctime = a->st_ctime_sec;
}

struct guestfs_stat *
guestfs_impl_stat (guestfs_h *g, const char *path)
{
  CLEANUP_FREE_STATNS struct guestfs_statns *r;
  struct guestfs_stat *ret;

  r = guestfs_statns (g, path);
  if (r == NULL)
    return NULL;

  ret = safe_malloc (g, sizeof *ret);
  statns_to_old_stat (r, ret);
  return ret;                   /* caller frees */
}

struct guestfs_stat *
guestfs_impl_lstat (guestfs_h *g, const char *path)
{
  CLEANUP_FREE_STATNS struct guestfs_statns *r;
  struct guestfs_stat *ret;

  r = guestfs_lstatns (g, path);
  if (r == NULL)
    return NULL;

  ret = safe_malloc (g, sizeof *ret);
  statns_to_old_stat (r, ret);
  return ret;                   /* caller frees */
}

struct guestfs_stat_list *
guestfs_impl_lstatlist (guestfs_h *g, const char *dir, char * const*names)
{
  CLEANUP_FREE_STATNS_LIST struct guestfs_statns_list *r;
  struct guestfs_stat_list *ret;
  size_t i;

  r = guestfs_lstatnslist (g, dir, names);
  if (r == NULL)
    return NULL;

  ret = safe_malloc (g, sizeof *ret);
  ret->len = r->len;
  ret->val = safe_calloc (g, r->len, sizeof (struct guestfs_stat));

  for (i = 0; i < r->len; ++i)
    statns_to_old_stat (&r->val[i], &ret->val[i]);

  return ret;
}
