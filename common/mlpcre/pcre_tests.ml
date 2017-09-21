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

let compile ?(anchored = false) ?(caseless = false)
            ?(dotall = false) ?(extended = false) ?(multiline = false)
            patt =
  eprintf "PCRE.compile%s%s%s%s%s %s\n%!"
          (if anchored then " ~anchored:true" else "")
          (if caseless then " ~caseless:true" else "")
          (if dotall then " ~dotall:true" else "")
          (if extended then " ~extended:true" else "")
          (if multiline then " ~multiline:true" else "")
          patt;
  PCRE.compile ~anchored ~caseless ~dotall ~extended ~multiline patt

let matches re str =
  eprintf "PCRE.matches %s ->%!" str;
  let r = PCRE.matches re str in
  eprintf " %b\n%!" r;
  r

let replace ?(global = false) patt subst subj =
  eprintf "PCRE.replace global:%b <patt> %s %s ->%!" global subst subj;
  let r = PCRE.replace ~global patt subst subj in
  eprintf " %s\n%!" r;
  r

let split patt subj =
  eprintf "PCRE.split <patt> %s ->%!" subj;
  let s1, s2 = PCRE.split patt subj in
  eprintf " (%s, %s)\n%!" s1 s2;
  (s1, s2)

let nsplit ?(max = 0) patt subj =
  eprintf "PCRE.nsplit%s <patt> %s ->%!"
          (if max = 0 then "" else sprintf " ~max:%d" max)
          subj;
  let ss = PCRE.nsplit ~max patt subj in
  eprintf " [%s]\n%!" (String.concat "; " ss);
  ss

let sub i =
  eprintf "PCRE.sub %d ->%!" i;
  let r = PCRE.sub i in
  eprintf " %s\n%!" r;
  r

let subi i =
  eprintf "PCRE.subi %d ->%!" i;
  let i1, i2 = PCRE.subi i in
  eprintf " (%d, %d)\n%!" i1 i2;
  (i1, i2)

let () =
  try
    let re0 = compile "a+b" in
    let re1 = compile "(a+)b" in
    let re2 = compile "(a+)(b*)" in
    let re3 = compile ~caseless:true "[^a-z0-9_]" in
    let ws = compile "\\s+" in

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
    assert (sub 0 = "a");
    assert (subi 0 = (2, 3));
    assert (subi 1 = (2, 3));
    assert (subi 2 = (3, 3));

    assert (replace re0 "dd" "abcabcaabccca" = "ddcabcaabccca");
    assert (replace ~global:true re0 "dd" "abcabcaabccca" = "ddcddcddccca");

    (* This example copies a usage from customize/firstboot.ml
     * "\xc2\xa3" is utf-8 for the GBP sign.  Ideally PCRE would
     * recognize that this is a single character, however doing that
     * would involve passing the PCRE_UTF8 flag when compiling
     * patterns, and that could be problematic if PCRE was built
     * without Unicode support (XXX).
     *)
    assert (replace ~global:true re3 "-" "this is a\xc2\xa3FUNNY.name?"
            (* = "this-is-a-FUNNY-name-" if UTF-8 worked *)
            = "this-is-a--FUNNY-name-");

    (* This also tests PCRE.split since that is used by nsplit. *)
    assert (nsplit ~max:1 ws "a b c" = [ "a b c" ]);
    assert (nsplit ~max:2 ws "a b c" = [ "a"; "b c" ]);
    assert (nsplit ~max:3 ws "a b c" = [ "a"; "b"; "c" ]);
    assert (nsplit ~max:10 ws "a b c" = [ "a"; "b"; "c" ]);
    assert (nsplit ws "the cat sat   on \t\t  the mat." =
              [ "the"; "cat"; "sat"; "on"; "the"; "mat." ]);
    assert (nsplit ~max:5 ws "the cat sat   on \t\t  the mat." =
              [ "the"; "cat"; "sat"; "on"; "the mat." ]);
    assert (nsplit ws " the " = [ ""; "the"; "" ]);
    assert (nsplit ws "the " = [ "the"; "" ]);
    assert (nsplit ws " the" = [ ""; "the" ]);
    assert (nsplit ws "    \t  the" = [ ""; "the" ]);
  with
  | Not_found ->
     failwith "one of the PCRE.sub functions unexpectedly raised Not_found"
  | PCRE.Error (msg, code) ->
     failwith (sprintf "PCRE error: %s (PCRE error code %d)" msg code)

(* Run some out of range [sub] and [subi] calls to ensure an exception
 * is thrown.
 *)
let () =
  let re2 = compile "(a+)(b*)" in
  ignore (matches re2 "ccac");
  (try ignore (sub 3) with Not_found -> ());
  (try ignore (sub (-1)) with Invalid_argument _ -> ());
  (try ignore (subi 3) with Not_found -> ());
  (try ignore (subi (-1)) with Invalid_argument _ -> ())

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
