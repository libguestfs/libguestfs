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

let rec generate_haskell_hs () =
  generate_header HaskellStyle LGPLv2plus;

  (* XXX We only know how to generate partial FFI for Haskell
   * at the moment.  Please help out!
   *)
  let can_generate style =
    match style with
    | _, _, (_::_) -> false (* no optional args yet *)
    | RErr, _, []
    | RInt _, _, []
    | RInt64 _, _, [] -> true
    | RBool _, _, []
    | RConstString _, _, []
    | RConstOptString _, _, []
    | RString _, _, []
    | RStringList _, _, []
    | RStruct _, _, []
    | RStructList _, _, []
    | RHashtable _, _, []
    | RBufferOut _, _, [] -> false in

  pr "\
{-# INCLUDE <guestfs.h> #-}
{-# LANGUAGE ForeignFunctionInterface #-}

module Guestfs (
  create";

  (* List out the names of the actions we want to export. *)
  List.iter (
    fun (name, style, _, _, _, _, _) ->
      if can_generate style then pr ",\n  %s" name
  ) all_functions;

  pr "
  ) where

-- Unfortunately some symbols duplicate ones already present
-- in Prelude.  We don't know which, so we hard-code a list
-- here.
import Prelude hiding (truncate)

import Foreign
import Foreign.C
import Foreign.C.Types
import System.IO
import Control.Exception
import Data.Typeable

data GuestfsS = GuestfsS            -- represents the opaque C struct
type GuestfsP = Ptr GuestfsS        -- guestfs_h *
type GuestfsH = ForeignPtr GuestfsS -- guestfs_h * with attached finalizer

-- XXX define properly later XXX
data PV = PV
data VG = VG
data LV = LV
data IntBool = IntBool
data Stat = Stat
data StatVFS = StatVFS
data Hashtable = Hashtable

foreign import ccall unsafe \"guestfs_create\" c_create
  :: IO GuestfsP
foreign import ccall unsafe \"&guestfs_close\" c_close
  :: FunPtr (GuestfsP -> IO ())
foreign import ccall unsafe \"guestfs_set_error_handler\" c_set_error_handler
  :: GuestfsP -> Ptr CInt -> Ptr CInt -> IO ()

create :: IO GuestfsH
create = do
  p <- c_create
  c_set_error_handler p nullPtr nullPtr
  h <- newForeignPtr c_close p
  return h

foreign import ccall unsafe \"guestfs_last_error\" c_last_error
  :: GuestfsP -> IO CString

-- last_error :: GuestfsH -> IO (Maybe String)
-- last_error h = do
--   str <- withForeignPtr h (\\p -> c_last_error p)
--   maybePeek peekCString str

last_error :: GuestfsH -> IO (String)
last_error h = do
  str <- withForeignPtr h (\\p -> c_last_error p)
  if (str == nullPtr)
    then return \"no error\"
    else peekCString str

";

  (* Generate wrappers for each foreign function. *)
  List.iter (
    fun (name, (ret, args, optargs as style), _, _, _, _, _) ->
      if can_generate style then (
        pr "foreign import ccall unsafe \"guestfs_%s\" c_%s\n" name name;
        pr "  :: ";
        generate_haskell_prototype ~handle:"GuestfsP" style;
        pr "\n";
        pr "\n";
        pr "%s :: " name;
        generate_haskell_prototype ~handle:"GuestfsH" ~hs:true style;
        pr "\n";
        pr "%s %s = do\n" name
          (String.concat " " ("h" :: List.map name_of_argt args));
        pr "  r <- ";
        (* Convert pointer arguments using with* functions. *)
        List.iter (
          function
          | FileIn n
          | FileOut n
          | Pathname n | Device n | Dev_or_Path n | String n | Key n ->
              pr "withCString %s $ \\%s -> " n n
          | BufferIn n ->
              pr "withCStringLen %s $ \\(%s, %s_size) -> " n n n
          | OptString n -> pr "maybeWith withCString %s $ \\%s -> " n n
          | StringList n | DeviceList n -> pr "withMany withCString %s $ \\%s -> withArray0 nullPtr %s $ \\%s -> " n n n n
          | Bool _ | Int _ | Int64 _ | Pointer _ -> ()
        ) args;
        (* Convert integer arguments. *)
        let args =
          List.map (
            function
            | Bool n -> sprintf "(fromBool %s)" n
            | Int n -> sprintf "(fromIntegral %s)" n
            | Int64 n | Pointer (_, n) -> sprintf "(fromIntegral %s)" n
            | FileIn n | FileOut n
            | Pathname n | Device n | Dev_or_Path n
            | String n | OptString n
            | StringList n | DeviceList n
            | Key n -> n
            | BufferIn n -> sprintf "%s (fromIntegral %s_size)" n n
          ) args in
        pr "withForeignPtr h (\\p -> c_%s %s)\n" name
          (String.concat " " ("p" :: args));
        (match ret with
         | RErr | RInt _ | RInt64 _ | RBool _ ->
             pr "  if (r == -1)\n";
             pr "    then do\n";
             pr "      err <- last_error h\n";
             pr "      fail err\n";
         | RConstString _ | RConstOptString _ | RString _
         | RStringList _ | RStruct _
         | RStructList _ | RHashtable _ | RBufferOut _ ->
             pr "  if (r == nullPtr)\n";
             pr "    then do\n";
             pr "      err <- last_error h\n";
             pr "      fail err\n";
        );
        (match ret with
         | RErr ->
             pr "    else return ()\n"
         | RInt _ ->
             pr "    else return (fromIntegral r)\n"
         | RInt64 _ ->
             pr "    else return (fromIntegral r)\n"
         | RBool _ ->
             pr "    else return (toBool r)\n"
         | RConstString _
         | RConstOptString _
         | RString _
         | RStringList _
         | RStruct _
         | RStructList _
         | RHashtable _
         | RBufferOut _ ->
             pr "    else return ()\n" (* XXXXXXXXXXXXXXXXXXXX *)
        );
        pr "\n";
      )
  ) all_functions

and generate_haskell_prototype ~handle ?(hs = false) (ret, args, optargs) =
  pr "%s -> " handle;
  let string = if hs then "String" else "CString" in
  let int = if hs then "Int" else "CInt" in
  let bool = if hs then "Bool" else "CInt" in
  let int64 = if hs then "Integer" else "Int64" in
  List.iter (
    fun arg ->
      (match arg with
       | Pathname _ | Device _ | Dev_or_Path _ | String _ | Key _ ->
           pr "%s" string
       | BufferIn _ ->
           if hs then pr "String"
           else pr "CString -> CInt"
       | OptString _ -> if hs then pr "Maybe String" else pr "CString"
       | StringList _ | DeviceList _ -> if hs then pr "[String]" else pr "Ptr CString"
       | Bool _ -> pr "%s" bool
       | Int _ -> pr "%s" int
       | Int64 _ -> pr "%s" int
       | Pointer _ -> pr "%s" int
       | FileIn _ -> pr "%s" string
       | FileOut _ -> pr "%s" string
      );
      pr " -> ";
  ) args;
  pr "IO (";
  (match ret with
   | RErr -> if not hs then pr "CInt"
   | RInt _ -> pr "%s" int
   | RInt64 _ -> pr "%s" int64
   | RBool _ -> pr "%s" bool
   | RConstString _ -> pr "%s" string
   | RConstOptString _ -> pr "Maybe %s" string
   | RString _ -> pr "%s" string
   | RStringList _ -> pr "[%s]" string
   | RStruct (_, typ) ->
       let name = camel_name_of_struct typ in
       pr "%s" name
   | RStructList (_, typ) ->
       let name = camel_name_of_struct typ in
       pr "[%s]" name
   | RHashtable _ -> pr "Hashtable"
   | RBufferOut _ -> pr "%s" string
  );
  pr ")"
