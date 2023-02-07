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

open Printf

open Std_utils
open Types
open Utils
open Pr
open Docstrings
open Optgroups
open Actions
open Structs

let generate_header = generate_header ~inputs:["generator/haskell.ml"]

let rec generate_haskell_hs () =
  generate_header HaskellStyle LGPLv2plus;

  (* See guestfs(3)/Haskell for limitations of the current Haskell
   * bindings.  Please help out! XXX
   *)
  let can_generate = function
    | _, _, (_::_) -> false (* no optional args yet *)
    | RErr, _, []
    | RInt _, _, []
    | RInt64 _, _, []
    | RBool _, _, []
    | RConstString _, _, []
    | RString _, _, []
    | RStringList _, _, []
    | RHashtable _, _, [] -> true
    | RStruct _, _, []
    | RStructList _, _, []
    | RBufferOut _, _, []
    | RConstOptString _, _, [] -> false
  in

  pr "\
{-# LANGUAGE ForeignFunctionInterface #-}

module Guestfs (
  create";

  (* List out the names of the actions we want to export. *)
  List.iter (
    fun { name; style } ->
      if can_generate style then pr ",\n  %s" name
  ) (actions |> external_functions |> sort);

  pr "
  ) where

-- Unfortunately some symbols duplicate ones already present
-- in Prelude.  We don't know which, so we hard-code a list
-- here.
import Prelude hiding (head, tail, truncate)

import Foreign
import Foreign.C
import Foreign.C.Types
import System.IO
import Control.Exception
import Data.Typeable

data GuestfsS = GuestfsS            -- represents the opaque C struct
type GuestfsP = Ptr GuestfsS        -- guestfs_h *
type GuestfsH = ForeignPtr GuestfsS -- guestfs_h * with attached finalizer

foreign import ccall unsafe \"guestfs.h guestfs_create\" c_create
  :: IO GuestfsP
foreign import ccall unsafe \"guestfs.h &guestfs_close\" c_close
  :: FunPtr (GuestfsP -> IO ())
foreign import ccall unsafe \"guestfs.h guestfs_set_error_handler\" c_set_error_handler
  :: GuestfsP -> Ptr CInt -> Ptr CInt -> IO ()

create :: IO GuestfsH
create = do
  p <- c_create
  c_set_error_handler p nullPtr nullPtr
  h <- newForeignPtr c_close p
  return h

foreign import ccall unsafe \"guestfs.h guestfs_last_error\" c_last_error
  :: GuestfsP -> IO CString

-- last_error :: GuestfsH -> IO (Maybe String)
-- last_error h = do
--   str <- withForeignPtr h (\\p -> c_last_error p)
--   maybePeek peekCString str

last_error :: GuestfsH -> IO String
last_error h = do
  str <- withForeignPtr h (\\p -> c_last_error p)
  if (str == nullPtr)
    then return \"no error\"
    else peekCString str

assocListOfHashtable :: Eq a => [a] -> [(a,a)]
assocListOfHashtable [] = []
assocListOfHashtable [a] =
  fail \"RHashtable returned an odd number of elements\"
assocListOfHashtable (a:b:rest) = (a,b) : assocListOfHashtable rest

";

  (* Generate wrappers for each foreign function. *)
  List.iter (
    fun { name; style = (ret, args, optargs as style);
          c_function = c_function } ->
      if can_generate style then (
        pr "foreign import ccall unsafe \"guestfs.h %s\" c_%s\n"
          c_function name;
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
          | String (_, n) ->
              pr "withCString %s $ \\%s -> " n n
          | BufferIn n ->
              pr "withCStringLen %s $ \\(%s, %s_size) -> " n n n
          | OptString n -> pr "maybeWith withCString %s $ \\%s -> " n n
          | StringList (_, n) ->
              pr "withMany withCString %s $ \\%s -> withArray0 nullPtr %s $ \\%s -> " n n n n
          | Bool _ | Int _ | Int64 _ | Pointer _ -> ()
        ) args;
        (* Convert integer arguments. *)
        let args =
          List.map (
            function
            | Bool n -> sprintf "(fromBool %s)" n
            | Int n -> sprintf "(fromIntegral %s)" n
            | Int64 n | Pointer (_, n) -> sprintf "(fromIntegral %s)" n
            | String (_, n)
            | OptString n
            | StringList (_, n) -> n
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
         | RString _ ->
             pr "    else peekCString r\n"
         | RStringList _ ->
             pr "    else peekArray0 nullPtr r >>= mapM peekCString\n"
         | RHashtable _ ->
             pr "    else do\n";
             pr "      arr <- peekArray0 nullPtr r\n";
             pr "      arr <- mapM peekCString arr\n";
             pr "      return (assocListOfHashtable arr)\n"
         | RStruct _
         | RStructList _
         | RBufferOut _
         | RConstOptString _ ->
             pr "    else return ()\n" (* XXXXXXXXXXXXXXXXXXXX *)
        );
        pr "\n";
      )
  ) (actions |> external_functions |> sort)

and generate_haskell_prototype ~handle ?(hs = false) (ret, args, optargs) =
  pr "%s -> " handle;
  if not hs then (
    List.iter (
      fun arg ->
        (match arg with
         | String _ ->
            pr "CString"
         | BufferIn _ ->
            pr "CString -> CInt"
         | OptString _ ->
            pr "CString"
         | StringList _ ->
            pr "Ptr CString"
         | Bool _ -> pr "CInt"
         | Int _ -> pr "CInt"
         | Int64 _ -> pr "Int64"
         | Pointer _ -> pr "CInt"
        );
        pr " -> ";
    ) args;
    pr "IO ";
    (match ret with
    | RErr -> pr "CInt"
    | RInt _ -> pr "CInt"
    | RInt64 _ -> pr "Int64"
    | RBool _ -> pr "CInt"
    | RConstString _ -> pr "CString"
    | RConstOptString _ -> pr "(Maybe CString)"
    | RString _ -> pr "CString"
    | RStringList _ -> pr "(Ptr CString)"
    | RStruct (_, typ) ->
      let name = camel_name_of_struct typ in
      pr "%s" name
    | RStructList (_, typ) ->
      let name = camel_name_of_struct typ in
      pr "[%s]" name
    | RHashtable _ -> pr "(Ptr CString)"
    | RBufferOut _ -> pr "CString"
    )
  )
  else (* hs *) (
    List.iter (
      fun arg ->
        (match arg with
         | String _ ->
           pr "String"
         | BufferIn _ ->
           pr "String"
         | OptString _ ->
           pr "Maybe String"
         | StringList _ ->
           pr "[String]"
         | Bool _ -> pr "Bool"
         | Int _ -> pr "Int"
         | Int64 _ -> pr "Integer"
         | Pointer _ -> pr "Int"
        );
        pr " -> ";
    ) args;
    pr "IO ";
    (match ret with
    | RErr -> pr "()"
    | RInt _ -> pr "Int"
    | RInt64 _ -> pr "Int64"
    | RBool _ -> pr "Bool"
    | RConstString _ -> pr "String"
    | RConstOptString _ -> pr "(Maybe String)"
    | RString _ -> pr "String"
    | RStringList _ -> pr "[String]"
    | RStruct (_, typ) ->
      let name = camel_name_of_struct typ in
      pr "%s" name
    | RStructList (_, typ) ->
      let name = camel_name_of_struct typ in
      pr "[%s]" name
    | RHashtable _ -> pr "[(String, String)]"
    | RBufferOut _ -> pr "String"
    )
  )
