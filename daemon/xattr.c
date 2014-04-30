/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2014 Red Hat Inc.
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
#include <limits.h>
#include <unistd.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#if (defined(HAVE_ATTR_XATTR_H) || defined(HAVE_SYS_XATTR_H)) && \
    defined(HAVE_LISTXATTR) && defined(HAVE_LLISTXATTR) && \
    defined(HAVE_GETXATTR) && defined(HAVE_LGETXATTR) && \
    defined(HAVE_REMOVEXATTR) && defined(HAVE_LREMOVEXATTR) && \
    defined(HAVE_SETXATTR) && defined(HAVE_LSETXATTR)
# define HAVE_LINUX_XATTRS
#endif

#ifdef HAVE_LINUX_XATTRS

# ifdef HAVE_ATTR_XATTR_H
#  include <attr/xattr.h>
# else
#  ifdef HAVE_SYS_XATTR_H
#   include <sys/xattr.h>
#  endif
# endif

int
optgroup_linuxxattrs_available (void)
{
  return 1;
}

static guestfs_int_xattr_list *getxattrs (const char *path, ssize_t (*listxattr) (const char *path, char *list, size_t size), ssize_t (*getxattr) (const char *path, const char *name, void *value, size_t size));
static int _setxattr (const char *xattr, const char *val, int vallen, const char *path, int (*setxattr) (const char *path, const char *name, const void *value, size_t size, int flags));
static int _removexattr (const char *xattr, const char *path, int (*removexattr) (const char *path, const char *name));
static char *_listxattrs (const char *path, ssize_t (*listxattr) (const char *path, char *list, size_t size), ssize_t *size);
static char *_getxattr (const char *name, const char *path, ssize_t (*getxattr) (const char *path, const char *name, void *value, size_t size), size_t *size_r);

guestfs_int_xattr_list *
do_getxattrs (const char *path)
{
  return getxattrs (path, listxattr, getxattr);
}

guestfs_int_xattr_list *
do_lgetxattrs (const char *path)
{
  return getxattrs (path, llistxattr, lgetxattr);
}

int
do_setxattr (const char *xattr, const char *val, int vallen, const char *path)
{
  return _setxattr (xattr, val, vallen, path, setxattr);
}

int
do_lsetxattr (const char *xattr, const char *val, int vallen, const char *path)
{
  return _setxattr (xattr, val, vallen, path, lsetxattr);
}

int
do_removexattr (const char *xattr, const char *path)
{
  return _removexattr (xattr, path, removexattr);
}

int
do_lremovexattr (const char *xattr, const char *path)
{
  return _removexattr (xattr, path, lremovexattr);
}

static int
compare_xattrs (const void *vxa1, const void *vxa2)
{
  const guestfs_int_xattr *xa1 = vxa1;
  const guestfs_int_xattr *xa2 = vxa2;

  return strcmp (xa1->attrname, xa2->attrname);
}

static guestfs_int_xattr_list *
getxattrs (const char *path,
           ssize_t (*listxattr) (const char *path, char *list, size_t size),
           ssize_t (*getxattr) (const char *path, const char *name,
                                void *value, size_t size))
{
  ssize_t len, vlen;
  CLEANUP_FREE char *buf = NULL;
  size_t i, j;
  guestfs_int_xattr_list *r = NULL;

  buf = _listxattrs (path, listxattr, &len);
  if (buf == NULL)
    /* _listxattrs issues reply_with_perror already. */
    goto error;

  r = calloc (1, sizeof (*r));
  if (r == NULL) {
    reply_with_perror ("malloc");
    goto error;
  }

  /* What we get from the kernel is a string "foo\0bar\0baz" of length
   * len.  First count the strings.
   */
  r->guestfs_int_xattr_list_len = 0;
  for (i = 0; i < (size_t) len; i += strlen (&buf[i]) + 1)
    r->guestfs_int_xattr_list_len++;

  r->guestfs_int_xattr_list_val =
    calloc (r->guestfs_int_xattr_list_len, sizeof (guestfs_int_xattr));
  if (r->guestfs_int_xattr_list_val == NULL) {
    reply_with_perror ("calloc");
    goto error;
  }

  for (i = 0, j = 0; i < (size_t) len; i += strlen (&buf[i]) + 1, ++j) {
    CHROOT_IN;
    vlen = getxattr (path, &buf[i], NULL, 0);
    CHROOT_OUT;
    if (vlen == -1) {
      reply_with_perror ("getxattr");
      goto error;
    }

    if (vlen > XATTR_SIZE_MAX) {
      /* The next call to getxattr will fail anyway, so ... */
      reply_with_error ("extended attribute is too large");
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

  /* Sort the entries by attrname. */
  qsort (&r->guestfs_int_xattr_list_val[0],
         (size_t) r->guestfs_int_xattr_list_len,
         sizeof (guestfs_int_xattr),
         compare_xattrs);

  return r;

 error:
  if (r) {
    if (r->guestfs_int_xattr_list_val) {
      size_t k;
      for (k = 0; k < r->guestfs_int_xattr_list_len; ++k) {
        free (r->guestfs_int_xattr_list_val[k].attrname);
        free (r->guestfs_int_xattr_list_val[k].attrval.attrval_val);
      }
    }
    free (r->guestfs_int_xattr_list_val);
  }
  free (r);
  return NULL;
}

static int
_setxattr (const char *xattr, const char *val, int vallen, const char *path,
           int (*setxattr) (const char *path, const char *name,
                            const void *value, size_t size, int flags))
{
  int r;

  if (vallen > XATTR_SIZE_MAX) {
    reply_with_error ("extended attribute is too large");
    return -1;
  }

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
_removexattr (const char *xattr, const char *path,
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

static char *
_listxattrs (const char *path,
             ssize_t (*listxattr) (const char *path, char *list, size_t size),
             ssize_t *size)
{
  char *buf = NULL;
  ssize_t len;

  CHROOT_IN;
  len = listxattr (path, NULL, 0);
  CHROOT_OUT;
  if (len == -1) {
    reply_with_perror ("listxattr: %s", path);
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
    reply_with_perror ("listxattr: %s", path);
    goto error;
  }

  if (size)
    *size = len;
  return buf;

 error:
  free (buf);
  return NULL;
}

guestfs_int_xattr_list *
do_internal_lxattrlist (const char *path, char *const *names)
{
  guestfs_int_xattr_list *ret = NULL;
  size_t i, j;
  size_t k, m, nr_attrs;
  ssize_t len, vlen;

  ret = malloc (sizeof (*ret));
  if (ret == NULL) {
    reply_with_perror ("malloc");
    goto error;
  }

  ret->guestfs_int_xattr_list_len = 0;
  ret->guestfs_int_xattr_list_val = NULL;

  for (k = 0; names[k] != NULL; ++k) {
    void *newptr;
    CLEANUP_FREE char *pathname = NULL;
    CLEANUP_FREE char *buf = NULL;

    /* Be careful in this loop about which errors cause the whole call
     * to abort, and which errors allow us to continue processing
     * the call, recording a special "error attribute" in the
     * outgoing struct list.
     */

    /* XXX This would be easier if the kernel had lgetxattrat.  In the
     * meantime we use the 'pathname' buffer to store the whole path
     * name.
     */
    if (asprintf (&pathname, "%s/%s", path, names[k]) == -1) {
      reply_with_perror ("asprintf");
      goto error;
    }

    /* Reserve space for the special attribute. */
    newptr = realloc (ret->guestfs_int_xattr_list_val,
                      (ret->guestfs_int_xattr_list_len+1) *
                      sizeof (guestfs_int_xattr));
    if (newptr == NULL) {
      reply_with_perror ("realloc");
      goto error;
    }
    ret->guestfs_int_xattr_list_val = newptr;
    ret->guestfs_int_xattr_list_len++;

    guestfs_int_xattr *entry =
      &ret->guestfs_int_xattr_list_val[ret->guestfs_int_xattr_list_len-1];
    entry->attrname = NULL;
    entry->attrval.attrval_len = 0;
    entry->attrval.attrval_val = NULL;

    entry->attrname = strdup ("");
    if (entry->attrname == NULL) {
      reply_with_perror ("strdup");
      goto error;
    }

    CHROOT_IN;
    len = llistxattr (pathname, NULL, 0);
    CHROOT_OUT;
    if (len == -1)
      continue; /* not fatal */

    buf = malloc (len);
    if (buf == NULL) {
      reply_with_perror ("malloc");
      goto error;
    }

    CHROOT_IN;
    len = llistxattr (pathname, buf, len);
    CHROOT_OUT;
    if (len == -1)
      continue; /* not fatal */

    /* What we get from the kernel is a string "foo\0bar\0baz" of length
     * len.  First count the strings.
     */
    nr_attrs = 0;
    for (i = 0; i < (size_t) len; i += strlen (&buf[i]) + 1)
      nr_attrs++;

    newptr =
      realloc (ret->guestfs_int_xattr_list_val,
               (ret->guestfs_int_xattr_list_len+nr_attrs) *
               sizeof (guestfs_int_xattr));
    if (newptr == NULL) {
      reply_with_perror ("realloc");
      goto error;
    }
    ret->guestfs_int_xattr_list_val = newptr;
    ret->guestfs_int_xattr_list_len += nr_attrs;

    /* entry[0] is the special attribute,
     * entry[1..nr_attrs] are the attributes.
     */
    entry = &ret->guestfs_int_xattr_list_val[ret->guestfs_int_xattr_list_len-nr_attrs-1];
    for (m = 1; m <= nr_attrs; ++m) {
      entry[m].attrname = NULL;
      entry[m].attrval.attrval_len = 0;
      entry[m].attrval.attrval_val = NULL;
    }

    for (i = 0, j = 0; i < (size_t) len; i += strlen (&buf[i]) + 1, ++j) {
      CHROOT_IN;
      vlen = lgetxattr (pathname, &buf[i], NULL, 0);
      CHROOT_OUT;
      if (vlen == -1) {
        reply_with_perror ("getxattr");
        goto error;
      }

      if (vlen > XATTR_SIZE_MAX) {
        reply_with_error ("extended attribute is too large");
        goto error;
      }

      entry[j+1].attrname = strdup (&buf[i]);
      entry[j+1].attrval.attrval_val = malloc (vlen);
      entry[j+1].attrval.attrval_len = vlen;

      if (entry[j+1].attrname == NULL ||
          entry[j+1].attrval.attrval_val == NULL) {
        reply_with_perror ("malloc");
        goto error;
      }

      CHROOT_IN;
      vlen = lgetxattr (pathname, &buf[i],
                        entry[j+1].attrval.attrval_val, vlen);
      CHROOT_OUT;
      if (vlen == -1) {
        reply_with_perror ("getxattr");
        goto error;
      }
    }

    char num[16];
    snprintf (num, sizeof num, "%zu", nr_attrs);
    entry[0].attrval.attrval_len = strlen (num) + 1;
    entry[0].attrval.attrval_val = strdup (num);

    if (entry[0].attrval.attrval_val == NULL) {
      reply_with_perror ("strdup");
      goto error;
    }

    /* Sort the entries by attrname (only for this single file). */
    qsort (&entry[1], nr_attrs, sizeof (guestfs_int_xattr), compare_xattrs);
  }

  return ret;

 error:
  if (ret) {
    if (ret->guestfs_int_xattr_list_val) {
      for (k = 0; k < ret->guestfs_int_xattr_list_len; ++k) {
        free (ret->guestfs_int_xattr_list_val[k].attrname);
        free (ret->guestfs_int_xattr_list_val[k].attrval.attrval_val);
      }
      free (ret->guestfs_int_xattr_list_val);
    }
    free (ret);
  }
  return NULL;
}

char *
do_getxattr (const char *path, const char *name, size_t *size_r)
{
  return _getxattr (name, path, getxattr, size_r);
}

static char *
_getxattr (const char *name, const char *path,
           ssize_t (*getxattr) (const char *path, const char *name,
                                void *value, size_t size),
           size_t *size_r)
{
  ssize_t r;
  char *buf;
  size_t len;

  CHROOT_IN;
  r = getxattr (path, name, NULL, 0);
  CHROOT_OUT;
  if (r == -1) {
    reply_with_perror ("getxattr");
    return NULL;
  }

  len = r;

  if (len > XATTR_SIZE_MAX) {
    reply_with_error ("extended attribute is too large");
    return NULL;
  }

  buf = malloc (len);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  CHROOT_IN;
  r = getxattr (path, name, buf, len);
  CHROOT_OUT;
  if (r == -1) {
    reply_with_perror ("getxattr");
    free (buf);
    return NULL;
  }

  if (len != (size_t) r) {
    reply_with_error ("getxattr: unexpected size (%zu/%zd)", len, r);
    free (buf);
    return NULL;
  }

  /* Must set size_r last thing before returning. */
  *size_r = len;
  return buf; /* caller frees */
}

char *
do_lgetxattr (const char *path, const char *name, size_t *size_r)
{
  return _getxattr (name, path, lgetxattr, size_r);
}

int
copy_xattrs (const char *src, const char *dest)
{
  ssize_t len, vlen, ret, attrval_len = 0;
  CLEANUP_FREE char *buf = NULL, *attrval = NULL;
  size_t i;

  buf = _listxattrs (src, listxattr, &len);
  if (buf == NULL)
    /* _listxattrs issues reply_with_perror already. */
    goto error;

  /* What we get from the kernel is a string "foo\0bar\0baz" of length
   * len.
   */
  for (i = 0; i < (size_t) len; i += strlen (&buf[i]) + 1) {
    CHROOT_IN;
    vlen = getxattr (src, &buf[i], NULL, 0);
    CHROOT_OUT;
    if (vlen == -1) {
      reply_with_perror ("getxattr: %s, %s", src, &buf[i]);
      goto error;
    }

    if (vlen > XATTR_SIZE_MAX) {
      /* The next call to getxattr will fail anyway, so ... */
      reply_with_error ("extended attribute is too large");
      goto error;
    }

    if (vlen > attrval_len) {
      char *new = realloc (attrval, vlen);
      if (new == NULL) {
        reply_with_perror ("realloc");
        goto error;
      }
      attrval = new;
      attrval_len = vlen;
    }

    CHROOT_IN;
    vlen = getxattr (src, &buf[i], attrval, vlen);
    CHROOT_OUT;
    if (vlen == -1) {
      reply_with_perror ("getxattr: %s, %s", src, &buf[i]);
      goto error;
    }

    CHROOT_IN;
    ret = setxattr (dest, &buf[i], attrval, vlen, 0);
    CHROOT_OUT;
    if (ret == -1) {
      reply_with_perror ("setxattr: %s, %s", dest, &buf[i]);
      goto error;
    }
  }

  return 1;

 error:
  return 0;
}

#else /* no HAVE_LINUX_XATTRS */

OPTGROUP_LINUXXATTRS_NOT_AVAILABLE

int
copy_xattrs (const char *src, const char *dest)
{
  abort ();
}

#endif /* no HAVE_LINUX_XATTRS */
