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

(* Generate the protocol (XDR) file, 'guestfs_protocol.x' and
 * indirectly 'guestfs_protocol.h' and 'guestfs_protocol.c'.
 *
 * We have to use an underscore instead of a dash because otherwise
 * rpcgen generates incorrect code.
 *
 * This header is NOT exported to clients, but see also generate_structs_h.
 *)
let generate_xdr () =
  generate_header CStyle LGPLv2plus;

  (* This has to be defined to get around a limitation in Sun's rpcgen. *)
  pr "typedef string guestfs_str<>;\n";
  pr "\n";

  (* Internal structures. *)
  List.iter (
    function
    | typ, cols ->
        pr "struct guestfs_int_%s {\n" typ;
        List.iter (function
                   | name, FChar -> pr "  char %s;\n" name
                   | name, FString -> pr "  string %s<>;\n" name
                   | name, FBuffer -> pr "  opaque %s<>;\n" name
                   | name, FUUID -> pr "  opaque %s[32];\n" name
                   | name, (FInt32|FUInt32) -> pr "  int %s;\n" name
                   | name, (FInt64|FUInt64|FBytes) -> pr "  hyper %s;\n" name
                   | name, FOptPercent -> pr "  float %s;\n" name
                  ) cols;
        pr "};\n";
        pr "\n";
        pr "typedef struct guestfs_int_%s guestfs_int_%s_list<>;\n" typ typ;
        pr "\n";
  ) structs;

  List.iter (
    fun (shortname, (ret, args, optargs), _, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in

      (* Ordinary arguments and optional arguments are concatenated
       * together in the XDR args struct.  The optargs_bitmask field
       * in the header controls which optional arguments are
       * meaningful.
       *)
      (match args @ args_of_optargs optargs with
       | [] -> ()
       | args ->
           pr "struct %s_args {\n" name;
           List.iter (
             function
             | Pathname n | Device n | Dev_or_Path n | String n | Key n ->
                 pr "  string %s<>;\n" n
             | OptString n -> pr "  guestfs_str *%s;\n" n
             | StringList n | DeviceList n -> pr "  guestfs_str %s<>;\n" n
             | Bool n -> pr "  bool %s;\n" n
             | Int n -> pr "  int %s;\n" n
             | Int64 n -> pr "  hyper %s;\n" n
             | BufferIn n ->
                 pr "  opaque %s<>;\n" n
             | FileIn _ | FileOut _ -> ()
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
           pr "  hyper %s;\n" n;
           pr "};\n\n"
       | RBool n ->
           pr "struct %s_ret {\n" name;
           pr "  bool %s;\n" n;
           pr "};\n\n"
       | RConstString _ | RConstOptString _ ->
           failwithf "RConstString|RConstOptString cannot be used by daemon functions"
       | RString n ->
           pr "struct %s_ret {\n" name;
           pr "  string %s<>;\n" n;
           pr "};\n\n"
       | RStringList n ->
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
       | RHashtable n ->
           pr "struct %s_ret {\n" name;
           pr "  guestfs_str %s<>;\n" n;
           pr "};\n\n"
       | RBufferOut n ->
           pr "struct %s_ret {\n" name;
           pr "  opaque %s<>;\n" n;
           pr "};\n\n"
      );
  ) daemon_functions;

  (* Table of procedure numbers. *)
  pr "enum guestfs_procedure {\n";
  List.iter (
    fun (shortname, _, proc_nr, _, _, _, _) ->
      pr "  GUESTFS_PROC_%s = %d,\n" (String.uppercase shortname) proc_nr
  ) daemon_functions;
  pr "  GUESTFS_PROC_NR_PROCS\n";
  pr "};\n";
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
/* The communication protocol is now documented in the guestfs(3)
 * manpage.
 */

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
  unsigned hyper progress_hint;      /* upload hint for progress bar */
  unsigned hyper optargs_bitmask;    /* bitmask for optional args */
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
 * (1) guestfs___recv_from_daemon assumes the XDR-encoded
 * structure is 24 bytes long.
 *
 * (2) daemon/proto.c:async_safe_send_pulse assumes the progress
 * message is laid out precisely in this way.  So if you change
 * this then you'd better change that function as well.
 */
struct guestfs_progress {
  guestfs_procedure proc;            /* @0:  GUESTFS_PROC_x */
  unsigned serial;                   /* @4:  message serial number */
  unsigned hyper position;           /* @8:  0 <= position <= total */
  unsigned hyper total;              /* @16: total size of operation */
                                     /* @24: size of structure */
};
"
