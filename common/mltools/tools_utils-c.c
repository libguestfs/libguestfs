/* libguestfs OCaml tools common code
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
#include <unistd.h>
#include <errno.h>
#include <error.h>
#include <time.h>
#include <string.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>

#include <guestfs.h>

#include "options.h"

extern value guestfs_int_mllib_inspect_decrypt (value gv, value gpv, value keysv);
extern value guestfs_int_mllib_set_echo_keys (value unitv);
extern value guestfs_int_mllib_set_keys_from_stdin (value unitv);
extern value guestfs_int_mllib_rfc3339_date_time_string (value unitv);

/* Interface with the guestfish inspection and decryption code. */
int echo_keys = 0;
int keys_from_stdin = 0;

value
guestfs_int_mllib_inspect_decrypt (value gv, value gpv, value keysv)
{
  CAMLparam3 (gv, gpv, keysv);
  CAMLlocal2 (elemv, v);
  guestfs_h *g = (guestfs_h *) (intptr_t) Int64_val (gpv);
  struct key_store *ks = NULL;

  while (keysv != Val_emptylist) {
    struct key_store_key key;

    elemv = Field (keysv, 0);
    key.id = strdup (String_val (Field (elemv, 0)));
    if (!key.id)
      caml_raise_out_of_memory ();

    v = Field (elemv, 1);
    switch (Tag_val (v)) {
    case 0:  /* KeyString of string */
      key.type = key_string;
      key.string.s = strdup (String_val (Field (v, 0)));
      if (!key.string.s)
        caml_raise_out_of_memory ();
      break;
    case 1:  /* KeyFileName of string */
      key.type = key_file;
      key.file.name = strdup (String_val (Field (v, 0)));
      if (!key.file.name)
        caml_raise_out_of_memory ();
      break;
    default:
      error (EXIT_FAILURE, 0,
             "internal error: unhandled Tag_val (v) = %d",
             Tag_val (v));
    }

    ks = key_store_import_key (ks, &key);

    keysv = Field (keysv, 1);
  }

  inspect_do_decrypt (g, ks);

  CAMLreturn (Val_unit);
}

/* NB: This is a "noalloc" call. */
value
guestfs_int_mllib_set_echo_keys (value unitv)
{
  echo_keys = 1;
  return Val_unit;
}

/* NB: This is a "noalloc" call. */
value
guestfs_int_mllib_set_keys_from_stdin (value unitv)
{
  keys_from_stdin = 1;
  return Val_unit;
}

value
guestfs_int_mllib_rfc3339_date_time_string (value unitv)
{
  CAMLparam1 (unitv);
  char buf[64];
  struct timespec ts;
  struct tm tm;
  size_t ret;
  size_t total = 0;

  if (clock_gettime (CLOCK_REALTIME, &ts) == -1)
    unix_error (errno, (char *) "clock_gettime", Val_unit);

  if (localtime_r (&ts.tv_sec, &tm) == NULL)
    unix_error (errno, (char *) "localtime_r", caml_copy_int64 (ts.tv_sec));

  /* Sadly strftime does not support nanoseconds, so what we do is:
   * - stringify everything before the nanoseconds
   * - print the nanoseconds
   * - stringify the rest (i.e. the timezone)
   * then place ':' between the hours, and the minutes of the
   * timezone offset.
   */

  ret = strftime (buf, sizeof (buf), "%Y-%m-%dT%H:%M:%S.", &tm);
  if (ret == 0)
    unix_error (errno, (char *) "strftime", Val_unit);
  total += ret;

  ret = snprintf (buf + total, sizeof (buf) - total, "%09ld", ts.tv_nsec);
  if (ret == 0)
    unix_error (errno, (char *) "sprintf", caml_copy_int64 (ts.tv_nsec));
  total += ret;

  ret = strftime (buf + total, sizeof (buf) - total, "%z", &tm);
  if (ret == 0)
    unix_error (errno, (char *) "strftime", Val_unit);
  total += ret;

  /* Move the timezone minutes one character to the right, moving the
   * null character too.
   */
  memmove (buf + total - 1, buf + total - 2, 3);
  buf[total - 2] = ':';

  CAMLreturn (caml_copy_string (buf));
}
