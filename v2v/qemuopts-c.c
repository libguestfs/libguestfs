/* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#ifdef HAVE_CAML_UNIXSUPPORT_H
#include <caml/unixsupport.h>
#else
#define Nothing ((value) 0)
extern void unix_error (int errcode, char * cmdname, value arg) Noreturn;
#endif

#include "qemuopts.h"

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

#define Qopts_val(v) (*((struct qemuopts **)Data_custom_val(v)))

static void
qopts_finalize (value qoptsv)
{
  struct qemuopts *qopts = Qopts_val (qoptsv);

  if (qopts)
    qemuopts_free (qopts);
}

static struct custom_operations qemuopts_custom_operations = {
  (char *) "qemuopts_custom_operations",
  qopts_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

value
guestfs_int_qemuopts_create (value unitv)
{
  CAMLparam1 (unitv);
  CAMLlocal1 (qoptsv);
  struct qemuopts *qopts;

  qopts = qemuopts_create ();
  if (qopts == NULL)
    unix_error (errno, (char *) "qemuopts_create", Nothing);

  qoptsv = caml_alloc_custom (&qemuopts_custom_operations,
                              sizeof (struct qemuopts *), 0, 1);
  Qopts_val (qoptsv) = qopts;

  CAMLreturn (qoptsv);
}

value
guestfs_int_qemuopts_set_binary (value qoptsv, value strv)
{
  CAMLparam2 (qoptsv, strv);
  struct qemuopts *qopts = Qopts_val (qoptsv);

  if (qemuopts_set_binary (qopts, String_val (strv)) == -1)
    unix_error (errno, (char *) "qemuopts_set_binary", strv);

  CAMLreturn (Val_unit);
}

value
guestfs_int_qemuopts_set_binary_by_arch (value qoptsv, value ostrv)
{
  CAMLparam2 (qoptsv, ostrv);
  struct qemuopts *qopts = Qopts_val (qoptsv);
  int r;

  if (ostrv != Val_int (0))
    r = qemuopts_set_binary_by_arch (qopts, NULL);
  else
    r = qemuopts_set_binary_by_arch (qopts, String_val (Field (ostrv, 0)));

  if (r == -1)
    unix_error (errno, (char *) "qemuopts_set_binary_by_arch", Nothing);

  CAMLreturn (Val_unit);
}

value
guestfs_int_qemuopts_flag (value qoptsv, value flagv)
{
  CAMLparam2 (qoptsv, flagv);
  struct qemuopts *qopts = Qopts_val (qoptsv);

  if (qemuopts_add_flag (qopts, String_val (flagv)) == -1)
    unix_error (errno, (char *) "qemuopts_add_flag", flagv);

  CAMLreturn (Val_unit);
}

value
guestfs_int_qemuopts_arg (value qoptsv, value flagv, value valv)
{
  CAMLparam3 (qoptsv, flagv, valv);
  struct qemuopts *qopts = Qopts_val (qoptsv);

  if (qemuopts_add_arg (qopts, String_val (flagv), String_val (valv)) == -1)
    unix_error (errno, (char *) "qemuopts_add_arg", flagv);

  CAMLreturn (Val_unit);
}

value
guestfs_int_qemuopts_arg_noquote (value qoptsv, value flagv, value valv)
{
  CAMLparam3 (qoptsv, flagv, valv);
  struct qemuopts *qopts = Qopts_val (qoptsv);

  if (qemuopts_add_arg_noquote (qopts,
                                String_val (flagv), String_val (valv)) == -1)
    unix_error (errno, (char *) "qemuopts_add_arg_noquote", flagv);

  CAMLreturn (Val_unit);
}

value
guestfs_int_qemuopts_arg_list (value qoptsv, value flagv, value valuesv)
{
  CAMLparam3 (qoptsv, flagv, valuesv);
  CAMLlocal1 (hd);
  struct qemuopts *qopts = Qopts_val (qoptsv);

  if (qemuopts_start_arg_list (qopts, String_val (flagv)) == -1)
    unix_error (errno, (char *) "qemuopts_start_arg_list", flagv);

  while (valuesv != Val_emptylist) {
    hd = Field (valuesv, 0);
    if (qemuopts_append_arg_list (qopts, String_val (hd)) == -1)
      unix_error (errno, (char *) "qemuopts_append_arg_list", flagv);
    valuesv = Field (valuesv, 1);
  }

  if (qemuopts_end_arg_list (qopts) == -1)
    unix_error (errno, (char *) "qemuopts_end_arg_list", flagv);

  CAMLreturn (Val_unit);
}

value
guestfs_int_qemuopts_to_script (value qoptsv, value strv)
{
  CAMLparam2 (qoptsv, strv);
  struct qemuopts *qopts = Qopts_val (qoptsv);

  if (qemuopts_to_script (qopts, String_val (strv)) == -1)
    unix_error (errno, (char *) "qemuopts_to_script", strv);

  CAMLreturn (Val_unit);
}

value
guestfs_int_qemuopts_to_chan (value qoptsv, value fdv)
{
  CAMLparam2 (qoptsv, fdv);
  struct qemuopts *qopts = Qopts_val (qoptsv);
  /* Note that Unix.file_descr is really just an int. */
  int fd = Int_val (fdv);
  int fd2;
  FILE *fp;
  int saved_errno;

  /* Dup the file descriptor so we don't lose it in fclose. */
  fd2 = dup (fd);
  if (fd2 == -1)
    unix_error (errno, (char *) "qemuopts_to_channel: dup", Nothing);

  fp = fdopen (fd2, "w");
  if (fp == NULL) {
    saved_errno = errno;
    close (fd2);
    unix_error (saved_errno, (char *) "qemuopts_to_channel: fdopen", Nothing);
  }

  if (qemuopts_to_channel (qopts, fp) == -1) {
    saved_errno = errno;
    fclose (fp);
    unix_error (saved_errno, (char *) "qemuopts_to_channel", Nothing);
  }

  if (fclose (fp) == EOF)
    unix_error (errno, (char *) "qemuopts_to_channel: fclose", Nothing);

  CAMLreturn (Val_unit);
}
