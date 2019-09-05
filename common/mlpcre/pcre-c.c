/* Bindings for Perl-compatible Regular Expressions.
 * Copyright (C) 2017 Red Hat Inc.
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

#include <pcre.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include "cleanups.h"

#include "glthread/tls.h"

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

/* Data on the most recent match is stored in this thread-local
 * variable.  It is freed either by the next call to PCRE.matches or
 * by (clean) thread exit.
 */
static gl_tls_key_t last_match;

struct last_match {
  char *subject;                /* subject string */
  int *vec;                     /* vector containing match offsets */
  int r;                        /* value returned by pcre_exec */
};

static void
free_last_match (struct last_match *data)
{
  if (data) {
    free (data->subject);
    free (data->vec);
    free (data);
  }
}

static void init (void) __attribute__((constructor));

static void
init (void)
{
  gl_tls_key_init (last_match, (void (*) (void *))free_last_match);
}

/* Raises PCRE.error (msg, errcode). */
static void
raise_pcre_error (const char *msg, int errcode)
{
  value args[2];

  args[0] = caml_copy_string (msg);
  args[1] = Val_int (errcode);
  caml_raise_with_args (*caml_named_value ("PCRE.Error"), 2, args);
}

/* Wrap and unwrap pcre regular expression handles, with a finalizer. */
#define Regexp_val(rv) (*(pcre **)Data_custom_val(rv))

static void
regexp_finalize (value rev)
{
  pcre *re = Regexp_val (rev);
  if (re) pcre_free (re);
}

static struct custom_operations custom_operations = {
  (char *) "pcre_custom_operations",
  regexp_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
};

static value
Val_regexp (pcre *re)
{
  CAMLparam0 ();
  CAMLlocal1 (rv);

  rv = caml_alloc_custom (&custom_operations, sizeof (pcre *), 0, 1);
  Regexp_val (rv) = re;

  CAMLreturn (rv);
}

static int
is_Some_true (value v)
{
  return
    v != Val_int (0) /* !None */ &&
    Bool_val (Field (v, 0)) /* Some true */;
}

value
guestfs_int_pcre_compile (value anchoredv, value caselessv, value dotallv,
                          value extendedv, value multilinev,
                          value pattv)
{
  CAMLparam5 (anchoredv, caselessv, dotallv, extendedv, multilinev);
  CAMLxparam1 (pattv);
  int options = 0;
  pcre *re;
  int errcode = 0;
  const char *err;
  int offset;

  /* Flag parameters are all ‘bool option’, defaulting to false. */
  if (is_Some_true (anchoredv))
    options |= PCRE_ANCHORED;
  if (is_Some_true (caselessv))
    options |= PCRE_CASELESS;
  if (is_Some_true (dotallv))
    options |= PCRE_DOTALL;
  if (is_Some_true (extendedv))
    options |= PCRE_EXTENDED;
  if (is_Some_true (multilinev))
    options |= PCRE_MULTILINE;

  re = pcre_compile2 (String_val (pattv), options,
                      &errcode, &err, &offset, NULL);
  if (re == NULL)
    raise_pcre_error (err, errcode);

  CAMLreturn (Val_regexp (re));
}

/* OCaml calls C functions from bytecode a bit differently when they
 * have more than 5 parameters.
 */
value
guestfs_int_pcre_compile_byte (value *argv, int argn)
{
  return guestfs_int_pcre_compile (argv[0], argv[1], argv[2], argv[3], argv[4],
                                   argv[5]);
}

value
guestfs_int_pcre_matches (value rev, value strv)
{
  CAMLparam2 (rev, strv);
  pcre *re = Regexp_val (rev);
  struct last_match *m, *oldm;
  size_t len = caml_string_length (strv);
  int capcount, r;
  int veclen;

  /* Calculate maximum number of substrings, and hence the vector
   * length required.
   */
  r = pcre_fullinfo (re, NULL, PCRE_INFO_CAPTURECOUNT, (int *) &capcount);
  /* I believe that errors should never occur because of OCaml
   * type safety, so we should abort here.  If this ever happens
   * we will need to look at it again.
   */
  assert (r == 0);
  veclen = 3 * (1 + capcount);

  m = calloc (1, sizeof *m);
  if (m == NULL)
    caml_raise_out_of_memory ();

  /* We will need the original subject string when fetching
   * substrings, so take a copy.
   */
  m->subject = malloc (len+1);
  if (m->subject == NULL) {
    free_last_match (m);
    caml_raise_out_of_memory ();
  }
  memcpy (m->subject, String_val (strv), len+1);

  m->vec = malloc (veclen * sizeof (int));
  if (m->vec == NULL) {
    free_last_match (m);
    caml_raise_out_of_memory ();
  }

  m->r = pcre_exec (re, NULL, m->subject, len, 0, 0, m->vec, veclen);
  if (m->r < 0 && m->r != PCRE_ERROR_NOMATCH) {
    int ret = m->r;
    free_last_match (m);
    raise_pcre_error ("pcre_exec", ret);
  }

  /* This error would indicate that pcre_exec ran out of space in the
   * vector.  However if we are calculating the size of the vector
   * correctly above, then this should never happen.
   */
  assert (m->r != 0);

  r = m->r != PCRE_ERROR_NOMATCH;

  /* Replace the old TLS match data, but only if we're going
   * to return a match.
   */
  if (r) {
    oldm = gl_tls_get (last_match);
    free_last_match (oldm);
    gl_tls_set (last_match, m);
  }
  else
    free_last_match (m);

  CAMLreturn (r ? Val_true : Val_false);
}

value
guestfs_int_pcre_sub (value nv)
{
  CAMLparam1 (nv);
  const int n = Int_val (nv);
  CAMLlocal1 (strv);
  int len;
  CLEANUP_FREE char *str = NULL;
  const struct last_match *m = gl_tls_get (last_match);

  if (m == NULL)
    raise_pcre_error ("PCRE.sub called without calling PCRE.matches", 0);

  if (n < 0)
    caml_invalid_argument ("PCRE.sub: n must be >= 0");

  len = pcre_get_substring (m->subject, m->vec, m->r, n, (const char **) &str);

  if (len == PCRE_ERROR_NOSUBSTRING)
    caml_raise_not_found ();

  if (len < 0)
    raise_pcre_error ("pcre_get_substring", len);

  strv = caml_alloc_string (len);
  memcpy (String_val (strv), str, len);
  CAMLreturn (strv);
}

value
guestfs_int_pcre_subi (value nv)
{
  CAMLparam1 (nv);
  const int n = Int_val (nv);
  CAMLlocal1 (rv);
  const struct last_match *m = gl_tls_get (last_match);

  if (m == NULL)
    raise_pcre_error ("PCRE.subi called without calling PCRE.matches", 0);

  if (n < 0)
    caml_invalid_argument ("PCRE.subi: n must be >= 0");

  /* eg if there are 2 captures, m->r == 3, and valid values of n are
   * 0, 1 or 2.
   */
  if (n >= m->r)
    caml_raise_not_found ();

  rv = caml_alloc (2, 0);
  Store_field (rv, 0, Val_int (m->vec[n*2]));
  Store_field (rv, 1, Val_int (m->vec[n*2+1]));

  CAMLreturn (rv);
}
