/* Augeas OCaml bindings
 * Copyright (C) 2008-2017 Red Hat Inc., Richard W.M. Jones
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
 *
 * $Id: augeas_c.c,v 1.1 2008/05/06 10:48:20 rjones Exp $
 */

#include "config.h"

#include <augeas.h>

#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/fail.h>
#include <caml/callback.h>
#include <caml/custom.h>

#include <stdbool.h>

#ifdef __GNUC__
  #define NORETURN __attribute__ ((noreturn))
#else
  #define NORETURN
#endif

extern CAMLprim value ocaml_augeas_create (value rootv, value loadpathv, value flagsv);
extern CAMLprim value ocaml_augeas_close (value tv);
extern CAMLprim value ocaml_augeas_defnode (value tv, value namev, value exprv, value valv);
extern CAMLprim value ocaml_augeas_defvar (value tv, value namev, value exprv);
extern CAMLprim value ocaml_augeas_get (value tv, value pathv);
extern CAMLprim value ocaml_augeas_exists (value tv, value pathv);
extern CAMLprim value ocaml_augeas_insert (value tv, value beforev, value pathv, value labelv);
extern CAMLprim value ocaml_augeas_label (value tv, value pathv);
extern CAMLprim value ocaml_augeas_mv (value tv, value srcv, value destv);
extern CAMLprim value ocaml_augeas_rm (value tv, value pathv);
extern CAMLprim value ocaml_augeas_match (value tv, value pathv);
extern CAMLprim value ocaml_augeas_count_matches (value tv, value pathv);
extern CAMLprim value ocaml_augeas_save (value tv);
extern CAMLprim value ocaml_augeas_load (value tv);
extern CAMLprim value ocaml_augeas_set (value tv, value pathv, value valuev);
extern CAMLprim value ocaml_augeas_setm (value tv, value basev, value subv, value valv);
extern CAMLprim value ocaml_augeas_transform (value tv, value lensv, value filev, value modev);
extern CAMLprim value ocaml_augeas_source (value tv, value pathv)
#ifndef HAVE_AUG_SOURCE
  NORETURN
#endif
;

typedef augeas *augeas_t;

/* Map C aug_errcode_t to OCaml error_code. */
static const int error_map[] = {
  /* AugErrInternal */ AUG_EINTERNAL,
  /* AugErrPathX */    AUG_EPATHX,
  /* AugErrNoMatch */  AUG_ENOMATCH,
  /* AugErrMMatch */   AUG_EMMATCH,
  /* AugErrSyntax */   AUG_ESYNTAX,
  /* AugErrNoLens */   AUG_ENOLENS,
  /* AugErrMXfm */     AUG_EMXFM,
  /* AugErrNoSpan */   AUG_ENOSPAN,
  /* AugErrMvDesc */   AUG_EMVDESC,
  /* AugErrCmdRun */   AUG_ECMDRUN,
  /* AugErrBadArg */   AUG_EBADARG,
  /* AugErrLabel */    AUG_ELABEL,
  /* AugErrCpDesc */   AUG_ECPDESC,
};
static const int error_map_len = sizeof error_map / sizeof error_map[0];

/* Raise an Augeas.Error exception, and optionally close the
 * specified handle.
 */
static void
raise_error_and_maybe_close (augeas_t t, const char *msg, bool close_handle)
{
  const value *exn = caml_named_value ("Augeas.Error");
  value args[5];
  const int code = aug_error (t);
  const char *aug_err_msg;
  const char *aug_err_minor;
  const char *aug_err_details;
  int ocaml_code = -1;
  int i;

  if (code == AUG_ENOMEM) {
    if (close_handle)
      aug_close (t);
    caml_raise_out_of_memory ();
  }

  aug_err_msg = aug_error_message (t);
  aug_err_minor = aug_error_minor_message (t);
  aug_err_details = aug_error_details (t);

  for (i = 0; i < error_map_len; ++i)
    if (error_map[i] == code) {
      ocaml_code = i;
      break;
    }

  if (ocaml_code != -1)
    args[0] = Val_int (ocaml_code);
  else {
    args[0] = caml_alloc (1, 0);
    Store_field (args[0], 0, Val_int (code));
  }
  args[1] = caml_copy_string (msg);
  args[2] = caml_copy_string (aug_err_msg);
  args[3] = caml_copy_string (aug_err_minor ? : "");
  args[4] = caml_copy_string (aug_err_details ? : "");

  if (close_handle)
    aug_close (t);

  caml_raise_with_args (*exn, 5, args);
}
#define raise_error(t, msg) raise_error_and_maybe_close(t, msg, false)

static void
raise_init_error (const char *msg)
{
  const value *exn = caml_named_value ("Augeas.Error");
  value args[5];

  args[0] = caml_alloc (1, 0);
  Store_field (args[0], 0, Val_int (-1));
  args[1] = caml_copy_string (msg);
  args[2] = caml_copy_string ("aug_init failed");
  args[3] = caml_copy_string ("augeas initialization failed");
  args[4] = caml_copy_string ("");

  caml_raise_with_args (*exn, 5, args);
}

static const char *
Optstring_val (value strv)
{
  if (strv == Val_int (0))      /* None */
    return NULL;
  else                          /* Some string */
    return String_val (Field (strv, 0));
}

/* Map OCaml flags to C flags. */
static const int flag_map[] = {
  /* AugSaveBackup */  AUG_SAVE_BACKUP,
  /* AugSaveNewFile */ AUG_SAVE_NEWFILE,
  /* AugTypeCheck */   AUG_TYPE_CHECK,
  /* AugNoStdinc */    AUG_NO_STDINC,
  /* AugSaveNoop */    AUG_SAVE_NOOP,
  /* AugNoLoad */      AUG_NO_LOAD,
  /* AugNoModlAutoload */ AUG_NO_MODL_AUTOLOAD,
  /* AugEnableSpan */  AUG_ENABLE_SPAN,
  /* AugNoErrClose */  AUG_NO_ERR_CLOSE,
  /* AugTraceModuleLoading */ AUG_TRACE_MODULE_LOADING,
};

/* Wrap and unwrap augeas_t handles, with a finalizer. */
#define Augeas_t_val(rv) (*(augeas_t *)Data_custom_val(rv))

static void
augeas_t_finalize (value tv)
{
  augeas_t t = Augeas_t_val (tv);
  if (t) aug_close (t);
}

static struct custom_operations custom_operations = {
  (char *) "augeas_t_custom_operations",
  augeas_t_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
};

static value Val_augeas_t (augeas_t t)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);
  /* We could choose these so that the GC can make better decisions.
   * See 18.9.2 of the OCaml manual.
   */
  const int used = 0;
  const int max = 1;

  rv = caml_alloc_custom (&custom_operations,
			  sizeof (augeas_t), used, max);
  Augeas_t_val(rv) = t;

  CAMLreturn (rv);
}

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

/* val create : string -> string option -> flag list -> t */
CAMLprim value
ocaml_augeas_create (value rootv, value loadpathv, value flagsv)
{
  CAMLparam1 (rootv);
  const char *root = String_val (rootv);
  const char *loadpath = Optstring_val (loadpathv);
  int flags = 0, i;
  augeas_t t;

  /* Convert list of flags to C. */
  for (; flagsv != Val_int (0); flagsv = Field (flagsv, 1)) {
    i = Int_val (Field (flagsv, 0));
    flags |= flag_map[i];
  }

  /* Pass AUG_NO_ERR_CLOSE so we raise a detailed Augeas.Error. */
  t = aug_init (root, loadpath, flags | AUG_NO_ERR_CLOSE);

  if (t == NULL)
    raise_init_error ("Augeas.create");

  if (aug_error (t) != AUG_NOERROR) {
    raise_error_and_maybe_close (t, "Augeas.init", true);
  }

  CAMLreturn (Val_augeas_t (t));
}

/* val close : t -> unit */
CAMLprim value
ocaml_augeas_close (value tv)
{
  CAMLparam1 (tv);
  augeas_t t = Augeas_t_val (tv);

  if (t) {
    aug_close (t);
    Augeas_t_val(tv) = NULL;	/* So the finalizer doesn't double-free. */
  }

  CAMLreturn (Val_unit);
}

/* val defnode : t -> string -> string -> string option -> int * bool */
CAMLprim value
ocaml_augeas_defnode (value tv, value namev, value exprv, value valv)
{
  CAMLparam4 (tv, namev, exprv, valv);
  CAMLlocal2 (optv, v);
  augeas_t t = Augeas_t_val (tv);
  const char *name = String_val (namev);
  const char *expr = String_val (exprv);
  const char *val = Optstring_val (valv);
  int r, created;

  r = aug_defnode (t, name, expr, val, &created);
  if (r == -1) {
    raise_error (t, "Augeas.defnode");
  }

  v = caml_alloc (2, 0);
  Store_field (v, 0, Val_int (r));
  Store_field (v, 1, Val_bool (created));

  CAMLreturn (v);
}

/* val defvar : t -> string -> string option -> int option */
CAMLprim value
ocaml_augeas_defvar (value tv, value namev, value exprv)
{
  CAMLparam3 (tv, namev, exprv);
  CAMLlocal2 (optv, v);
  augeas_t t = Augeas_t_val (tv);
  const char *name = String_val (namev);
  const char *expr = Optstring_val (exprv);
  int r;

  r = aug_defvar (t, name, expr);
  if (r > 0) {		/* Return Some val */
    v = Val_int (r);
    optv = caml_alloc (1, 0);
    Field (optv, 0) = v;
  } else if (r == 0)	/* Return None */
    optv = Val_int (0);
  else if (r == -1)		/* Error or multiple matches */
    raise_error (t, "Augeas.defvar");
  else
    caml_failwith ("Augeas.defvar: bad return value");

  CAMLreturn (optv);
}

/* val get : t -> path -> value option */
CAMLprim value
ocaml_augeas_get (value tv, value pathv)
{
  CAMLparam2 (tv, pathv);
  CAMLlocal2 (optv, v);
  augeas_t t = Augeas_t_val (tv);
  const char *path = String_val (pathv);
  const char *val;
  int r;

  r = aug_get (t, path, &val);
  if (r == 1 && val) {		/* Return Some val */
    v = caml_copy_string (val);
    optv = caml_alloc (1, 0);
    Field (optv, 0) = v;
  } else if (r == 0 || !val)	/* Return None */
    optv = Val_int (0);
  else if (r == -1)		/* Error or multiple matches */
    raise_error (t, "Augeas.get");
  else
    caml_failwith ("Augeas.get: bad return value");

  CAMLreturn (optv);
}

/* val exists : t -> path -> bool */
CAMLprim value
ocaml_augeas_exists (value tv, value pathv)
{
  CAMLparam2 (tv, pathv);
  CAMLlocal1 (v);
  augeas_t t = Augeas_t_val (tv);
  const char *path = String_val (pathv);
  int r;

  r = aug_get (t, path, NULL);
  if (r == 1)			/* Return true. */
    v = Val_int (1);
  else if (r == 0)		/* Return false */
    v = Val_int (0);
  else if (r == -1)		/* Error or multiple matches */
    raise_error (t, "Augeas.exists");
  else
    caml_failwith ("Augeas.exists: bad return value");

  CAMLreturn (v);
}

/* val insert : t -> ?before:bool -> path -> string -> unit */
CAMLprim value
ocaml_augeas_insert (value tv, value beforev, value pathv, value labelv)
{
  CAMLparam4 (tv, beforev, pathv, labelv);
  augeas_t t = Augeas_t_val (tv);
  const char *path = String_val (pathv);
  const char *label = String_val (labelv);
  int before;

  before = beforev == Val_int (0) ? 0 : Int_val (Field (beforev, 0));

  if (aug_insert (t, path, label, before) == -1)
    raise_error (t, "Augeas.insert");

  CAMLreturn (Val_unit);
}

/* val label : t -> path -> string option */
CAMLprim value
ocaml_augeas_label (value tv, value pathv)
{
  CAMLparam2 (tv, pathv);
  CAMLlocal2 (optv, v);
  augeas_t t = Augeas_t_val (tv);
  const char *path = String_val (pathv);
  const char *val;
  int r;

  r = aug_label (t, path, &val);
  if (r == 1 && val) {		/* Return Some val */
    v = caml_copy_string (val);
    optv = caml_alloc (1, 0);
    Field (optv, 0) = v;
  } else if (r == 0 || !val)	/* Return None */
    optv = Val_int (0);
  else if (r == -1)		/* Error or multiple matches */
    raise_error (t, "Augeas.label");
  else
    caml_failwith ("Augeas.label: bad return value");

  CAMLreturn (optv);
}

/* val mv : t -> path -> path -> unit */
CAMLprim value
ocaml_augeas_mv (value tv, value srcv, value destv)
{
  CAMLparam3 (tv, srcv, destv);
  augeas_t t = Augeas_t_val (tv);
  const char *src = String_val (srcv);
  const char *dest = String_val (destv);

  if (aug_mv (t, src, dest) == -1)
    raise_error (t, "Augeas.mv");

  CAMLreturn (Val_unit);
}

/* val rm : t -> path -> int */
CAMLprim value
ocaml_augeas_rm (value tv, value pathv)
{
  CAMLparam2 (tv, pathv);
  augeas_t t = Augeas_t_val (tv);
  const char *path = String_val (pathv);
  int r;

  r = aug_rm (t, path);
  if (r == -1)
    raise_error (t, "Augeas.rm");

  CAMLreturn (Val_int (r));
}

/* val matches : t -> path -> path list */
CAMLprim value
ocaml_augeas_match (value tv, value pathv)
{
  CAMLparam2 (tv, pathv);
  CAMLlocal3 (rv, v, cons);
  augeas_t t = Augeas_t_val (tv);
  const char *path = String_val (pathv);
  char **matches;
  int r, i;

  r = aug_match (t, path, &matches);
  if (r == -1)
    raise_error (t, "Augeas.matches");

  /* Copy the paths to a list. */
  rv = Val_int (0);
  for (i = 0; i < r; ++i) {
    v = caml_copy_string (matches[i]);
    free (matches[i]);
    cons = caml_alloc (2, 0);
    Field (cons, 1) = rv;
    Field (cons, 0) = v;
    rv = cons;
  }

  free (matches);

  CAMLreturn (rv);
}

/* val count_matches : t -> path -> int */
CAMLprim value
ocaml_augeas_count_matches (value tv, value pathv)
{
  CAMLparam2 (tv, pathv);
  augeas_t t = Augeas_t_val (tv);
  const char *path = String_val (pathv);
  int r;

  r = aug_match (t, path, NULL);
  if (r == -1)
    raise_error (t, "Augeas.count_matches");

  CAMLreturn (Val_int (r));
}

/* val save : t -> unit */
CAMLprim value
ocaml_augeas_save (value tv)
{
  CAMLparam1 (tv);
  augeas_t t = Augeas_t_val (tv);

  if (aug_save (t) == -1)
    raise_error (t, "Augeas.save");

  CAMLreturn (Val_unit);
}

/* val load : t -> unit */
CAMLprim value
ocaml_augeas_load (value tv)
{
  CAMLparam1 (tv);
  augeas_t t = Augeas_t_val (tv);

  if (aug_load (t) == -1)
    raise_error (t, "Augeas.load");

  CAMLreturn (Val_unit);
}

/* val set : t -> -> path -> value option -> unit */
CAMLprim value
ocaml_augeas_set (value tv, value pathv, value valuev)
{
  CAMLparam3 (tv, pathv, valuev);
  augeas_t t = Augeas_t_val (tv);
  const char *path = String_val (pathv);
  const char *val = Optstring_val (valuev);

  if (aug_set (t, path, val) == -1)
    raise_error (t, "Augeas.set");

  CAMLreturn (Val_unit);
}

/* val setm : t -> path -> string option -> value option -> int */
CAMLprim value
ocaml_augeas_setm (value tv, value basev, value subv, value valv)
{
  CAMLparam4 (tv, basev, subv, valv);
  augeas_t t = Augeas_t_val (tv);
  const char *base = String_val (basev);
  const char *sub = Optstring_val (subv);
  const char *val = Optstring_val (valv);
  int r;

  r = aug_setm (t, base, sub, val);
  if (r == -1)
    raise_error (t, "Augeas.setm");

  CAMLreturn (Val_int (r));
}

/* val transform : t -> string -> string -> transform_mode -> unit */
CAMLprim value
ocaml_augeas_transform (value tv, value lensv, value filev, value modev)
{
  CAMLparam4 (tv, lensv, filev, modev);
  augeas_t t = Augeas_t_val (tv);
  const char *lens = String_val (lensv);
  const char *file = String_val (filev);
  const int excl = Int_val (modev) == 1 ? 1 : 0;

  if (aug_transform (t, lens, file, excl) == -1)
    raise_error (t, "Augeas.transform");

  CAMLreturn (Val_unit);
}

/* val source : t -> path -> path option */
CAMLprim value
ocaml_augeas_source (value tv, value pathv)
{
#ifdef HAVE_AUG_SOURCE
  CAMLparam2 (tv, pathv);
  CAMLlocal2 (optv, v);
  augeas_t t = Augeas_t_val (tv);
  const char *path = String_val (pathv);
  char *file_path;
  int r;

  r = aug_source (t, path, &file_path);
  if (r == 0) {
    if (file_path) {	/* Return Some file_path */
      v = caml_copy_string (file_path);
      optv = caml_alloc (1, 0);
      Field (optv, 0) = v;
      free (file_path);
    } else		/* Return None */
      optv = Val_int (0);
  }
  else			/* Error */
    raise_error (t, "Augeas.source");

  CAMLreturn (optv);
#else
  caml_failwith ("Augeas.source: function not implemented");
#endif
}
