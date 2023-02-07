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

let generate_header = generate_header ~inputs:["generator/xdr.ml"]

(* Generate the protocol (XDR) file, 'guestfs_protocol.x' and
 * indirectly 'guestfs_protocol.h' and 'guestfs_protocol.c'.
 *
 * We have to use an underscore instead of a dash because otherwise
 * rpcgen generates incorrect code.
 *
 * This header is NOT exported to clients, but see also generate_structs_h.
 *)
let generate_xdr () =
  generate_header ~emacs_mode:"c" CStyle LGPLv2plus;

  pr "/* This file defines the protocol used between the library and\n";
  pr " * the appliance/daemon.  For more information see the COMMUNICATION\n";
  pr " * PROTOCOL section in guestfs(3).  Note this protocol is internal\n";
  pr " * to libguestfs and may change at any time.\n";
  pr " */\n";
  pr "\n";
  pr "%%#include <config.h>\n";
  pr "\n";
  pr "%%#ifndef HAVE_XDR_UINT64_T\n";
  pr "%%#define xdr_uint64_t xdr_int64_t\n";
  pr "%%#endif\n";
  pr "\n";

  pr "/* This has to be defined to get around a limitation in Sun's rpcgen. */\n";
  pr "typedef string guestfs_str<>;\n";
  pr "\n";

  pr "/* Internal structures. */\n";
  pr "\n";
  List.iter (
    fun { s_name = typ; s_cols = cols } ->
        pr "struct guestfs_int_%s {\n" typ;
        List.iter (function
                   | name, FChar -> pr "  char %s;\n" name
                   | name, FString -> pr "  string %s<>;\n" name
                   | name, FBuffer -> pr "  opaque %s<>;\n" name
                   | name, FUUID -> pr "  opaque %s[32];\n" name
                   | name, FInt32 -> pr "  int %s;\n" name
                   | name, FUInt32 -> pr "  unsigned int %s;\n" name
                   | name, (FInt64|FBytes) -> pr "  int64_t %s;\n" name
                   | name, FUInt64 -> pr "  uint64_t %s;\n" name
                   | name, FOptPercent -> pr "  float %s;\n" name
                  ) cols;
        pr "};\n";
        pr "\n";
        pr "typedef struct guestfs_int_%s guestfs_int_%s_list<>;\n" typ typ;
        pr "\n";
  ) structs;

  pr "/* Function arguments and return values. */\n";
  pr "\n";
  List.iter (
    fun { name = shortname; style = ret, args, optargs } ->
      let name = "guestfs_" ^ shortname in

      (* Ordinary arguments and optional arguments are concatenated
       * together in the XDR args struct.  The optargs_bitmask field
       * in the header controls which optional arguments are
       * meaningful.  FileIn/FileOut parameters are ignored here.
       *)
      let args_passed_to_daemon = args @ args_of_optargs optargs in
      let args_passed_to_daemon =
        List.filter (function String ((FileIn|FileOut), _) -> false | _ -> true)
                    args_passed_to_daemon in
      (match args_passed_to_daemon with
      | [] -> ()
      | args ->
        pr "struct %s_args {\n" name;
        List.iter (
          function
          | String (_, n) ->
            pr "  string %s<>;\n" n
          | OptString n -> pr "  guestfs_str *%s;\n" n
          | StringList (_, n) ->
            pr "  guestfs_str %s<>;\n" n
          | Bool n -> pr "  bool %s;\n" n
          | Int n -> pr "  int %s;\n" n
          | Int64 n -> pr "  int64_t %s;\n" n
          | BufferIn n ->
            pr "  opaque %s<>;\n" n
          | Pointer _ -> assert false
        ) args;
        pr "};\n\n"
      );
      (match ret with
       | RErr -> ()
       | RInt n ->
           pr "struct %s_ret {\n" name;
           pr "  int %s;\n" n;
           pr "};\n\n"
       | RInt64 n ->
           pr "struct %s_ret {\n" name;
           pr "  int64_t %s;\n" n;
           pr "};\n\n"
       | RBool n ->
           pr "struct %s_ret {\n" name;
           pr "  bool %s;\n" n;
           pr "};\n\n"
       | RConstString _ | RConstOptString _ ->
           failwithf "RConstString|RConstOptString cannot be used by daemon functions"
       | RString (_, n) ->
           pr "struct %s_ret {\n" name;
           pr "  string %s<>;\n" n;
           pr "};\n\n"
       | RStringList (_, n) ->
           pr "struct %s_ret {\n" name;
           pr "  guestfs_str %s<>;\n" n;
           pr "};\n\n"
       | RStruct (n, typ) ->
           pr "struct %s_ret {\n" name;
           pr "  guestfs_int_%s %s;\n" typ n;
           pr "};\n\n"
       | RStructList (n, typ) ->
           pr "struct %s_ret {\n" name;
           pr "  guestfs_int_%s_list %s;\n" typ n;
           pr "};\n\n"
       | RHashtable (_, _, n) ->
           pr "struct %s_ret {\n" name;
           pr "  guestfs_str %s<>;\n" n;
           pr "};\n\n"
       | RBufferOut n ->
           pr "struct %s_ret {\n" name;
           pr "  opaque %s<>;\n" n;
           pr "};\n\n"
      );
  ) (actions |> daemon_functions |> sort);

  pr "/* Table of procedure numbers. */\n";
  pr "enum guestfs_procedure {\n";
  let rec loop = function
    | [] -> ()
    | { proc_nr = None } :: _ -> assert false
    | { name = shortname; proc_nr = Some proc_nr } :: [] ->
      pr "  GUESTFS_PROC_%s = %d\n" (String.uppercase_ascii shortname) proc_nr
    | { name = shortname; proc_nr = Some proc_nr } :: rest ->
      pr "  GUESTFS_PROC_%s = %d,\n" (String.uppercase_ascii shortname) proc_nr;
      loop rest
  in
  loop (actions |> daemon_functions |> sort);
  pr "};\n";
  pr "\n";

  pr "const GUESTFS_MAX_PROC_NR = %d;\n" Proc_nr.max_proc_nr;
  pr "\n";

  pr "/* The remote procedure call protocol. */\n";
  pr "\n";

  (* Having to choose a maximum message size is annoying for several
   * reasons (it limits what we can do in the API), but it (a) makes
   * the protocol a lot simpler, and (b) provides a bound on the size
   * of the daemon which operates in limited memory space.
   *)
  pr "const GUESTFS_MESSAGE_MAX = %d;\n" (4 * 1024 * 1024);
  pr "\n";

  (* Message header, etc. *)
  pr "\
const GUESTFS_PROGRAM = 0x2000F5F5;
const GUESTFS_PROTOCOL_VERSION = 4;

/* These constants must be larger than any possible message length. */
const GUESTFS_LAUNCH_FLAG = 0xf5f55ff5;
const GUESTFS_CANCEL_FLAG = 0xffffeeee;
const GUESTFS_PROGRESS_FLAG = 0xffff5555;

enum guestfs_message_direction {
  GUESTFS_DIRECTION_CALL = 0,        /* client -> daemon */
  GUESTFS_DIRECTION_REPLY = 1        /* daemon -> client */
};

enum guestfs_message_status {
  GUESTFS_STATUS_OK = 0,
  GUESTFS_STATUS_ERROR = 1
};

";

  pr "const GUESTFS_ERROR_LEN = %d;\n" (64 * 1024);
  pr "\n";

  pr "\
struct guestfs_message_error {
  string errno_string<32>;           /* errno eg. \"EINVAL\", empty string
                                        if errno not available */
  string error_message<GUESTFS_ERROR_LEN>;
};

struct guestfs_message_header {
  unsigned prog;                     /* GUESTFS_PROGRAM */
  unsigned vers;                     /* GUESTFS_PROTOCOL_VERSION */
  guestfs_procedure proc;            /* GUESTFS_PROC_x */
  guestfs_message_direction direction;
  unsigned serial;                   /* message serial number */
  uint64_t progress_hint;            /* upload hint for progress bar */
  uint64_t optargs_bitmask;          /* bitmask for optional args */
  guestfs_message_status status;
};

const GUESTFS_MAX_CHUNK_SIZE = 8192;

struct guestfs_chunk {
  int cancel;			     /* if non-zero, transfer is cancelled */
  /* data size is 0 bytes if the transfer has finished successfully */
  opaque data<GUESTFS_MAX_CHUNK_SIZE>;
};

/* Progress notifications.  Daemon self-limits these messages to
 * at most one per second.  The daemon can send these messages
 * at any time, and the caller should discard unexpected messages.
 * 'position' and 'total' have undefined units; however they may
 * have meaning for some calls.
 *
 * Notes:
 *
 * (1) guestfs_int_recv_from_daemon assumes the XDR-encoded
 * structure is 24 bytes long.
 *
 * (2) daemon/proto.c:async_safe_send_pulse assumes the progress
 * message is laid out precisely in this way.  So if you change
 * this then you'd better change that function as well.
 */
struct guestfs_progress {
  guestfs_procedure proc;            /* @0:  GUESTFS_PROC_x */
  unsigned serial;                   /* @4:  message serial number */
  uint64_t position;                 /* @8:  0 <= position <= total */
  uint64_t total;                    /* @16: total size of operation */
                                     /* @24: size of structure */
};
"
