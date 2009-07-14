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
#include <unistd.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

#if defined(HAVE_ATTR_XATTR_H) || defined(HAVE_SYS_XATTR_H)

#ifdef HAVE_ATTR_XATTR_H
#include <attr/xattr.h>
#else
#ifdef HAVE_SYS_XATTR_H
#include <sys/xattr.h>
#endif
#endif

static guestfs_int_xattr_list *getxattrs (char *path, ssize_t (*listxattr) (const char *path, char *list, size_t size), ssize_t (*getxattr) (const char *path, const char *name, void *value, size_t size));
static int _setxattr (char *xattr, char *val, int vallen, char *path, int (*setxattr) (const char *path, const char *name, const void *value, size_t size, int flags));
static int _removexattr (char *xattr, char *path, int (*removexattr) (const char *path, const char *name));

guestfs_int_xattr_list *
do_getxattrs (char *path)
{
#if defined(HAVE_LISTXATTR) && defined(HAVE_GETXATTR)
  return getxattrs (path, listxattr, getxattr);
#else
  reply_with_error ("getxattrs: no support for listxattr and getxattr");
  return NULL;
#endif
}

guestfs_int_xattr_list *
do_lgetxattrs (char *path)
{
#if defined(HAVE_LLISTXATTR) && defined(HAVE_LGETXATTR)
  return getxattrs (path, llistxattr, lgetxattr);
#else
  reply_with_error ("lgetxattrs: no support for llistxattr and lgetxattr");
  return NULL;
#endif
}

int
do_setxattr (char *xattr, char *val, int vallen, char *path)
{
#if defined(HAVE_SETXATTR)
  return _setxattr (xattr, val, vallen, path, setxattr);
#else
  reply_with_error ("setxattr: no support for setxattr");
  return -1;
#endif
}

int
do_lsetxattr (char *xattr, char *val, int vallen, char *path)
{
#if defined(HAVE_LSETXATTR)
  return _setxattr (xattr, val, vallen, path, lsetxattr);
#else
  reply_with_error ("lsetxattr: no support for lsetxattr");
  return -1;
#endif
}

int
do_removexattr (char *xattr, char *path)
{
#if defined(HAVE_REMOVEXATTR)
  return _removexattr (xattr, path, removexattr);
#else
  reply_with_error ("removexattr: no support for removexattr");
  return -1;
#endif
}

int
do_lremovexattr (char *xattr, char *path)
{
#if defined(HAVE_LREMOVEXATTR)
  return _removexattr (xattr, path, lremovexattr);
#else
  reply_with_error ("lremovexattr: no support for lremovexattr");
  return -1;
#endif
}

static guestfs_int_xattr_list *
getxattrs (char *path,
	   ssize_t (*listxattr) (const char *path, char *list, size_t size),
	   ssize_t (*getxattr) (const char *path, const char *name,
				void *value, size_t size))
{
  ssize_t len, vlen;
  char *buf = NULL;
  int i, j;
  guestfs_int_xattr_list *r = NULL;

  NEED_ROOT (NULL);
  ABS_PATH (path, NULL);

  CHROOT_IN;
  len = listxattr (path, NULL, 0);
  CHROOT_OUT;
  if (len == -1) {
    reply_with_perror ("listxattr");
    goto error;
  }

  buf = malloc (len);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    goto error;
  }

  CHROOT_IN;
  len = listxattr (path, buf, len);
  CHROOT_OUT;
  if (len == -1) {
    reply_with_perror ("listxattr");
    goto error;
  }

  r = calloc (1, sizeof (*r));
  if (r == NULL) {
    reply_with_perror ("malloc");
    goto error;
  }

  /* What we get from the kernel is a string "foo\0bar\0baz" of length
   * len.  First count the strings.
   */
  r->guestfs_int_xattr_list_len = 0;
  for (i = 0; i < len; i += strlen (&buf[i]) + 1)
    r->guestfs_int_xattr_list_len++;

  r->guestfs_int_xattr_list_val =
    calloc (r->guestfs_int_xattr_list_len, sizeof (guestfs_int_xattr));
  if (r->guestfs_int_xattr_list_val == NULL) {
    reply_with_perror ("calloc");
    goto error;
  }

  for (i = 0, j = 0; i < len; i += strlen (&buf[i]) + 1, ++j) {
    CHROOT_IN;
    vlen = getxattr (path, &buf[i], NULL, 0);
    CHROOT_OUT;
    if (vlen == -1) {
      reply_with_perror ("getxattr");
      goto error;
    }

    r->guestfs_int_xattr_list_val[j].attrname = strdup (&buf[i]);
    r->guestfs_int_xattr_list_val[j].attrval.attrval_val = malloc (vlen);
    r->guestfs_int_xattr_list_val[j].attrval.attrval_len = vlen;

    if (r->guestfs_int_xattr_list_val[j].attrname == NULL ||
	r->guestfs_int_xattr_list_val[j].attrval.attrval_val == NULL) {
      reply_with_perror ("malloc");
      goto error;
    }

    CHROOT_IN;
    vlen = getxattr (path, &buf[i],
		     r->guestfs_int_xattr_list_val[j].attrval.attrval_val,
		     vlen);
    CHROOT_OUT;
    if (vlen == -1) {
      reply_with_perror ("getxattr");
      goto error;
    }
  }

  free (buf);

  return r;

 error:
  free (buf);
  if (r) {
    if (r->guestfs_int_xattr_list_val)
      for (i = 0; i < r->guestfs_int_xattr_list_len; ++i) {
	free (r->guestfs_int_xattr_list_val[i].attrname);
	free (r->guestfs_int_xattr_list_val[i].attrval.attrval_val);
      }
    free (r->guestfs_int_xattr_list_val);
  }
  free (r);
  return NULL;
}

static int
_setxattr (char *xattr, char *val, int vallen, char *path,
	   int (*setxattr) (const char *path, const char *name,
			    const void *value, size_t size, int flags))
{
  int r;

  CHROOT_IN;
  r = setxattr (path, xattr, val, vallen, 0);
  CHROOT_OUT;
  if (r == -1) {
    reply_with_perror ("setxattr");
    return -1;
  }

  return 0;
}

static int
_removexattr (char *xattr, char *path,
	      int (*removexattr) (const char *path, const char *name))
{
  int r;

  CHROOT_IN;
  r = removexattr (path, xattr);
  CHROOT_OUT;
  if (r == -1) {
    reply_with_perror ("removexattr");
    return -1;
  }

  return 0;
}

#else /* no xattr.h */

guestfs_int_xattr_list *
do_getxattrs (char *path)
{
  reply_with_error ("getxattrs: no support for xattrs");
  return NULL;
}

guestfs_int_xattr_list *
do_lgetxattrs (char *path)
{
  reply_with_error ("lgetxattrs: no support for xattrs");
  return NULL;
}

int
do_setxattr (char *xattr, char *val, int vallen, char *path)
{
  reply_with_error ("setxattr: no support for xattrs");
  return -1;
}

int
do_lsetxattr (char *xattr, char *val, int vallen, char *path)
{
  reply_with_error ("lsetxattr: no support for xattrs");
  return -1;
}

int
do_removexattr (char *xattr, char *path)
{
  reply_with_error ("removexattr: no support for xattrs");
  return -1;
}

int
do_lremovexattr (char *xattr, char *path)
{
  reply_with_error ("lremovexattr: no support for xattrs");
  return -1;
}

#endif /* no xattr.h */
