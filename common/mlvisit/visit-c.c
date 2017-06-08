/* Bindings for visitor function.
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
#include <string.h>
#include <errno.h>
#include <assert.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include "guestfs.h"
#include "visit.h"

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

struct visitor_function_wrapper_args {
  /* In both case we are pointing to local roots, hence why these are
   * value* not value.
   */
  value *exnp;                  /* Safe place to store any exception
                                   raised by visitor_function. */
  value *fvp;                   /* visitor_function. */
};

static int visitor_function_wrapper (const char *dir, const char *name, const struct guestfs_statns *stat, const struct guestfs_xattr_list *xattrs, void *opaque);
static value copy_statns (const struct guestfs_statns *statns);
static value copy_xattr (const struct guestfs_xattr *xattr);
static value copy_xattr_list (const struct guestfs_xattr_list *xattrs);

value
guestfs_int_mllib_visit (value gv, value dirv, value fv)
{
  CAMLparam3 (gv, dirv, fv);
  guestfs_h *g = (guestfs_h *) (intptr_t) Int64_val (gv);
  struct visitor_function_wrapper_args args;
  /* The dir string could move around when we call the
   * visitor_function, so we have to take a full copy of it.
   */
  char *dir = strdup (String_val (dirv));
  /* This stack address is used to point to the exception, if one is
   * raised in the visitor_function.
   */
  CAMLlocal1 (exn);

  exn = Val_unit;

  args.exnp = &exn;
  args.fvp = &fv;

  if (visit (g, dir, visitor_function_wrapper, &args) == -1) {
    free (dir);

    if (exn != Val_unit) {
      /* The failure was caused by visitor_function raising an
       * exception.  Re-raise it here.
       */
      caml_raise (exn);
    }

    /* Otherwise it's some other failure.  The visit function has
     * already printed the error to stderr (XXX - fix), so we raise a
     * generic Failure.
     */
    caml_failwith ("visit");
  }
  free (dir);

  CAMLreturn (Val_unit);
}

static int
visitor_function_wrapper (const char *dir,
                          const char *filename,
                          const struct guestfs_statns *stat,
                          const struct guestfs_xattr_list *xattrs,
                          void *opaque)
{
  CAMLparam0 ();
  CAMLlocal5 (dirv, filenamev, statv, xattrsv, v);
  struct visitor_function_wrapper_args *args = opaque;

  assert (dir != NULL);
  assert (stat != NULL);
  assert (xattrs != NULL);
  assert (args != NULL);

  dirv = caml_copy_string (dir);
  if (filename == NULL)
    filenamev = Val_int (0);    /* None */
  else {
    filenamev = caml_alloc (1, 0);
    v = caml_copy_string (filename);
    Store_field (filenamev, 0, v);
  }
  statv = copy_statns (stat);
  xattrsv = copy_xattr_list (xattrs);

  /* Call the visitor_function. */
  value argsv[4] = { dirv, filenamev, statv, xattrsv };
  v = caml_callbackN_exn (*args->fvp, 4, argsv);
  if (Is_exception_result (v)) {
    /* The visitor_function raised an exception.  Store the exception
     * in the 'exn' field on the stack of guestfs_int_mllib_visit, and
     * return an error.
     */
    *args->exnp = Extract_exception (v);
    CAMLreturnT (int, -1);
  }

  /* No error, return normally. */
  CAMLreturnT (int, 0);
}

value
guestfs_int_mllib_full_path (value dirv, value namev)
{
  CAMLparam2 (dirv, namev);
  CAMLlocal1 (rv);
  const char *name = NULL;
  char *ret;

  if (namev != Val_int (0))
    name = String_val (Field (namev, 0));

  ret = full_path (String_val (dirv), name);
  rv = caml_copy_string (ret);
  free (ret);

  CAMLreturn (rv);
}

#define is(t)                                           \
  value                                                 \
  guestfs_int_mllib_is_##t (value iv)                   \
  {                                                     \
    return Val_bool (is_##t (Int64_val (iv)));          \
  }
is(reg)
is(dir)
is(chr)
is(blk)
is(fifo)
is(lnk)
is(sock)

/* The functions below are copied from ocaml/guestfs-c-actions.c. */

static value
copy_statns (const struct guestfs_statns *statns)
{
  CAMLparam0 ();
  CAMLlocal2 (rv, v);

  rv = caml_alloc (22, 0);
  v = caml_copy_int64 (statns->st_dev);
  Store_field (rv, 0, v);
  v = caml_copy_int64 (statns->st_ino);
  Store_field (rv, 1, v);
  v = caml_copy_int64 (statns->st_mode);
  Store_field (rv, 2, v);
  v = caml_copy_int64 (statns->st_nlink);
  Store_field (rv, 3, v);
  v = caml_copy_int64 (statns->st_uid);
  Store_field (rv, 4, v);
  v = caml_copy_int64 (statns->st_gid);
  Store_field (rv, 5, v);
  v = caml_copy_int64 (statns->st_rdev);
  Store_field (rv, 6, v);
  v = caml_copy_int64 (statns->st_size);
  Store_field (rv, 7, v);
  v = caml_copy_int64 (statns->st_blksize);
  Store_field (rv, 8, v);
  v = caml_copy_int64 (statns->st_blocks);
  Store_field (rv, 9, v);
  v = caml_copy_int64 (statns->st_atime_sec);
  Store_field (rv, 10, v);
  v = caml_copy_int64 (statns->st_atime_nsec);
  Store_field (rv, 11, v);
  v = caml_copy_int64 (statns->st_mtime_sec);
  Store_field (rv, 12, v);
  v = caml_copy_int64 (statns->st_mtime_nsec);
  Store_field (rv, 13, v);
  v = caml_copy_int64 (statns->st_ctime_sec);
  Store_field (rv, 14, v);
  v = caml_copy_int64 (statns->st_ctime_nsec);
  Store_field (rv, 15, v);
  v = caml_copy_int64 (statns->st_spare1);
  Store_field (rv, 16, v);
  v = caml_copy_int64 (statns->st_spare2);
  Store_field (rv, 17, v);
  v = caml_copy_int64 (statns->st_spare3);
  Store_field (rv, 18, v);
  v = caml_copy_int64 (statns->st_spare4);
  Store_field (rv, 19, v);
  v = caml_copy_int64 (statns->st_spare5);
  Store_field (rv, 20, v);
  v = caml_copy_int64 (statns->st_spare6);
  Store_field (rv, 21, v);
  CAMLreturn (rv);
}

static value
copy_xattr (const struct guestfs_xattr *xattr)
{
  CAMLparam0 ();
  CAMLlocal2 (rv, v);

  rv = caml_alloc (2, 0);
  v = caml_copy_string (xattr->attrname);
  Store_field (rv, 0, v);
  v = caml_alloc_string (xattr->attrval_len);
  memcpy (String_val (v), xattr->attrval, xattr->attrval_len);
  Store_field (rv, 1, v);
  CAMLreturn (rv);
}

static value
copy_xattr_list (const struct guestfs_xattr_list *xattrs)
{
  CAMLparam0 ();
  CAMLlocal2 (rv, v);
  unsigned int i;

  if (xattrs->len == 0)
    CAMLreturn (Atom (0));
  else {
    rv = caml_alloc (xattrs->len, 0);
    for (i = 0; i < xattrs->len; ++i) {
      v = copy_xattr (&xattrs->val[i]);
      Store_field (rv, i, v);
    }
    CAMLreturn (rv);
  }
}
