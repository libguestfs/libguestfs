/* Binding for fnmatch.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdlib.h>
#include <fnmatch.h>
#include <errno.h>

#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

/* NB: These flags must appear in the same order as fnmatch.ml */
static int flags[] = {
  FNM_NOESCAPE,
  FNM_PATHNAME,
  FNM_PERIOD,
  FNM_FILE_NAME,
  FNM_LEADING_DIR,
  FNM_CASEFOLD,
};

value
guestfs_int_mllib_fnmatch (value patternv, value strv, value flagsv)
{
  CAMLparam3 (patternv, strv, flagsv);
  int f = 0, r;

  /* Convert flags to bitmask. */
  while (flagsv != Val_int (0)) {
    f |= flags[Int_val (Field (flagsv, 0))];
    flagsv = Field (flagsv, 1);
  }

  r = fnmatch (String_val (patternv), String_val (strv), f);

  if (r == 0)
    CAMLreturn (Val_true);
  else if (r == FNM_NOMATCH)
    CAMLreturn (Val_false);
  else {
    /* XXX The fnmatch specification doesn't mention what errors can
     * be returned by fnmatch.  Assume they are errnos for now.
     */
    unix_error (errno, (char *) "fnmatch", patternv);
  }
}
