(* libguestfs
 * Copyright (C) 2019 Hiroyuki Katsura <hiroyuki.katsura.0513@gmail.com>
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

open Std_utils
open Types
open Utils
open Pr
open Docstrings
open Optgroups
open Actions
open Structs
open C
open Events

let copyrights = ["Hiroyuki Katsura <hiroyuki.katsura.0513@gmail.com>"]

(* Utilities for Rust *)
(* Are there corresponding functions to them? *)
(* Should they be placed in utils.ml? *)
let rec indent = function
  | x when x > 0 -> pr "    "; indent (x - 1)
  | _ -> ()

let snake2caml name =
  let l = String.nsplit "_" name in
  let l = List.map String.capitalize_ascii l in
  String.concat "" l

(* because there is a function which contains 'unsafe' field *)
let black_list = ["unsafe"]

let translate_bad_symbols s =
  if List.mem s black_list then
    s ^ "_"
  else
    s

let generate_rust () =
  generate_header ~copyrights CStyle LGPLv2plus;

  pr "
use crate::base::*;
use crate::utils::*;
use crate::error::*;
use std::collections;
use std::convert;
use std::convert::TryFrom;
use std::ffi;
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::slice;

extern \"C\" {
    fn free(buf: *const c_void);
}
";

  (* event enum *)
  pr "\n";
  pr "pub enum Event {\n";
  List.iter (
    fun (name, _) ->
      pr "    %s,\n" (snake2caml name)
  ) events;
  pr "}\n\n";

  pr "impl Event {\n";
  pr "    pub fn to_u64(&self) -> u64 {\n";
  pr "        match self {\n";
  List.iter (
    fun (name, i) ->
      pr "            Event::%s => %d,\n" (snake2caml name) i
  ) events;
  pr "        }\n";
  pr "    }\n";
  pr "    pub fn from_bitmask(bitmask: u64) -> Option<Event> {\n";
  pr "        match bitmask {\n";
  List.iter (
    fun (name, i) ->
      pr "            %d => Some(Event::%s),\n" i (snake2caml name)
  ) events;
  pr "            _ => None,\n";
  pr "        }\n";
  pr "    }\n";
  pr "}\n\n";

  pr "pub const EVENT_ALL: [Event; %d] = [\n" (List.length events);
  List.iter (
    fun (name, _) ->
      pr "    Event::%s,\n" (snake2caml name)
  ) events;
  pr "];\n";

  List.iter (
    fun { s_camel_name = name; s_name = c_name; s_cols = cols } ->
      pr "\n";
      pr "pub struct %s {\n" name;
      List.iter (
        function
        | n, FChar -> pr "    pub %s: i8,\n" n
        | n, FString -> pr "    pub %s: String,\n" n
        | n, FBuffer -> pr "    pub %s: Vec<u8>,\n" n
        | n, FUInt32 -> pr "    pub %s: u32,\n" n
        | n, FInt32 -> pr "    pub %s: i32,\n" n
        | n, (FUInt64 | FBytes) -> pr "    pub %s: u64,\n" n
        | n, FInt64 -> pr "    pub %s: i64,\n" n
        | n, FUUID -> pr "    pub %s: UUID,\n" n
        | n, FOptPercent -> pr "    pub %s: Option<f32>,\n" n
      ) cols;
      pr "}\n";
      pr "#[repr(C)]\n";
      pr "struct Raw%s {\n" name;
      List.iter (
        function
        | n, FChar -> pr "    %s: c_char,\n" n
        | n, FString -> pr "    %s: *const c_char,\n" n
        | n, FBuffer ->
          pr "    %s_len: usize,\n" n;
          pr "    %s: *const c_char,\n" n;
        | n, FUUID -> pr "    %s: [u8; 32],\n" n
        | n, FUInt32 -> pr "    %s: u32,\n" n
        | n, FInt32 -> pr "    %s: i32,\n" n
        | n, (FUInt64 | FBytes) -> pr "    %s: u64,\n" n
        | n, FInt64 -> pr "    %s: i64,\n" n
        | n, FOptPercent -> pr "    %s: f32,\n" n
      ) cols;
      pr "}\n";
      pr "\n";
      pr "impl TryFrom<*const Raw%s> for %s {\n" name name;
      pr "    type Error = Error;\n";
      pr "    fn try_from(raw: *const Raw%s) -> Result<Self, Self::Error> {\n" name;
      pr "        Ok(unsafe {\n";
      pr "            %s {\n" name;
      List.iter (
        fun x ->
          indent 4;
          match x with
          | n, FChar ->
            pr "%s: (*raw).%s as i8,\n" n n;
          | n, FString ->
            pr "%s: char_ptr_to_string((*raw).%s)?,\n" n n;
          | n, FBuffer ->
            pr "%s: slice::from_raw_parts((*raw).%s as *const u8, (*raw).%s_len).to_vec(),\n" n n n
          | n, FUUID ->
            pr "%s: UUID::new((*raw).%s),\n" n n
          | n, (FUInt32 | FInt32 | FUInt64 | FInt64 | FBytes) ->
            pr "%s: (*raw).%s,\n" n n
          | n, FOptPercent ->
            pr "%s: if (*raw).%s < 0.0 {\n" n n;
            indent 4; pr "    None\n";
            indent 4; pr "} else {\n";
            indent 4; pr "    Some((*raw).%s)\n" n;
            indent 4; pr"},\n"
      ) cols;
      pr "            }\n";
      pr "        })\n";
      pr "    }\n";
      pr "}\n"
  ) external_structs;

  (* generate free functionf of structs *)
  pr "\n";
  pr "extern \"C\" {\n";
  List.iter (
    fun {  s_camel_name = name; s_name = c_name; } ->
      pr "    #[allow(dead_code)]\n";
      pr "    fn guestfs_free_%s(v: *const Raw%s);\n" c_name name;
      pr "    #[allow(dead_code)]\n";
      pr "    fn guestfs_free_%s_list(l: *const RawList<Raw%s>);\n" c_name name;
  ) external_structs;
  pr "}\n";

  (* [Outline] There are three types for each optional structs: SOptArgs,
   * CExprSOptArgs, RawSOptArgs.
   * SOptArgs: for Rust bindings' API. This can be seen by bindings' users.
   * CExprSOptArgs: Each field has C expression(e.g. CString, *const c_char)
   * RawSOptArgs: Each field has raw pointers or integer values
   *
   * SOptArgs ---try_into()---> CExprSOptArgs ---to_raw()---> RawSOptArgs
   *
   * Note: direct translation from SOptArgs to RawSOptArgs will cause a memory
   * management problem. Using into_raw/from_raw, this problem can be avoided,
   * but it is complex to handle freeing memories manually in Rust because of
   * panic/?/etc.
   *)
  (* generate structs for optional arguments *)
  List.iter (
    fun ({ name = name; shortdesc = shortdesc;
          style = (ret, args, optargs) }) ->
      let cname = snake2caml name in
      let contains_ptr =
        List.exists (
          function
          | OString _
          | OStringList _ -> true
          | _ -> false
        )
      in
      let opt_life_parameter = if contains_ptr optargs then "<'a>" else "" in
      if optargs <> [] then (
        pr "\n";
        pr "/* Optional Structs */\n";
        pr "#[derive(Default)]\n";
        pr "pub struct %sOptArgs%s {\n" cname opt_life_parameter;
        List.iter (
          fun optarg ->
            let n = translate_bad_symbols (name_of_optargt optarg) in
            match optarg with
            | OBool _ ->
              pr "    pub %s: Option<bool>,\n" n
            | OInt _ ->
              pr "    pub %s: Option<i32>,\n" n
            | OInt64 _ ->
              pr "    pub %s: Option<i64>,\n" n
            | OString _ ->
              pr "    pub %s: Option<&'a str>,\n" n
            | OStringList _ ->
              pr "    pub %s: Option<&'a [&'a str]>,\n" n
        ) optargs;
        pr "}\n\n";

        pr "struct CExpr%sOptArgs {\n" cname;
        List.iter (
          fun optarg ->
            let n = translate_bad_symbols (name_of_optargt optarg) in
            match optarg with
            | OBool _ | OInt _ ->
              pr "    %s: Option<c_int>,\n" n
            | OInt64 _ ->
              pr "    %s: Option<i64>,\n" n
            | OString _ ->
              pr "    %s: Option<ffi::CString>,\n" n
            | OStringList _ ->
              (* buffers and their pointer vector *)
              pr "    %s: Option<(Vec<ffi::CString>, Vec<*const c_char>)>,\n" n
        ) optargs;
        pr "}\n\n";

        pr "impl%s TryFrom<%sOptArgs%s> for CExpr%sOptArgs {\n"
          opt_life_parameter cname opt_life_parameter cname;
        pr "    type Error = Error;\n";
        pr "    fn try_from(optargs: %sOptArgs%s) -> Result<Self, Self::Error> {\n" cname opt_life_parameter;
        pr "        Ok(CExpr%sOptArgs {\n" cname;
        List.iteri (
          fun index optarg ->
            let n = translate_bad_symbols (name_of_optargt optarg) in
            match optarg with
            | OBool _ ->
              pr "        %s: optargs.%s.map(|b| if b { 1 } else { 0 }),\n" n n;
            | OInt _ | OInt64 _  ->
              pr "        %s: optargs.%s, \n" n n;
            | OString _ ->
              pr "        %s: optargs.%s.map(|v| ffi::CString::new(v)).transpose()?,\n" n n;
            | OStringList _ ->
              pr "        %s: optargs.%s.map(\n" n n;
              pr "                |v| Ok::<_, Error>({\n";
              pr "                         let v = arg_string_list(v)?;\n";
              pr "                         let mut w = (&v).into_iter()\n";
              pr "                                         .map(|v| v.as_ptr())\n";
              pr "                                         .collect::<Vec<_>>();\n";
              pr "                         w.push(ptr::null());\n";
              pr "                         (v, w)\n";
              pr "                    })\n";
              pr "                ).transpose()?,\n";
        ) optargs;
        pr "         })\n";
        pr "    }\n";
        pr "}\n";

        (* raw struct for C bindings *)
        pr "#[repr(C)]\n";
        pr "struct Raw%sOptArgs {\n" cname;
        pr "    bitmask: u64,\n";
        List.iter (
          fun optarg ->
            let n = translate_bad_symbols (name_of_optargt optarg) in
            match optarg with
            | OBool _ ->
              pr "    %s: c_int,\n" n
            | OInt _ ->
              pr "    %s: c_int,\n" n
            | OInt64 _ ->
              pr "    %s: i64,\n" n
            | OString _ ->
              pr "    %s: *const c_char,\n" n
            | OStringList _ ->
              pr "    %s: *const *const c_char,\n" n
        ) optargs;
        pr "}\n\n";

        pr "impl convert::From<&CExpr%sOptArgs> for Raw%sOptArgs {\n"
          cname cname;
        pr "    fn from(optargs: &CExpr%sOptArgs) -> Self {\n" cname;
        pr "        let mut bitmask = 0;\n";
        pr "        Raw%sOptArgs {\n" cname;
        List.iteri (
          fun index optarg ->
            let n = translate_bad_symbols (name_of_optargt optarg) in
            match optarg with
            | OBool _ | OInt _ | OInt64 _  ->
              pr "        %s: if let Some(v) = optargs.%s {\n" n n;
              pr "            bitmask |= 1 << %d;\n" index;
              pr "            v\n";
              pr "        } else {\n";
              pr "            0\n";
              pr "        },\n";
            | OString _ ->
              pr "        %s: if let Some(ref v) = optargs.%s {\n" n n;
              pr "            bitmask |= 1 << %d;\n" index;
              pr "            v.as_ptr()\n";
              pr "        } else {\n";
              pr "            ptr::null()\n";
              pr "        },\n";
            | OStringList _ ->
              pr "        %s: if let Some((_, ref v)) = optargs.%s {\n" n n;
              pr "            bitmask |= 1 << %d;\n" index;
              pr "            v.as_ptr()\n";
              pr "        } else {\n";
              pr "            ptr::null()\n";
              pr "        },\n";
        ) optargs;
        pr "              bitmask,\n";
        pr "         }\n";
        pr "    }\n";
        pr "}\n";
      );
  ) (actions |> external_functions |> sort);

  (* extern C APIs *)
  pr "extern \"C\" {\n";
  List.iter (
    fun ({ name = name; shortdesc = shortdesc;
          style = (ret, args, optargs) } as f) ->
      let cname = snake2caml name in
      pr "    #[allow(non_snake_case)]\n";
      pr "    fn %s(g: *const guestfs_h" f.c_function;
      List.iter (
        fun arg ->
          pr ", ";
          match arg with
          | Bool n -> pr "%s: c_int" n
          | String (_, n) -> pr "%s: *const c_char" n
          | OptString n -> pr "%s: *const c_char" n
          | Int n -> pr "%s: c_int" n
          | Int64 n -> pr "%s: i64" n
          | Pointer (_, n) -> pr "%s: *const ffi::c_void" n
          | StringList (_, n) -> pr "%s: *const *const c_char" n
          | BufferIn n -> pr "%s: *const c_char, %s_len: usize" n n
      ) args;
      (match ret with
       | RBufferOut _ -> pr ", size: *const usize"
       | _ -> ()
      );
      if optargs <> [] then
        pr ", optarg: *const Raw%sOptArgs" cname;

      pr ") -> ";

      (match ret with
      | RErr | RInt _ | RBool _ -> pr "c_int"
      | RInt64 _ -> pr "i64"
      | RConstString _ | RString _ | RConstOptString _  -> pr "*const c_char"
      | RBufferOut _ -> pr "*const u8"
      | RStringList _ | RHashtable _-> pr "*const *const c_char"
      | RStruct (_, n) ->
        let n = camel_name_of_struct n in
        pr "*const Raw%s" n
      | RStructList (_, n) ->
        let n = camel_name_of_struct n in
        pr "*const RawList<Raw%s>" n
      );
      pr ";\n";

  ) (actions |> external_functions |> sort);
  pr "}\n";


  pr "impl<'a> Handle<'a> {\n";
  List.iter (
    fun ({ name = name; shortdesc = shortdesc; longdesc = longdesc;
          style = (ret, args, optargs) } as f) ->
      let cname = snake2caml name in
      pr "    /// %s\n" shortdesc;
      pr "    #[allow(non_snake_case)]\n";
      pr "    pub fn %s" name;

      (* generate arguments *)
      pr "(&self, ";

      let comma = ref false in
      List.iter (
        fun arg ->
          if !comma then pr ", ";
          comma := true;
          match arg with
          | Bool n -> pr "%s: bool" n
          | Int n -> pr "%s: i32" n
          | Int64 n -> pr "%s: i64" n
          | String (_, n) -> pr "%s: &str" n
          | OptString n -> pr "%s: Option<&str>" n
          | StringList (_, n) -> pr "%s: &[&str]" n
          | BufferIn n -> pr "%s: &[u8]" n
          | Pointer (_, n) -> pr "%s: *mut c_void" n
      ) args;
      if optargs <> [] then (
        if !comma then pr ", ";
        comma := true;
        pr "optargs: %sOptArgs" cname
      );
      pr ")";

      (* generate return type *)
      pr " -> Result<";
      (match ret with
      | RErr -> pr "()"
      | RInt _ -> pr "i32"
      | RInt64 _ -> pr "i64"
      | RBool _ -> pr "bool"
      | RConstString _ -> pr "&'static str"
      | RString _ -> pr "String"
      | RConstOptString _ -> pr "Option<&'static str>"
      | RStringList _ -> pr "Vec<String>"
      | RStruct (_, sn) ->
        let sn = camel_name_of_struct sn in
        pr "%s" sn
      | RStructList (_, sn) ->
        let sn = camel_name_of_struct sn in
        pr "Vec<%s>" sn
      | RHashtable _ -> pr "collections::HashMap<String, String>"
      | RBufferOut _ -> pr "Vec<u8>");
      pr ", Error> {\n";


      let _pr = pr in
      let pr fs = indent 2; pr fs in
      List.iter (
        function
        | Bool n ->
          pr "let %s = if %s { 1 } else { 0 };\n" n n
        | String (_, n) ->
          pr "let c_%s = ffi::CString::new(%s)?;\n" n n;
        | OptString n ->
          pr "let c_%s = %s.map(|s| ffi::CString::new(s)).transpose()?;\n" n n;
        | StringList (_, n) ->
          pr "let c_%s_v = arg_string_list(%s)?;\n" n n;
          pr "let mut c_%s = (&c_%s_v).into_iter().map(|v| v.as_ptr()).collect::<Vec<_>>();\n" n n;
          pr "c_%s.push(ptr::null());\n" n;
        | BufferIn n ->
          pr "let c_%s_len = %s.len();\n" n n;
          pr "let c_%s = unsafe { ffi::CString::from_vec_unchecked(%s.to_vec())};\n" n n;
        | Int _ | Int64 _ | Pointer _ -> ()
      ) args;

      (match ret with
       | RBufferOut _ ->
         pr "let mut size = 0usize;\n"
       | _ -> ()
      );

      if optargs <> [] then (
        pr "let optargs_cexpr = CExpr%sOptArgs::try_from(optargs)?;\n" cname;
      );

      pr "\n";

      pr "let r = unsafe { %s(self.g" f.c_function;
      let pr = _pr in
      List.iter (
        fun arg ->
          pr ", ";
          match arg with
          | String (_, n)  -> pr "(&c_%s).as_ptr()" n
          | OptString n -> pr "match &c_%s { Some(ref s) => s.as_ptr(), None => ptr::null() }\n" n
          | StringList (_, n) -> pr "(&c_%s).as_ptr() as *const *const c_char" n
          | Bool n | Int n | Int64 n | Pointer (_, n) -> pr "%s" n
          | BufferIn n -> pr "(&c_%s).as_ptr(), c_%s_len" n n
      ) args;
      (match ret with
       | RBufferOut _ -> pr ", &mut size as *mut usize"
       | _ -> ()
      );
      if optargs <> [] then (
        pr ", &(Raw%sOptArgs::from(&optargs_cexpr)) as *const Raw%sOptArgs"
          cname cname;
      );
      pr ") };\n";

      let _pr = pr in
      let pr fs = indent 2; pr fs in
      (match errcode_of_ret ret with
       | `CannotReturnError -> ()
       | `ErrorIsMinusOne ->
         pr "if r == -1 {\n";
         pr "    return Err(self.get_error_from_handle(\"%s\"));\n" name;
         pr "}\n"
       | `ErrorIsNULL ->
         pr "if r.is_null() {\n";
         pr "    return Err(self.get_error_from_handle(\"%s\"));\n" name;
         pr "}\n"
      );

      (* This part is not required, but type system will guarantee that
       * the buffers are still alive. This is useful because Rust cannot
       * know whether raw pointers used above are alive or not.
       *)
      List.iter (
        function
        | Bool _ | Int _ | Int64 _ | Pointer _ -> ()
        | String (_, n)
        | OptString n
        | BufferIn n -> pr "drop(c_%s);\n" n;
        | StringList (_, n) ->
          pr "drop(c_%s);\n" n;
          pr "drop(c_%s_v);\n" n;
      ) args;
      if optargs <> [] then (
        pr "drop(optargs_cexpr);\n";
      );

      pr "Ok(";
      let pr = _pr in
      let pr3 fs = indent 3; pr fs in
      (match ret with
       | RErr -> pr "()"
       | RInt _ | RInt64 _ -> pr "r"
       | RBool _ -> pr "r != 0"
       | RConstString _ ->
         pr "unsafe{ ffi::CStr::from_ptr(r) }.to_str()?"
       | RString _ ->
         pr "{\n";
         pr3 "let s = unsafe { char_ptr_to_string(r) };\n";
         pr3 "unsafe { free(r as *const c_void) };";
         pr3 "s?\n";
         indent 2; pr "}";
       | RConstOptString _ ->
         pr "if r.is_null() {\n";
         pr3 "None\n";
         indent 2; pr "} else {\n";
         pr3 "Some(unsafe { ffi::CStr::from_ptr(r) }.to_str()?)\n";
         indent 2; pr "}";
       | RStringList _ ->
         pr "{\n";
         pr3 "let s = string_list(r);\n";
         pr3 "free_string_list(r);\n";
         pr3 "s?\n";
         indent 2; pr "}";
       | RStruct (_, n) ->
         let sn = camel_name_of_struct n in
         pr "{\n";
         pr3 "let s = %s::try_from(r);\n" sn;
         pr3 "unsafe { guestfs_free_%s(r) };\n" n;
         pr3 "s?\n";
         indent 2; pr "}";
       | RStructList (_, n) ->
         let sn = camel_name_of_struct n in
         pr "{\n";
         pr3 "let l = struct_list::<Raw%s, %s>(r);\n" sn sn;
         pr3 "unsafe { guestfs_free_%s_list(r) };\n" n;
         pr3 "l?\n";
         indent 2; pr "}";
       | RHashtable _ ->
         pr "{\n";
         pr3 "let h = hashmap(r);\n";
         pr3 "free_string_list(r);\n";
         pr3 "h?\n";
         indent 2; pr "}";
       | RBufferOut _ ->
         pr "{\n";
         pr3 "let s = unsafe { slice::from_raw_parts(r, size) }.to_vec();\n";
         pr3 "unsafe { free(r as *const c_void) } ;\n";
         pr3 "s\n";
         indent 2; pr "}";
      );
      pr ")\n";
      pr "    }\n\n"
  ) (actions |> external_functions |> sort);
  pr "}\n"
