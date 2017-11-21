(* Read /dev/urandom.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

(* Read and return N bytes (only) from /dev/urandom.
 *
 * As pointed out by Edwin Török, previous versions of this had a big
 * problem.  They used the OCaml buffered I/O library which would read
 * a lot more data than requested.  This version uses unbuffered I/O
 * from the Unix module.
 *)

open Unix

open Std_utils

let read_byte fd =
  let b = Bytes.make 1 ' ' in
  fun () ->
    if read fd b 0 1 = 0 then (
      raise End_of_file
    );
    Char.code (Bytes.unsafe_get b 0)

let urandom_bytes n =
  assert (n > 0);
  let ret = Bytes.make n ' ' in
  with_openfile "/dev/urandom" [O_RDONLY; O_CLOEXEC] 0 (
    fun fd ->
      for i = 0 to n-1 do
        Bytes.unsafe_set ret i (Char.chr (read_byte fd ()))
      done
  );
  Bytes.to_string ret

(* Return a random number uniformly distributed in [0, upper_bound)
 * avoiding modulo bias.
 *)
let rec uniform_random read upper_bound =
  let c = read () in
  if c >= 256 mod upper_bound then c mod upper_bound
  else uniform_random read upper_bound

let urandom_uniform n chars =
  assert (n > 0);
  let nr_chars = String.length chars in
  assert (nr_chars > 0);

  let ret = Bytes.make n ' ' in
  with_openfile "/dev/urandom" [O_RDONLY; O_CLOEXEC] 0 (
    fun fd ->
      for i = 0 to n-1 do
        Bytes.unsafe_set ret i
                         (chars.[uniform_random (read_byte fd) nr_chars])
      done
  );
  Bytes.to_string ret
