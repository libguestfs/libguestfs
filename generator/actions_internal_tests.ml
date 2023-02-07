(* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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
 *)

(* Please read generator/README first. *)

open Types

(* These test functions are used in the language binding tests. *)

let test_all_args = [
  String (PlainString, "str");
  OptString "optstr";
  StringList (PlainString, "strlist");
  Bool "b";
  Int "integer";
  Int64 "integer64";
  String (FileIn, "filein");
  String (FileOut, "fileout");
  BufferIn "bufferin";
]

let test_all_optargs = [
  OBool "obool";
  OInt "oint";
  OInt64 "oint64";
  OString "ostring";
  OStringList "ostringlist";
]

let test_all_rets = [
  (* except for RErr, which is tested thoroughly elsewhere *)
  "internal_test_rint",         RInt "valout";
  "internal_test_rint64",       RInt64 "valout";
  "internal_test_rbool",        RBool "valout";
  "internal_test_rconststring", RConstString "valout";
  "internal_test_rconstoptstring", RConstOptString "valout";
  "internal_test_rstring",      RString (RPlainString, "valout");
  "internal_test_rstringlist",  RStringList (RPlainString, "valout");
  "internal_test_rstruct",      RStruct ("valout", "lvm_pv");
  "internal_test_rstructlist",  RStructList ("valout", "lvm_pv");
  "internal_test_rhashtable",   RHashtable (RPlainString, RPlainString, "valout");
  "internal_test_rbufferout",   RBufferOut "valout";
]

let test_functions = [
  { defaults with
    name = "internal_test";
    style = RErr, test_all_args, test_all_optargs;
    visibility = VBindTest; cancellable = true;
    blocking = false;
    shortdesc = "internal test function - do not use";
    longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
parameter type correctly.

It echos the contents of each parameter to stdout (by default)
or to a file (if C<guestfs_internal_test_set_output> was called).

You probably don't want to call this function." };

  { defaults with
    name = "internal_test_only_optargs";
    style = RErr, [], [OInt "test"];
    visibility = VBindTest; cancellable = true;
    blocking = false;
    shortdesc = "internal test function - do not use";
    longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle no args, some
optargs correctly.

It echos the contents of each parameter to stdout (by default)
or to a file (if C<guestfs_internal_test_set_output> was called).

You probably don't want to call this function." };

  { defaults with
    name = "internal_test_63_optargs";
    style = RErr, [], [OInt "opt1"; OInt "opt2"; OInt "opt3"; OInt "opt4"; OInt "opt5"; OInt "opt6"; OInt "opt7"; OInt "opt8"; OInt "opt9"; OInt "opt10"; OInt "opt11"; OInt "opt12"; OInt "opt13"; OInt "opt14"; OInt "opt15"; OInt "opt16"; OInt "opt17"; OInt "opt18"; OInt "opt19"; OInt "opt20"; OInt "opt21"; OInt "opt22"; OInt "opt23"; OInt "opt24"; OInt "opt25"; OInt "opt26"; OInt "opt27"; OInt "opt28"; OInt "opt29"; OInt "opt30"; OInt "opt31"; OInt "opt32"; OInt "opt33"; OInt "opt34"; OInt "opt35"; OInt "opt36"; OInt "opt37"; OInt "opt38"; OInt "opt39"; OInt "opt40"; OInt "opt41"; OInt "opt42"; OInt "opt43"; OInt "opt44"; OInt "opt45"; OInt "opt46"; OInt "opt47"; OInt "opt48"; OInt "opt49"; OInt "opt50"; OInt "opt51"; OInt "opt52"; OInt "opt53"; OInt "opt54"; OInt "opt55"; OInt "opt56"; OInt "opt57"; OInt "opt58"; OInt "opt59"; OInt "opt60"; OInt "opt61"; OInt "opt62"; OInt "opt63"];
    visibility = VBindTest; cancellable = true;
    blocking = false;
    shortdesc = "internal test function - do not use";
    longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle the full range
of 63 optargs correctly.  (Note that 63 is not an absolute limit
and it could be raised by changing the XDR protocol).

It echos the contents of each parameter to stdout (by default)
or to a file (if C<guestfs_internal_test_set_output> was called).

You probably don't want to call this function." }

] @ List.flatten (
  List.map (
    fun (name, ret) -> [
      { defaults with
        name = name;
        style = ret, [String (PlainString, "val")], [];
        visibility = VBindTest;
        blocking = false;
        shortdesc = "internal test function - do not use";
        longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
return type correctly.

It converts string C<val> to the return type.

You probably don't want to call this function." };
      { defaults with
        name = name ^ "err";
        style = ret, [], [];
        visibility = VBindTest;
        blocking = false;
        shortdesc = "internal test function - do not use";
        longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
return type correctly.

This function always returns an error.

You probably don't want to call this function." }
    ]
  ) test_all_rets
)

let test_support_functions = [
  { defaults with
    name = "internal_test_set_output";
    style = RErr, [String (PlainString, "filename")], [];
    visibility = VBindTest;
    blocking = false;
    shortdesc = "internal test function - do not use";
    longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
parameter type correctly.

It sets the output file used by C<guestfs_internal_test>.

You probably don't want to call this function." };

  { defaults with
    name = "internal_test_close_output";
    style = RErr, [], [];
    visibility = VBindTest;
    blocking = false;
    shortdesc = "internal test function - do not use";
    longdesc = "\
This is an internal test function which is used to test whether
the automatically generated bindings can handle every possible
parameter type correctly.

It closes the output file previously opened by
C<guestfs_internal_test_set_output>.

You probably don't want to call this function." };
]
