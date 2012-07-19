/* virt-resize - interface to progress bar mini library
 * Copyright (C) 2011 Red Hat Inc.
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
#include <stdint.h>
#include <string.h>
#include <locale.h>

#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include "progress.h"

#define Bar_val(v) (*((struct progress_bar **)Data_custom_val(v)))

static void
progress_bar_finalize (value barv)
{
  struct progress_bar *bar = Bar_val (barv);

  if (bar)
    progress_bar_free (bar);
}

static struct custom_operations progress_bar_custom_operations = {
  (char *) "progress_bar_custom_operations",
  progress_bar_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

value
virt_resize_progress_bar_init (value machine_readablev)
{
  CAMLparam1 (machine_readablev);
  CAMLlocal1 (barv);
  struct progress_bar *bar;
  int machine_readable = Bool_val (machine_readablev);
  unsigned flags = 0;

  /* XXX Have to do this to get nl_langinfo to work properly.  However
   * we should really only call this from main.
   */
  setlocale (LC_ALL, "");

  if (machine_readable)
    flags |= PROGRESS_BAR_MACHINE_READABLE;
  bar = progress_bar_init (flags);
  if (bar == NULL)
    caml_raise_out_of_memory ();

  barv = caml_alloc_custom (&progress_bar_custom_operations,
                            sizeof (struct progress_bar *), 0, 1);
  Bar_val (barv) = bar;

  CAMLreturn (barv);
}

value
virt_resize_progress_bar_reset (value barv)
{
  CAMLparam1 (barv);
  struct progress_bar *bar = Bar_val (barv);

  progress_bar_reset (bar);

  CAMLreturn (Val_unit);
}

value
virt_resize_progress_bar_set (value barv,
                              value positionv, value totalv)
{
  CAMLparam3 (barv, positionv, totalv);
  struct progress_bar *bar = Bar_val (barv);
  uint64_t position = Int64_val (positionv);
  uint64_t total = Int64_val (totalv);

  progress_bar_set (bar, position, total);

  CAMLreturn (Val_unit);
}
