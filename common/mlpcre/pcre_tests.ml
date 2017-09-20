(* Test bindings for Perl-compatible Regular Expressions.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

open Printf

let compile patt =
  eprintf "PCRE.compile %s\n%!" patt;
  PCRE.compile patt

let matches re str =
  eprintf "PCRE.matches %s ->%!" str;
  let r = PCRE.matches re str in
  eprintf " %b\n%!" r;
  r

let sub i =
  eprintf "PCRE.sub %d ->%!" i;
  let r = PCRE.sub i in
  eprintf " %s\n%!" r;
  r

let () =
  try
    let re0 = compile "a+b" in
    let re1 = compile "(a+)b" in
    let re2 = compile "(a+)(b*)" in

    assert (matches re0 "ccaaabbbb" = true);
    assert (sub 0 = "aaab");

    assert (matches re0 "aaa" = false);

    assert (matches re0 "xyz" = false);

    assert (matches re0 "aaabc" = true);
    assert (sub 0 = "aaab");

    assert (matches re1 "ccaaabb" = true);
    assert (sub 1 = "aaa");
    assert (sub 0 = "aaab");

    assert (matches re2 "ccabbc" = true);
    assert (sub 1 = "a");
    assert (sub 2 = "bb");
    assert (sub 0 = "abb");

    assert (matches re2 "ccac" = true);
    assert (sub 1 = "a");
    assert (sub 2 = "");
    assert (sub 0 = "a")
  with
  | Not_found ->
     failwith "one of the PCRE.sub functions unexpectedly raised Not_found"
  | PCRE.Error (msg, code) ->
     failwith (sprintf "PCRE error: %s (PCRE error code %d)" msg code)

(* Run some out of range [sub] calls to ensure an exception is thrown. *)
let () =
  let re2 = compile "(a+)(b*)" in
  ignore (matches re2 "ccac");
  (try ignore (sub 3) with Not_found -> ());
  (try ignore (sub (-1)) with Invalid_argument _ -> ())

(* Compile some bad regexps and check that an exception is thrown.
 * It would be nice to check the error message is right but
 * that involves dealing with language and future changes of
 * PCRE error codes.
 *)
let () =
  List.iter (
    fun patt ->
      let msg, code =
        try ignore (PCRE.compile patt); assert false
        with PCRE.Error (m, c) -> m, c in
      eprintf "patt: %s -> exception: %s (%d)\n%!" patt msg code
  ) [ "("; ")"; "+"; "*"; "(abc" ]

let () = Gc.compact ()
