/* virt-resize - interface to isatty
 * Copyright (C) 2013 Red Hat Inc.
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

#include <caml/memory.h>
#include <caml/mlvalues.h>

#pragma GCC diagnostic ignored "-Wmissing-prototypes"

/* RHEL 5-era ocaml didn't have Unix.isatty.
 *
 * Note this function is marked as "noalloc" so it must not call any
 * OCaml allocation functions:
 * http://camltastic.blogspot.co.uk/2008/08/tip-calling-c-functions-directly-with.html
 */
value
virt_resize_isatty_stdout (value unitv)
{
  return isatty (1) ? Val_true : Val_false;
}
