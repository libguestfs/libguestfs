(* libguestfs
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

open Printf

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

let generate_header = generate_header ~inputs:["generator/golang.ml"]

let generate_golang_go () =
  generate_header CStyle LGPLv2plus;

  pr "\
package guestfs

/*
#cgo CFLAGS:  -DGUESTFS_PRIVATE=1 -DGUESTFS_NO_WARN_DEPRECATED -UGUESTFS_NO_DEPRECATED
#cgo LDFLAGS: -lguestfs
#include <stdio.h>
#include <stdlib.h>
#include \"guestfs.h\"

// cgo can't deal with variable argument functions.
static guestfs_h *
_go_guestfs_create_flags (unsigned flags)
{
    return guestfs_create_flags (flags);
}

// Passing a Go pointer to C via CGo is allowed, but the memory that points to
// is not allowed to contain further Go pointers. The helper functions below
// are one way to implement this, although the same can be achieved purely in
// Go as well. See the discussion here:
// <https://listman.redhat.com/archives/libguestfs/2021-September/msg00101.html>.
typedef char *pChar;

pChar *allocStringArray (size_t nmemb)
{
    pChar *array;

    array = malloc (sizeof (pChar) * (nmemb + 1));
    array[nmemb] = NULL;
    return array;
}

void storeString (pChar *array, size_t idx, pChar string)
{
    array[idx] = string;
}

void freeStringArray (pChar *array)
{
    pChar *position;
    pChar string;

    position = array;
    while ((string = *position) != NULL) {
      free (string);
      position++;
    }
    free (array);
}
*/
import \"C\"

import (
    \"fmt\"
    \"runtime\"
    \"syscall\"
    \"unsafe\"
)

/* Handle. */
type Guestfs struct {
    g *C.guestfs_h
}

/* Convert handle to string (just for debugging). */
func (g *Guestfs) String () string {
    return \"&Guestfs{}\"
}

/* Create a new handle with flags. */
type CreateFlags uint

const (
    CREATE_NO_ENVIRONMENT = CreateFlags (C.GUESTFS_CREATE_NO_ENVIRONMENT)
    CREATE_NO_CLOSE_ON_EXIT = CreateFlags (C.GUESTFS_CREATE_NO_CLOSE_ON_EXIT)
)

func Create_flags (flags CreateFlags) (*Guestfs, error) {
    c_g, err := C._go_guestfs_create_flags (C.uint (flags))
    if c_g == nil {
        return nil, err
    }
    g := &Guestfs{g : c_g}
    // Finalizers aren't guaranteed to run, but try having one anyway ...
    runtime.SetFinalizer (g, (*Guestfs).Close)
    return g, nil
}

/* Create a new handle without flags. */
func Create () (*Guestfs, error) {
    return Create_flags (0)
}

/* Apart from Create() and Create_flags() which return a (handle, error)
 * pair, the other functions return a ([result,] GuestfsError) where
 * GuestfsError is defined here.
 */
type GuestfsError struct {
    Op string                // operation which failed
    Errmsg string            // string (guestfs_last_error)
    Errno syscall.Errno      // errno (guestfs_last_errno)
}

func (e *GuestfsError) String() string {
    if e.Errno != 0 {
        return fmt.Sprintf (\"%%s: %%s\", e.Op, e.Errmsg);
    } else {
        return fmt.Sprintf (\"%%s: %%s: %%s\", e.Op, e.Errmsg, e.Errno);
    }
}

/* Implement the error interface */
func (e *GuestfsError) Error() string {
     return e.String()
}

func get_error_from_handle (g *Guestfs, op string) *GuestfsError {
    // NB: DO NOT try to free c_errmsg!
    c_errmsg := C.guestfs_last_error (g.g)
    errmsg := C.GoString (c_errmsg)

    errno := syscall.Errno (C.guestfs_last_errno (g.g))

    return &GuestfsError{ Op : op, Errmsg : errmsg, Errno : errno }
}

func closed_handle_error (op string) *GuestfsError {
    return &GuestfsError{ Op : op, Errmsg : \"handle is closed\",
                          Errno : syscall.Errno (0) }
}

/* Close the handle. */
func (g *Guestfs) Close () *GuestfsError {
    if g.g == nil {
        return closed_handle_error (\"close\")
    }
    C.guestfs_close (g.g)
    g.g = nil
    return nil
}

/* Functions for translating between NULL-terminated lists of
 * C strings and golang []string.
 */
func arg_string_list (xs []string) **C.char {
    r := C.allocStringArray (C.size_t (len (xs)))
    for i, x := range xs {
        C.storeString (r, C.size_t (i), C.CString (x));
    }
    return (**C.char) (r)
}

func count_string_list (argv **C.char) int {
    var i int
    for *argv != nil {
        i++
        argv = (**C.char) (unsafe.Pointer (uintptr (unsafe.Pointer (argv)) +
                                           unsafe.Sizeof (*argv)))
    }
    return i
}

func free_string_list (argv **C.char) {
    C.freeStringArray ((*C.pChar) (argv))
}

func return_string_list (argv **C.char) []string {
    r := make ([]string, count_string_list (argv))
    var i int
    for *argv != nil {
        r[i] = C.GoString (*argv)
        i++
        argv = (**C.char) (unsafe.Pointer (uintptr (unsafe.Pointer (argv)) +
                                           unsafe.Sizeof (*argv)))
    }
    return r
}

func return_hashtable (argv **C.char) map[string]string {
    r := make (map[string]string)
    for *argv != nil {
        key := C.GoString (*argv)
        argv = (**C.char) (unsafe.Pointer (uintptr (unsafe.Pointer (argv)) +
                                           unsafe.Sizeof (*argv)))
        if *argv == nil {
            panic (\"odd number of items in hash table\")
        }

        r[key] = C.GoString (*argv)
        argv = (**C.char) (unsafe.Pointer (uintptr (unsafe.Pointer (argv)) +
                                           unsafe.Sizeof (*argv)))
    }
    return r
}

/* XXX Events/callbacks not yet implemented. */
";

  (* Structures. *)
  List.iter (
    fun { s_camel_name = name; s_name = c_name; s_cols = cols } ->
      pr "\n";
      pr "type %s struct {\n" name;
      List.iter (
        fun (n, field) ->
          (* We capitalize the field names so that they are
           * publicly accessible.
           *)
          let n = String.capitalize_ascii n in
          match field with
          | FChar -> pr "    %s byte\n" n
          | FString -> pr "    %s string\n" n
          | FBuffer -> pr "    %s []byte\n" n
          | FUInt32 -> pr "    %s uint32\n" n
          | FInt32 -> pr "    %s int32\n" n
          | FUInt64 -> pr "    %s uint64\n" n
          | FInt64 -> pr "    %s int64\n" n
          | FBytes -> pr "    %s uint64\n" n
          | FUUID -> pr "    %s [32]byte\n" n
          | FOptPercent -> pr "    %s float32\n" n
      ) cols;
      pr "}\n";
      pr "\n";
      pr "func return_%s (c *C.struct_guestfs_%s) *%s {\n" name c_name name;
      pr "    r := %s{}\n" name;
      List.iter (
        fun (n, field) ->
          let gon = String.capitalize_ascii n in
          match field with
          | FChar -> pr "    r.%s = byte (c.%s)\n" gon n
          | FString -> pr "    r.%s = C.GoString (c.%s)\n" gon n
          | FBuffer ->
             pr "    r.%s = C.GoBytes (unsafe.Pointer (c.%s), C.int (c.%s_len))\n"
               gon n n
          | FUInt32 -> pr "    r.%s = uint32 (c.%s)\n" gon n
          | FInt32 -> pr "    r.%s = int32 (c.%s)\n" gon n
          | FUInt64 -> pr "    r.%s = uint64 (c.%s)\n" gon n
          | FInt64 -> pr "    r.%s = int64 (c.%s)\n" gon n
          | FBytes -> pr "    r.%s = uint64 (c.%s)\n" gon n
          | FOptPercent -> pr "    r.%s = float32 (c.%s)\n" gon n
          | FUUID ->
             pr "    // XXX doesn't work XXX r.%s = C.GoBytes (c.%s, len (c.%s))\n" gon n n;
             pr "    r.%s = [32]byte{}\n" gon
      ) cols;
      pr "    return &r\n";
      pr "}\n";
      pr "\n";
      pr "func return_%s_list (c *C.struct_guestfs_%s_list) *[]%s {\n"
        name c_name name;
      pr "    nrelems := int (c.len)\n";
      pr "    ptr := uintptr (unsafe.Pointer (c.val))\n";
      pr "    elemsize := unsafe.Sizeof (*c.val)\n";
      pr "    r := make ([]%s, nrelems)\n" name;
      pr "    for i := 0; i < nrelems; i++ {\n";
      pr "        r[i] = *return_%s ((*C.struct_guestfs_%s) (unsafe.Pointer (ptr)))\n"
        name c_name;
      pr "        ptr += elemsize";
      pr "    }\n";
      pr "    return &r\n";
      pr "}\n";
  ) external_structs;

  (* Actions. *)
  List.iter (
    fun ({ name; shortdesc; style = (ret, args, optargs) } as f) ->
      let go_name = String.capitalize_ascii name in

      (* If it has optional arguments, pass them in a struct
       * after the required arguments.
       *)
      if optargs <> [] then (
        pr "\n";
        pr "/* Struct carrying optional arguments for %s */\n" go_name;
        pr "type Optargs%s struct {\n" go_name;
        List.iter (
          fun optarg ->
            let cn = String.capitalize_ascii (name_of_optargt optarg) in
            pr "    /* %s field is ignored unless %s_is_set == true */\n"
              cn cn;
            pr "    %s_is_set bool\n" cn;
            match optarg with
            | OBool _ ->
              pr "    %s bool\n" cn
            | OInt _ ->
              pr "    %s int\n" cn
            | OInt64 _ ->
              pr "    %s int64\n" cn
            | OString _ ->
              pr "    %s string\n" cn
            | OStringList _ ->
              pr "    %s []string\n" cn
        ) optargs;
        pr "}\n";
      );

      pr "\n";
      pr "/* %s : %s */\n" name shortdesc;
      pr "func (g *Guestfs) %s" go_name;

      (* Arguments. *)
      pr " (";
      let comma = ref false in
      List.iter (
        fun arg ->
          if !comma then pr ", ";
          comma := true;
          match arg with
          | Bool n -> pr "%s bool" n
          | Int n -> pr "%s int" n
          | Int64 n -> pr "%s int64" n
          | String (_, n) -> pr "%s string" n
          | OptString n -> pr "%s *string" n
          | StringList (_, n) -> pr "%s []string" n
          | BufferIn n -> pr "%s []byte" n
          | Pointer (_, n) -> pr "%s int64" n
      ) args;
      if optargs <> [] then (
        if !comma then pr ", ";
        comma := true;
        pr "optargs *Optargs%s" go_name
      );
      pr ")";

      (* Return type. *)
      let noreturn =
        match ret with
        | RErr -> pr " error"; ""
        | RInt _ -> pr " (int, error)"; "0, "
        | RInt64 _ -> pr " (int64, error)"; "0, "
        | RBool _ -> pr " (bool, error)"; "false, "
        | RConstString _
        | RString _ -> pr " (string, error)"; "\"\", "
        | RConstOptString _ -> pr " (*string, error)"; "nil, "
        | RStringList _ -> pr " ([]string, error)"; "nil, "
        | RStruct (_, sn) ->
          let sn = camel_name_of_struct sn in
          pr " (*%s, error)" sn;
          sprintf "&%s{}, " sn
        | RStructList (_, sn) ->
          let sn = camel_name_of_struct sn in
          pr " (*[]%s, error)" sn;
          "nil, "
        | RHashtable _ -> pr " (map[string]string, error)"; "nil, "
        | RBufferOut _ -> pr " ([]byte, error)"; "nil, " in

      (* Body of the function. *)
      pr " {\n";
      pr "    if g.g == nil {\n";
      pr "        return %sclosed_handle_error (\"%s\")\n" noreturn name;
      pr "    }\n";

      List.iter (
        function
        | Bool n ->
          pr "\n";
          pr "    var c_%s C.int\n" n;
          pr "    if %s { c_%s = 1 } else { c_%s = 0 }\n" n n n
        | String (_, n) ->
          pr "\n";
          pr "    c_%s := C.CString (%s)\n" n n;
          pr "    defer C.free (unsafe.Pointer (c_%s))\n" n
        | OptString n ->
          pr "\n";
          pr "    var c_%s *C.char = nil\n" n;
          pr "    if %s != nil {\n" n;
          pr "        c_%s = C.CString (*%s)\n" n n;
          pr "        defer C.free (unsafe.Pointer (c_%s))\n" n;
          pr "    }\n"
        | StringList (_, n) ->
          pr "\n";
          pr "    c_%s := arg_string_list (%s)\n" n n;
          pr "    defer free_string_list (c_%s)\n" n
        | BufferIn n ->
          pr "\n";
          pr "    /* string() cast here is apparently safe because\n";
          pr "     *   \"Converting a slice of bytes to a string type yields\n";
          pr "     *   a string whose successive bytes are the elements of\n";
          pr "     *   the slice.\"\n";
          pr "     */\n";
          pr "    c_%s := C.CString (string (%s))\n" n n;
          pr "    defer C.free (unsafe.Pointer (c_%s))\n" n
        | Int _
        | Int64 _
        | Pointer _ -> ()
      ) args;

      if optargs <> [] then (
        pr "    c_optargs := C.struct_guestfs_%s_argv{}\n" f.c_name;
        pr "    if optargs != nil {\n";
        List.iter (
          fun optarg ->
            let n = name_of_optargt optarg in
            let cn = String.capitalize_ascii n in
            pr "        if optargs.%s_is_set {\n" cn;
            pr "            c_optargs.bitmask |= C.%s_%s_BITMASK\n"
              f.c_optarg_prefix (String.uppercase_ascii n);
            (match optarg with
            | OBool _ ->
              pr "            if optargs.%s { c_optargs.%s = 1 } else { c_optargs.%s = 0}\n" cn n n
            | OInt _ ->
              pr "            c_optargs.%s = C.int (optargs.%s)\n" n cn
            | OInt64 _ ->
              pr "            c_optargs.%s = C.int64_t (optargs.%s)\n" n cn
            | OString _ ->
              pr "            c_optargs.%s = C.CString (optargs.%s)\n" n cn;
              pr "            defer C.free (unsafe.Pointer (c_optargs.%s))\n" n
            | OStringList _ ->
              pr "            c_optargs.%s = arg_string_list (optargs.%s)\n"
                n cn;
              pr "            defer free_string_list (c_optargs.%s)\n" n
            );
            pr "        }\n"
        ) optargs;
        pr "    }\n"
      );

      (match ret with
      | RBufferOut _ ->
        pr "\n";
        pr "    var size C.size_t\n"
      | _ -> ()
      );

      pr "\n";
      pr "    r := C.%s (g.g" f.c_function;
      List.iter (
        fun arg ->
          pr ", ";
          match arg with
          | Bool n -> pr "c_%s" n
          | Int n -> pr "C.int (%s)" n
          | Int64 n -> pr "C.int64_t (%s)" n
          | String (_, n)
          | OptString n -> pr "c_%s" n
          | StringList (_, n) -> pr "c_%s" n
          | BufferIn n -> pr "c_%s, C.size_t (len (%s))" n n
          | Pointer _ -> pr "nil"
      ) args;
      (match ret with
      | RBufferOut _ -> pr ", &size"
      | _ -> ()
      );
      if optargs <> [] then
        pr ", &c_optargs";
      pr ")\n";

      (match errcode_of_ret ret with
      | `CannotReturnError -> ()
      | `ErrorIsMinusOne ->
        pr "\n";
        pr "    if r == -1 {\n";
        pr "        return %sget_error_from_handle (g, \"%s\")\n" noreturn name;
        pr "    }\n"
      | `ErrorIsNULL ->
        pr "\n";
        pr "    if r == nil {\n";
        pr "        return %sget_error_from_handle (g, \"%s\")\n" noreturn name;
        pr "    }\n"
      );

      (match ret with
      | RErr -> pr "    return nil\n"
      | RInt _ -> pr "    return int (r), nil\n"
      | RInt64 _ -> pr "    return int64 (r), nil\n"
      | RBool _ -> pr "    return r != 0, nil\n"
      | RConstString _ ->
        pr "    return C.GoString (r), nil\n"
      | RString _ ->
        pr "    defer C.free (unsafe.Pointer (r))\n";
        pr "    return C.GoString (r), nil\n"
      | RConstOptString _ ->
        pr "    if r != nil {\n";
        pr "        r_s := string (rune (*r))\n";
        pr "        return &r_s, nil\n";
        pr "    } else {\n";
        pr "        return nil, nil\n";
        pr "    }\n"
      | RStringList _ ->
        pr "    defer free_string_list (r)\n";
        pr "    return return_string_list (r), nil\n"
      | RStruct (_, sn) ->
        pr "    defer C.guestfs_free_%s (r)\n" sn;
        let sn = camel_name_of_struct sn in
        pr "    return return_%s (r), nil\n" sn
      | RStructList (_, sn) ->
        pr "    defer C.guestfs_free_%s_list (r)\n" sn;
        let sn = camel_name_of_struct sn in
        pr "    return return_%s_list (r), nil\n" sn
      | RHashtable _ ->
        pr "    defer free_string_list (r)\n";
        pr "    return return_hashtable (r), nil\n"
      | RBufferOut _ ->
        pr "    defer C.free (unsafe.Pointer (r))\n";
        pr "    return C.GoBytes (unsafe.Pointer (r), C.int (size)), nil\n"
      );
      pr "}\n";
  ) (actions |> external_functions |> sort)
