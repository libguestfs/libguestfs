(* Windows Registry reverse-engineering tool.
 * Copyright (C) 2010 Red Hat Inc.
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
 *
 * For existing information on the registry format, please refer
 * to the following documents.  Note they are both incomplete
 * and inaccurate in some respects.
 *)

(* Convert an NT file timestamp to time_t.  See:
 * http://blogs.msdn.com/oldnewthing/archive/2003/09/05/54806.aspx
 * http://support.microsoft.com/kb/167296
 *)
let nt_to_time_t t =
  let t = Int64.sub t 116444736000000000L in
  let t = Int64.div t 10000000L in
  Int64.to_float t
