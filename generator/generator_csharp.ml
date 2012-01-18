(* libguestfs
 * Copyright (C) 2009-2012 Red Hat Inc.
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

open Printf

open Generator_types
open Generator_utils
open Generator_pr
open Generator_docstrings
open Generator_optgroups
open Generator_actions
open Generator_structs

let rec generate_csharp () =
  generate_header CPlusPlusStyle LGPLv2plus;

  (* XXX Make this configurable by the C# assembly users. *)
  let library = "libguestfs.so.0" in

  pr "\
// These C# bindings are highly experimental at present.
//
// Firstly they only work on Linux (ie. Mono).  In order to get them
// to work on Windows (ie. .Net) you would need to port the library
// itself to Windows first.
//
// The second issue is that some calls are known to be incorrect and
// can cause Mono to segfault.  Particularly: calls which pass or
// return string[], or return any structure value.  This is because
// we haven't worked out the correct way to do this from C#.  Also
// we don't handle functions that take optional arguments at all.
//
// The third issue is that when compiling you get a lot of warnings.
// We are not sure whether the warnings are important or not.
//
// Fourthly we do not routinely build or test these bindings as part
// of the make && make check cycle, which means that regressions might
// go unnoticed.
//
// Suggestions and patches are welcome.

// To compile:
//
// gmcs Libguestfs.cs
// mono Libguestfs.exe
//
// (You'll probably want to add a Test class / static main function
// otherwise this won't do anything useful).

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Collections;

namespace Guestfs
{
  class Error : System.ApplicationException
  {
    public Error (string message) : base (message) {}
    protected Error (SerializationInfo info, StreamingContext context) {}
  }

  class Guestfs
  {
    IntPtr _handle;

    [DllImport (\"%s\")]
    static extern IntPtr guestfs_create ();

    public Guestfs ()
    {
      _handle = guestfs_create ();
      if (_handle == IntPtr.Zero)
        throw new Error (\"could not create guestfs handle\");
    }

    [DllImport (\"%s\")]
    static extern void guestfs_close (IntPtr h);

    ~Guestfs ()
    {
      guestfs_close (_handle);
    }

    [DllImport (\"%s\")]
    static extern string guestfs_last_error (IntPtr h);

" library library library;

  (* Generate C# structure bindings.  We prefix struct names with
   * underscore because C# cannot have conflicting struct names and
   * method names (eg. "class stat" and "stat").
   *)
  List.iter (
    fun (typ, cols) ->
      pr "    [StructLayout (LayoutKind.Sequential)]\n";
      pr "    public class _%s {\n" typ;
      List.iter (
        function
        | name, FChar -> pr "      char %s;\n" name
        | name, FString -> pr "      string %s;\n" name
        | name, FBuffer ->
            pr "      uint %s_len;\n" name;
            pr "      string %s;\n" name
        | name, FUUID ->
            pr "      [MarshalAs (UnmanagedType.ByValTStr, SizeConst=16)]\n";
            pr "      string %s;\n" name
        | name, FUInt32 -> pr "      uint %s;\n" name
        | name, FInt32 -> pr "      int %s;\n" name
        | name, (FUInt64|FBytes) -> pr "      ulong %s;\n" name
        | name, FInt64 -> pr "      long %s;\n" name
        | name, FOptPercent -> pr "      float %s; /* [0..100] or -1 */\n" name
      ) cols;
      pr "    }\n";
      pr "\n"
  ) structs;

  (* Generate C# function bindings. *)
  List.iter (
    fun (name, (ret, args, optargs), _, _, _, shortdesc, _) ->
      let rec csharp_return_type () =
        match ret with
        | RErr -> "void"
        | RBool n -> "bool"
        | RInt n -> "int"
        | RInt64 n -> "long"
        | RConstString n
        | RConstOptString n
        | RString n
        | RBufferOut n -> "string"
        | RStruct (_,n) -> "_" ^ n
        | RHashtable n -> "Hashtable"
        | RStringList n -> "string[]"
        | RStructList (_,n) -> sprintf "_%s[]" n

      and c_return_type () =
        match ret with
        | RErr
        | RBool _
        | RInt _ -> "int"
        | RInt64 _ -> "long"
        | RConstString _
        | RConstOptString _
        | RString _
        | RBufferOut _ -> "string"
        | RStruct (_,n) -> "_" ^ n
        | RHashtable _
        | RStringList _ -> "string[]"
        | RStructList (_,n) -> sprintf "_%s[]" n

      and c_error_comparison () =
        match ret with
        | RErr
        | RBool _
        | RInt _
        | RInt64 _ -> "== -1"
        | RConstString _
        | RConstOptString _
        | RString _
        | RBufferOut _
        | RStruct (_,_)
        | RHashtable _
        | RStringList _
        | RStructList (_,_) -> "== null"

      and generate_extern_prototype () =
        pr "    static extern %s guestfs_%s (IntPtr h"
          (c_return_type ()) name;
        List.iter (
          function
          | Pathname n | Device n | Dev_or_Path n | String n | OptString n
          | FileIn n | FileOut n
          | Key n
          | BufferIn n ->
              pr ", [In] string %s" n
          | StringList n | DeviceList n ->
              pr ", [In] string[] %s" n
          | Bool n ->
              pr ", bool %s" n
          | Int n ->
              pr ", int %s" n
          | Int64 n | Pointer (_, n) ->
              pr ", long %s" n
        ) args;
        pr ");\n"

      and generate_public_prototype () =
        pr "    public %s %s (" (csharp_return_type ()) name;
        let comma = ref false in
        let next () =
          if !comma then pr ", ";
          comma := true
        in
        List.iter (
          function
          | Pathname n | Device n | Dev_or_Path n | String n | OptString n
          | FileIn n | FileOut n
          | Key n
          | BufferIn n ->
              next (); pr "string %s" n
          | StringList n | DeviceList n ->
              next (); pr "string[] %s" n
          | Bool n ->
              next (); pr "bool %s" n
          | Int n ->
              next (); pr "int %s" n
          | Int64 n | Pointer (_, n) ->
              next (); pr "long %s" n
        ) args;
        pr ")\n"

      and generate_call () =
        pr "guestfs_%s (_handle" name;
        List.iter (fun arg -> pr ", %s" (name_of_argt arg)) args;
        pr ");\n";
      in

      pr "    [DllImport (\"%s\")]\n" library;
      generate_extern_prototype ();
      pr "\n";
      pr "    /// <summary>\n";
      pr "    /// %s\n" shortdesc;
      pr "    /// </summary>\n";
      generate_public_prototype ();
      pr "    {\n";
      pr "      %s r;\n" (c_return_type ());
      pr "      r = ";
      generate_call ();
      pr "      if (r %s)\n" (c_error_comparison ());
      pr "        throw new Error (guestfs_last_error (_handle));\n";
      (match ret with
       | RErr -> ()
       | RBool _ ->
           pr "      return r != 0 ? true : false;\n"
       | RHashtable _ ->
           pr "      Hashtable rr = new Hashtable ();\n";
           pr "      for (size_t i = 0; i < r.Length; i += 2)\n";
           pr "        rr.Add (r[i], r[i+1]);\n";
           pr "      return rr;\n"
       | RInt _ | RInt64 _ | RConstString _ | RConstOptString _
       | RString _ | RBufferOut _ | RStruct _ | RStringList _
       | RStructList _ ->
           pr "      return r;\n"
      );
      pr "    }\n";
      pr "\n";
  ) all_functions_sorted;

  pr "  }
}
"
