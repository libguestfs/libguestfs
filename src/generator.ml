#!/usr/bin/env ocaml
(* libguestfs
 * Copyright (C) 2009 Red Hat Inc.
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
 *
 * This script generates a large amount of code and documentation for
 * all the daemon actions.  To add a new action there are only two
 * files you need to change, this one to describe the interface, and
 * daemon/<somefile>.c to write the implementation.
 *)

#load "unix.cma";;

open Printf

type style = ret * args
and ret =
    (* "Err" as a return value means an int used as a simple error
     * indication, ie. 0 or -1.
     *)
  | Err
    (* "RString" and "RStringList" require special treatment because
     * the caller must free them.
     *)
  | RString of string
  | RStringList of string
    (* LVM PVs, VGs and LVs. *)
  | RPVList of string
  | RVGList of string
  | RLVList of string
and args =
    (* 0 arguments, 1 argument, etc. The guestfs_h param is implicit. *)
  | P0
  | P1 of argt
  | P2 of argt * argt
and argt =
  | String of string	(* const char *name, cannot be NULL *)

type flags = ProtocolLimitWarning

let functions = [
  ("mount", (Err, P2 (String "device", String "mountpoint")), 1, [],
   "mount a guest disk at a position in the filesystem",
   "\
Mount a guest disk at a position in the filesystem.  Block devices
are named C</dev/sda>, C</dev/sdb> and so on, as they were added to
the guest.  If those block devices contain partitions, they will have
the usual names (eg. C</dev/sda1>).  Also LVM C</dev/VG/LV>-style
names can be used.

The rules are the same as for L<mount(2)>:  A filesystem must
first be mounted on C</> before others can be mounted.  Other
filesystems can only be mounted on directories which already
exist.

The mounted filesystem is writable, if we have sufficient permissions
on the underlying device.

The filesystem options C<sync> and C<noatime> are set with this
call, in order to improve reliability.");

  ("sync", (Err, P0), 2, [],
   "sync disks, writes are flushed through to the disk image",
   "\
This syncs the disk, so that any writes are flushed through to the
underlying disk image.

You should always call this if you have modified a disk image, before
calling C<guestfs_close>.");

  ("touch", (Err, P1 (String "path")), 3, [],
   "update file timestamps or create a new file",
   "\
Touch acts like the L<touch(1)> command.  It can be used to
update the timestamps on a file, or, if the file does not exist,
to create a new zero-length file.");

  ("cat", (RString "content", P1 (String "path")), 4, [ProtocolLimitWarning],
   "list the contents of a file",
   "\
Return the contents of the file named C<path>.

Note that this function cannot correctly handle binary files
(specifically, files containing C<\\0> character which is treated
as end of string).  For those you need to use the C<guestfs_read_file>
function which has a more complex interface.");

  ("ll", (RString "listing", P1 (String "directory")), 5, [],
   "list the files in a directory (long format)",
   "\
List the files in C<directory> (relative to the root directory,
there is no cwd) in the format of 'ls -la'.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string.");

  ("ls", (RStringList "listing", P1 (String "directory")), 6, [],
   "list the files in a directory",
   "\
List the files in C<directory> (relative to the root directory,
there is no cwd).  The '.' and '..' entries are not returned, but
hidden files are shown.

This command is mostly useful for interactive sessions.  Programs
should probably use C<guestfs_readdir> instead.");

  ("list_devices", (RStringList "devices", P0), 7, [],
   "list the block devices",
   "\
List all the block devices.

The full block device names are returned, eg. C</dev/sda>
");

  ("list_partitions", (RStringList "partitions", P0), 8, [],
   "list the partitions",
   "\
List all the partitions detected on all block devices.

The full partition device names are returned, eg. C</dev/sda1>

This does not return logical volumes.  For that you will need to
call C<guestfs_lvs>.");

  ("pvs", (RStringList "physvols", P0), 9, [],
   "list the LVM physical volumes (PVs)",
   "\
List all the physical volumes detected.  This is the equivalent
of the L<pvs(8)> command.

This returns a list of just the device names that contain
PVs (eg. C</dev/sda2>).

See also C<guestfs_pvs_full>.");

  ("vgs", (RStringList "volgroups", P0), 10, [],
   "list the LVM volume groups (VGs)",
   "\
List all the volumes groups detected.  This is the equivalent
of the L<vgs(8)> command.

This returns a list of just the volume group names that were
detected (eg. C<VolGroup00>).

See also C<guestfs_vgs_full>.");

  ("lvs", (RStringList "logvols", P0), 11, [],
   "list the LVM logical volumes (LVs)",
   "\
List all the logical volumes detected.  This is the equivalent
of the L<lvs(8)> command.

This returns a list of the logical volume device names
(eg. C</dev/VolGroup00/LogVol00>).

See also C<guestfs_lvs_full>.");

  ("pvs_full", (RPVList "physvols", P0), 12, [],
   "list the LVM physical volumes (PVs)",
   "\
List all the physical volumes detected.  This is the equivalent
of the L<pvs(8)> command.  The \"full\" version includes all fields.");

  ("vgs_full", (RVGList "volgroups", P0), 13, [],
   "list the LVM volume groups (VGs)",
   "\
List all the volumes groups detected.  This is the equivalent
of the L<vgs(8)> command.  The \"full\" version includes all fields.");

  ("lvs_full", (RLVList "logvols", P0), 14, [],
   "list the LVM logical volumes (LVs)",
   "\
List all the logical volumes detected.  This is the equivalent
of the L<lvs(8)> command.  The \"full\" version includes all fields.");
]

(* Column names and types from LVM PVs/VGs/LVs. *)
let pv_cols = [
  "pv_name", `String;
  "pv_uuid", `UUID;
  "pv_fmt", `String;
  "pv_size", `Bytes;
  "dev_size", `Bytes;
  "pv_free", `Bytes;
  "pv_used", `Bytes;
  "pv_attr", `String (* XXX *);
  "pv_pe_count", `Int;
  "pv_pe_alloc_count", `Int;
  "pv_tags", `String;
  "pe_start", `Bytes;
  "pv_mda_count", `Int;
  "pv_mda_free", `Bytes;
(* Not in Fedora 10:
  "pv_mda_size", `Bytes;
*)
]
let vg_cols = [
  "vg_name", `String;
  "vg_uuid", `UUID;
  "vg_fmt", `String;
  "vg_attr", `String (* XXX *);
  "vg_size", `Bytes;
  "vg_free", `Bytes;
  "vg_sysid", `String;
  "vg_extent_size", `Bytes;
  "vg_extent_count", `Int;
  "vg_free_count", `Int;
  "max_lv", `Int;
  "max_pv", `Int;
  "pv_count", `Int;
  "lv_count", `Int;
  "snap_count", `Int;
  "vg_seqno", `Int;
  "vg_tags", `String;
  "vg_mda_count", `Int;
  "vg_mda_free", `Bytes;
(* Not in Fedora 10:
  "vg_mda_size", `Bytes;
*)
]
let lv_cols = [
  "lv_name", `String;
  "lv_uuid", `UUID;
  "lv_attr", `String (* XXX *);
  "lv_major", `Int;
  "lv_minor", `Int;
  "lv_kernel_major", `Int;
  "lv_kernel_minor", `Int;
  "lv_size", `Bytes;
  "seg_count", `Int;
  "origin", `String;
  "snap_percent", `OptPercent;
  "copy_percent", `OptPercent;
  "move_pv", `String;
  "lv_tags", `String;
  "mirror_log", `String;
  "modules", `String;
]

(* In some places we want the functions to be displayed sorted
 * alphabetically, so this is useful:
 *)
let sorted_functions =
  List.sort (fun (n1,_,_,_,_,_) (n2,_,_,_,_,_) -> compare n1 n2) functions

(* Useful functions. *)
let failwithf fs = ksprintf failwith fs
let replace s c1 c2 =
  let s2 = String.copy s in
  let r = ref false in
  for i = 0 to String.length s2 - 1 do
    if String.unsafe_get s2 i = c1 then (
      String.unsafe_set s2 i c2;
      r := true
    )
  done;
  if not !r then s else s2

(* 'pr' prints to the current output file. *)
let chan = ref stdout
let pr fs = ksprintf (output_string !chan) fs

let iter_args f = function
  | P0 -> ()
  | P1 arg1 -> f arg1
  | P2 (arg1, arg2) -> f arg1; f arg2

let iteri_args f = function
  | P0 -> ()
  | P1 arg1 -> f 0 arg1
  | P2 (arg1, arg2) -> f 0 arg1; f 1 arg2

let map_args f = function
  | P0 -> []
  | P1 arg1 -> [f arg1]
  | P2 (arg1, arg2) -> [f arg1; f arg2]

let nr_args = function | P0 -> 0 | P1 _ -> 1 | P2 _ -> 2

(* Check function names etc. for consistency. *)
let check_functions () =
  List.iter (
    fun (name, _, _, _, _, _) ->
      if String.contains name '-' then
	failwithf "Function name '%s' should not contain '-', use '_' instead."
	  name
  ) functions;

  let proc_nrs =
    List.map (fun (name, _, proc_nr, _, _, _) -> name, proc_nr) functions in
  let proc_nrs =
    List.sort (fun (_,nr1) (_,nr2) -> compare nr1 nr2) proc_nrs in
  let rec loop = function
    | [] -> ()
    | [_] -> ()
    | (name1,nr1) :: ((name2,nr2) :: _ as rest) when nr1 < nr2 ->
	loop rest
    | (name1,nr1) :: (name2,nr2) :: _ ->
	failwithf "'%s' and '%s' have conflicting procedure numbers (%d, %d)"
	  name1 name2 nr1 nr2
  in
  loop proc_nrs

type comment_style = CStyle | HashStyle | OCamlStyle
type license = GPLv2 | LGPLv2

(* Generate a header block in a number of standard styles. *)
let rec generate_header comment license =
  let c = match comment with
    | CStyle ->     pr "/* "; " *"
    | HashStyle ->  pr "# ";  "#"
    | OCamlStyle -> pr "(* "; " *" in
  pr "libguestfs generated file\n";
  pr "%s WARNING: THIS FILE IS GENERATED BY 'src/generator.ml'.\n" c;
  pr "%s ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.\n" c;
  pr "%s\n" c;
  pr "%s Copyright (C) 2009 Red Hat Inc.\n" c;
  pr "%s\n" c;
  (match license with
   | GPLv2 ->
       pr "%s This program is free software; you can redistribute it and/or modify\n" c;
       pr "%s it under the terms of the GNU General Public License as published by\n" c;
       pr "%s the Free Software Foundation; either version 2 of the License, or\n" c;
       pr "%s (at your option) any later version.\n" c;
       pr "%s\n" c;
       pr "%s This program is distributed in the hope that it will be useful,\n" c;
       pr "%s but WITHOUT ANY WARRANTY; without even the implied warranty of\n" c;
       pr "%s MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\n" c;
       pr "%s GNU General Public License for more details.\n" c;
       pr "%s\n" c;
       pr "%s You should have received a copy of the GNU General Public License along\n" c;
       pr "%s with this program; if not, write to the Free Software Foundation, Inc.,\n" c;
       pr "%s 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.\n" c;

   | LGPLv2 ->
       pr "%s This library is free software; you can redistribute it and/or\n" c;
       pr "%s modify it under the terms of the GNU Lesser General Public\n" c;
       pr "%s License as published by the Free Software Foundation; either\n" c;
       pr "%s version 2 of the License, or (at your option) any later version.\n" c;
       pr "%s\n" c;
       pr "%s This library is distributed in the hope that it will be useful,\n" c;
       pr "%s but WITHOUT ANY WARRANTY; without even the implied warranty of\n" c;
       pr "%s MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU\n" c;
       pr "%s Lesser General Public License for more details.\n" c;
       pr "%s\n" c;
       pr "%s You should have received a copy of the GNU Lesser General Public\n" c;
       pr "%s License along with this library; if not, write to the Free Software\n" c;
       pr "%s Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA\n" c;
  );
  (match comment with
   | CStyle -> pr " */\n"
   | HashStyle -> ()
   | OCamlStyle -> pr " *)\n"
  );
  pr "\n"

(* Generate the pod documentation for the C API. *)
and generate_actions_pod () =
  List.iter (
    fun (shortname, style, _, flags, _, longdesc) ->
      let name = "guestfs_" ^ shortname in
      pr "=head2 %s\n\n" name;
      pr " ";
      generate_prototype ~extern:false ~handle:"handle" name style;
      pr "\n\n";
      pr "%s\n\n" longdesc;
      (match fst style with
       | Err ->
	   pr "This function returns 0 on success or -1 on error.\n\n"
       | RString _ ->
	   pr "This function returns a string or NULL on error.
I<The caller must free the returned string after use>.\n\n"
       | RStringList _ ->
	   pr "This function returns a NULL-terminated array of strings
(like L<environ(3)>), or NULL if there was an error.
I<The caller must free the strings and the array after use>.\n\n"
       | RPVList _ ->
	   pr "This function returns a C<struct guestfs_lvm_pv_list>.
I<The caller must call C<guestfs_free_lvm_pv_list> after use.>.\n\n"
       | RVGList _ ->
	   pr "This function returns a C<struct guestfs_lvm_vg_list>.
I<The caller must call C<guestfs_free_lvm_vg_list> after use.>.\n\n"
       | RLVList _ ->
	   pr "This function returns a C<struct guestfs_lvm_lv_list>.
I<The caller must call C<guestfs_free_lvm_lv_list> after use.>.\n\n"
      );
      if List.mem ProtocolLimitWarning flags then
	pr "Because of the message protocol, there is a transfer limit 
of somewhere between 2MB and 4MB.  To transfer large files you should use
FTP.\n\n";
  ) sorted_functions

and generate_structs_pod () =
  (* LVM structs documentation. *)
  List.iter (
    fun (typ, cols) ->
      pr "=head2 guestfs_lvm_%s\n" typ;
      pr "\n";
      pr " struct guestfs_lvm_%s {\n" typ;
      List.iter (
	function
	| name, `String -> pr "  char *%s;\n" name
	| name, `UUID ->
	    pr "  /* The next field is NOT nul-terminated, be careful when printing it: */\n";
	    pr "  char %s[32];\n" name
	| name, `Bytes -> pr "  uint64_t %s;\n" name
	| name, `Int -> pr "  int64_t %s;\n" name
	| name, `OptPercent ->
	    pr "  /* The next field is [0..100] or -1 meaning 'not present': */\n";
	    pr "  float %s;\n" name
      ) cols;
      pr " \n";
      pr " struct guestfs_lvm_%s_list {\n" typ;
      pr "   uint32_t len; /* Number of elements in list. */\n";
      pr "   struct guestfs_lvm_%s *val; /* Elements. */\n" typ;
      pr " };\n";
      pr " \n";
      pr " void guestfs_free_lvm_%s_list (struct guestfs_free_lvm_%s_list *);\n"
	typ typ;
      pr "\n"
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols]

(* Generate the protocol (XDR) file, 'guestfs_protocol.x' and
 * indirectly 'guestfs_protocol.h' and 'guestfs_protocol.c'.  We
 * have to use an underscore instead of a dash because otherwise
 * rpcgen generates incorrect code.
 *
 * This header is NOT exported to clients, but see also generate_structs_h.
 *)
and generate_xdr () =
  generate_header CStyle LGPLv2;

  (* This has to be defined to get around a limitation in Sun's rpcgen. *)
  pr "typedef string str<>;\n";
  pr "\n";

  (* LVM internal structures. *)
  List.iter (
    function
    | typ, cols ->
	pr "struct guestfs_lvm_int_%s {\n" typ;
	List.iter (function
		   | name, `String -> pr "  string %s<>;\n" name
		   | name, `UUID -> pr "  opaque %s[32];\n" name
		   | name, `Bytes -> pr "  hyper %s;\n" name
		   | name, `Int -> pr "  hyper %s;\n" name
		   | name, `OptPercent -> pr "  float %s;\n" name
		  ) cols;
	pr "};\n";
	pr "\n";
	pr "typedef struct guestfs_lvm_int_%s guestfs_lvm_int_%s_list<>;\n" typ typ;
	pr "\n";
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols];

  List.iter (
    fun (shortname, style, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in
      pr "/* %s */\n\n" name;
      (match snd style with
       | P0 -> ()
       | args ->
	   pr "struct %s_args {\n" name;
	   iter_args (
	     function
	     | String name -> pr "  string %s<>;\n" name
	   ) args;
	   pr "};\n\n"
      );
      (match fst style with
       | Err -> () 
       | RString n ->
	   pr "struct %s_ret {\n" name;
	   pr "  string %s<>;\n" n;
	   pr "};\n\n"
       | RStringList n ->
	   pr "struct %s_ret {\n" name;
	   pr "  str %s<>;\n" n;
	   pr "};\n\n"
       | RPVList n ->
	   pr "struct %s_ret {\n" name;
	   pr "  guestfs_lvm_int_pv_list %s;\n" n;
	   pr "};\n\n"
       | RVGList n ->
	   pr "struct %s_ret {\n" name;
	   pr "  guestfs_lvm_int_vg_list %s;\n" n;
	   pr "};\n\n"
       | RLVList n ->
	   pr "struct %s_ret {\n" name;
	   pr "  guestfs_lvm_int_lv_list %s;\n" n;
	   pr "};\n\n"
      );
  ) functions;

  (* Table of procedure numbers. *)
  pr "enum guestfs_procedure {\n";
  List.iter (
    fun (shortname, _, proc_nr, _, _, _) ->
      pr "  GUESTFS_PROC_%s = %d,\n" (String.uppercase shortname) proc_nr
  ) functions;
  pr "  GUESTFS_PROC_dummy\n"; (* so we don't have a "hanging comma" *)
  pr "};\n";
  pr "\n";

  (* Having to choose a maximum message size is annoying for several
   * reasons (it limits what we can do in the API), but it (a) makes
   * the protocol a lot simpler, and (b) provides a bound on the size
   * of the daemon which operates in limited memory space.  For large
   * file transfers you should use FTP.
   *)
  pr "const GUESTFS_MESSAGE_MAX = %d;\n" (4 * 1024 * 1024);
  pr "\n";

  (* Message header, etc. *)
  pr "\
const GUESTFS_PROGRAM = 0x2000F5F5;
const GUESTFS_PROTOCOL_VERSION = 1;

enum guestfs_message_direction {
  GUESTFS_DIRECTION_CALL = 0,        /* client -> daemon */
  GUESTFS_DIRECTION_REPLY = 1        /* daemon -> client */
};

enum guestfs_message_status {
  GUESTFS_STATUS_OK = 0,
  GUESTFS_STATUS_ERROR = 1
};

const GUESTFS_ERROR_LEN = 256;

struct guestfs_message_error {
  string error<GUESTFS_ERROR_LEN>;   /* error message */
};

struct guestfs_message_header {
  unsigned prog;                     /* GUESTFS_PROGRAM */
  unsigned vers;                     /* GUESTFS_PROTOCOL_VERSION */
  guestfs_procedure proc;            /* GUESTFS_PROC_x */
  guestfs_message_direction direction;
  unsigned serial;                   /* message serial number */
  guestfs_message_status status;
};
"

(* Generate the guestfs-structs.h file. *)
and generate_structs_h () =
  generate_header CStyle LGPLv2;

  (* This is a public exported header file containing various
   * structures.  The structures are carefully written to have
   * exactly the same in-memory format as the XDR structures that
   * we use on the wire to the daemon.  The reason for creating
   * copies of these structures here is just so we don't have to
   * export the whole of guestfs_protocol.h (which includes much
   * unrelated and XDR-dependent stuff that we don't want to be
   * public, or required by clients).
   *
   * To reiterate, we will pass these structures to and from the
   * client with a simple assignment or memcpy, so the format
   * must be identical to what rpcgen / the RFC defines.
   *)

  (* LVM public structures. *)
  List.iter (
    function
    | typ, cols ->
	pr "struct guestfs_lvm_%s {\n" typ;
	List.iter (
	  function
	  | name, `String -> pr "  char *%s;\n" name
	  | name, `UUID -> pr "  char %s[32]; /* this is NOT nul-terminated, be careful when printing */\n" name
	  | name, `Bytes -> pr "  uint64_t %s;\n" name
	  | name, `Int -> pr "  int64_t %s;\n" name
	  | name, `OptPercent -> pr "  float %s; /* [0..100] or -1 */\n" name
	) cols;
	pr "};\n";
	pr "\n";
	pr "struct guestfs_lvm_%s_list {\n" typ;
	pr "  uint32_t len;\n";
	pr "  struct guestfs_lvm_%s *val;\n" typ;
	pr "};\n";
	pr "\n"
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols]

(* Generate the guestfs-actions.h file. *)
and generate_actions_h () =
  generate_header CStyle LGPLv2;
  List.iter (
    fun (shortname, style, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in
      generate_prototype ~single_line:true ~newline:true ~handle:"handle"
	name style
  ) functions

(* Generate the client-side dispatch stubs. *)
and generate_client_actions () =
  generate_header CStyle LGPLv2;

  (* Client-side stubs for each function. *)
  List.iter (
    fun (shortname, style, _, _, _, _) ->
      let name = "guestfs_" ^ shortname in

      (* Generate the return value struct. *)
      pr "struct %s_rv {\n" shortname;
      pr "  int cb_done;  /* flag to indicate callback was called */\n";
      pr "  struct guestfs_message_header hdr;\n";
      pr "  struct guestfs_message_error err;\n";
      (match fst style with
       | Err -> ()
       | RString _ | RStringList _ | RPVList _ | RVGList _ | RLVList _ ->
	   pr "  struct %s_ret ret;\n" name
      );
      pr "};\n\n";

      (* Generate the callback function. *)
      pr "static void %s_cb (guestfs_h *g, void *data, XDR *xdr)\n" shortname;
      pr "{\n";
      pr "  struct %s_rv *rv = (struct %s_rv *) data;\n" shortname shortname;
      pr "\n";
      pr "  if (!xdr_guestfs_message_header (xdr, &rv->hdr)) {\n";
      pr "    error (g, \"%s: failed to parse reply header\");\n" name;
      pr "    return;\n";
      pr "  }\n";
      pr "  if (rv->hdr.status == GUESTFS_STATUS_ERROR) {\n";
      pr "    if (!xdr_guestfs_message_error (xdr, &rv->err)) {\n";
      pr "      error (g, \"%s: failed to parse reply error\");\n" name;
      pr "      return;\n";
      pr "    }\n";
      pr "    goto done;\n";
      pr "  }\n";

      (match fst style with
       | Err -> ()
       | RString _ | RStringList _ | RPVList _ | RVGList _ | RLVList _ ->
	    pr "  if (!xdr_%s_ret (xdr, &rv->ret)) {\n" name;
	    pr "    error (g, \"%s: failed to parse reply\");\n" name;
	    pr "    return;\n";
	    pr "  }\n";
      );

      pr " done:\n";
      pr "  rv->cb_done = 1;\n";
      pr "  main_loop.main_loop_quit (g);\n";
      pr "}\n\n";

      (* Generate the action stub. *)
      generate_prototype ~extern:false ~semicolon:false ~newline:true
	~handle:"g" name style;

      let error_code =
	match fst style with
	| Err -> "-1"
	| RString _ | RStringList _ | RPVList _ | RVGList _ | RLVList _ ->
	    "NULL" in

      pr "{\n";

      (match snd style with
       | P0 -> ()
       | _ -> pr "  struct %s_args args;\n" name
      );

      pr "  struct %s_rv rv;\n" shortname;
      pr "  int serial;\n";
      pr "\n";
      pr "  if (g->state != READY) {\n";
      pr "    error (g, \"%s called from the wrong state, %%d != READY\",\n"
	name;
      pr "      g->state);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";
      pr "  memset (&rv, 0, sizeof rv);\n";
      pr "\n";

      (match snd style with
       | P0 ->
	   pr "  serial = dispatch (g, GUESTFS_PROC_%s, NULL, NULL);\n"
	     (String.uppercase shortname)
       | args ->
	   iter_args (
	     function
	     | String name -> pr "  args.%s = (char *) %s;\n" name name
	   ) args;
	   pr "  serial = dispatch (g, GUESTFS_PROC_%s,\n"
	     (String.uppercase shortname);
	   pr "                     (xdrproc_t) xdr_%s_args, (char *) &args);\n"
	     name;
      );
      pr "  if (serial == -1)\n";
      pr "    return %s;\n" error_code;
      pr "\n";

      pr "  rv.cb_done = 0;\n";
      pr "  g->reply_cb_internal = %s_cb;\n" shortname;
      pr "  g->reply_cb_internal_data = &rv;\n";
      pr "  main_loop.main_loop_run (g);\n";
      pr "  g->reply_cb_internal = NULL;\n";
      pr "  g->reply_cb_internal_data = NULL;\n";
      pr "  if (!rv.cb_done) {\n";
      pr "    error (g, \"%s failed, see earlier error messages\");\n" name;
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      pr "  if (check_reply_header (g, &rv.hdr, GUESTFS_PROC_%s, serial) == -1)\n"
	(String.uppercase shortname);
      pr "    return %s;\n" error_code;
      pr "\n";

      pr "  if (rv.hdr.status == GUESTFS_STATUS_ERROR) {\n";
      pr "    error (g, \"%%s\", rv.err.error);\n";
      pr "    return %s;\n" error_code;
      pr "  }\n";
      pr "\n";

      (match fst style with
       | Err -> pr "  return 0;\n"
       | RString n ->
	   pr "  return rv.ret.%s; /* caller will free */\n" n
       | RStringList n ->
	   pr "  /* caller will free this, but we need to add a NULL entry */\n";
	   pr "  rv.ret.%s.%s_val =" n n;
	   pr "    safe_realloc (g, rv.ret.%s.%s_val,\n" n n;
	   pr "                  sizeof (char *) * (rv.ret.%s.%s_len + 1));\n"
	     n n;
	   pr "  rv.ret.%s.%s_val[rv.ret.%s.%s_len] = NULL;\n" n n n n;
	   pr "  return rv.ret.%s.%s_val;\n" n n
       | RPVList n ->
	   pr "  /* caller will free this */\n";
	   pr "  return safe_memdup (g, &rv.ret.%s, sizeof (rv.ret.%s));\n" n n
       | RVGList n ->
	   pr "  /* caller will free this */\n";
	   pr "  return safe_memdup (g, &rv.ret.%s, sizeof (rv.ret.%s));\n" n n
       | RLVList n ->
	   pr "  /* caller will free this */\n";
	   pr "  return safe_memdup (g, &rv.ret.%s, sizeof (rv.ret.%s));\n" n n
      );

      pr "}\n\n"
  ) functions

(* Generate daemon/actions.h. *)
and generate_daemon_actions_h () =
  generate_header CStyle GPLv2;

  pr "#include \"../src/guestfs_protocol.h\"\n";
  pr "\n";

  List.iter (
    fun (name, style, _, _, _, _) ->
      generate_prototype
	~single_line:true ~newline:true ~in_daemon:true ("do_" ^ name) style;
  ) functions

(* Generate the server-side stubs. *)
and generate_daemon_actions () =
  generate_header CStyle GPLv2;

  pr "#define _GNU_SOURCE // for strchrnul\n";
  pr "\n";
  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "#include <inttypes.h>\n";
  pr "#include <ctype.h>\n";
  pr "#include <rpc/types.h>\n";
  pr "#include <rpc/xdr.h>\n";
  pr "\n";
  pr "#include \"daemon.h\"\n";
  pr "#include \"../src/guestfs_protocol.h\"\n";
  pr "#include \"actions.h\"\n";
  pr "\n";

  List.iter (
    fun (name, style, _, _, _, _) ->
      (* Generate server-side stubs. *)
      pr "static void %s_stub (XDR *xdr_in)\n" name;
      pr "{\n";
      let error_code =
	match fst style with
	| Err -> pr "  int r;\n"; "-1"
	| RString _ -> pr "  char *r;\n"; "NULL"
	| RStringList _ -> pr "  char **r;\n"; "NULL"
	| RPVList _ -> pr "  guestfs_lvm_int_pv_list *r;\n"; "NULL"
	| RVGList _ -> pr "  guestfs_lvm_int_vg_list *r;\n"; "NULL"
	| RLVList _ -> pr "  guestfs_lvm_int_lv_list *r;\n"; "NULL" in

      (match snd style with
       | P0 -> ()
       | args ->
	   pr "  struct guestfs_%s_args args;\n" name;
	   iter_args (
	     function
	     | String name -> pr "  const char *%s;\n" name
	   ) args
      );
      pr "\n";

      (match snd style with
       | P0 -> ()
       | args ->
	   pr "  memset (&args, 0, sizeof args);\n";
	   pr "\n";
	   pr "  if (!xdr_guestfs_%s_args (xdr_in, &args)) {\n" name;
	   pr "    reply_with_error (\"%s: daemon failed to decode procedure arguments\");\n" name;
	   pr "    return;\n";
	   pr "  }\n";
	   iter_args (
	     function
	     | String name -> pr "  %s = args.%s;\n" name name
	   ) args;
	   pr "\n"
      );

      pr "  r = do_%s " name;
      generate_call_args style;
      pr ";\n";

      pr "  if (r == %s)\n" error_code;
      pr "    /* do_%s has already called reply_with_error, so just return */\n" name;
      pr "    return;\n";
      pr "\n";

      (match fst style with
       | Err -> pr "  reply (NULL, NULL);\n"
       | RString n ->
	   pr "  struct guestfs_%s_ret ret;\n" name;
	   pr "  ret.%s = r;\n" n;
	   pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n" name;
	   pr "  free (r);\n"
       | RStringList n ->
	   pr "  struct guestfs_%s_ret ret;\n" name;
	   pr "  ret.%s.%s_len = count_strings (r);\n" n n;
	   pr "  ret.%s.%s_val = r;\n" n n;
	   pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n" name;
	   pr "  free_strings (r);\n"
       | RPVList n ->
	   pr "  struct guestfs_%s_ret ret;\n" name;
	   pr "  ret.%s = *r;\n" n;
	   pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n" name;
	   pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n" name
       | RVGList n ->
	   pr "  struct guestfs_%s_ret ret;\n" name;
	   pr "  ret.%s = *r;\n" n;
	   pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n" name;
	   pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n" name
       | RLVList n ->
	   pr "  struct guestfs_%s_ret ret;\n" name;
	   pr "  ret.%s = *r;\n" n;
	   pr "  reply ((xdrproc_t) &xdr_guestfs_%s_ret, (char *) &ret);\n" name;
	   pr "  xdr_free ((xdrproc_t) xdr_guestfs_%s_ret, (char *) &ret);\n" name
      );

      pr "}\n\n";
  ) functions;

  (* Dispatch function. *)
  pr "void dispatch_incoming_message (XDR *xdr_in)\n";
  pr "{\n";
  pr "  switch (proc_nr) {\n";

  List.iter (
    fun (name, style, _, _, _, _) ->
      pr "    case GUESTFS_PROC_%s:\n" (String.uppercase name);
      pr "      %s_stub (xdr_in);\n" name;
      pr "      break;\n"
  ) functions;

  pr "    default:\n";
  pr "      reply_with_error (\"dispatch_incoming_message: unknown procedure number %%d\", proc_nr);\n";
  pr "  }\n";
  pr "}\n";
  pr "\n";

  (* LVM columns and tokenization functions. *)
  (* XXX This generates crap code.  We should rethink how we
   * do this parsing.
   *)
  List.iter (
    function
    | typ, cols ->
	pr "static const char *lvm_%s_cols = \"%s\";\n"
	  typ (String.concat "," (List.map fst cols));
	pr "\n";

	pr "static int lvm_tokenize_%s (char *str, struct guestfs_lvm_int_%s *r)\n" typ typ;
	pr "{\n";
	pr "  char *tok, *p, *next;\n";
	pr "  int i, j;\n";
	pr "\n";
	(*
	pr "  fprintf (stderr, \"%%s: <<%%s>>\\n\", __func__, str);\n";
	pr "\n";
	*)
	pr "  if (!str) {\n";
	pr "    fprintf (stderr, \"%%s: failed: passed a NULL string\\n\", __func__);\n";
	pr "    return -1;\n";
	pr "  }\n";
	pr "  if (!*str || isspace (*str)) {\n";
	pr "    fprintf (stderr, \"%%s: failed: passed a empty string or one beginning with whitespace\\n\", __func__);\n";
	pr "    return -1;\n";
	pr "  }\n";
	pr "  tok = str;\n";
	List.iter (
	  fun (name, coltype) ->
	    pr "  if (!tok) {\n";
	    pr "    fprintf (stderr, \"%%s: failed: string finished early, around token %%s\\n\", __func__, \"%s\");\n" name;
	    pr "    return -1;\n";
	    pr "  }\n";
	    pr "  p = strchrnul (tok, ',');\n";
	    pr "  if (*p) next = p+1; else next = NULL;\n";
	    pr "  *p = '\\0';\n";
	    (match coltype with
	     | `String ->
		 pr "  r->%s = strdup (tok);\n" name;
		 pr "  if (r->%s == NULL) {\n" name;
		 pr "    perror (\"strdup\");\n";
		 pr "    return -1;\n";
		 pr "  }\n"
	     | `UUID ->
		 pr "  for (i = j = 0; i < 32; ++j) {\n";
		 pr "    if (tok[j] == '\\0') {\n";
		 pr "      fprintf (stderr, \"%%s: failed to parse UUID from '%%s'\\n\", __func__, tok);\n";
		 pr "      return -1;\n";
		 pr "    } else if (tok[j] != '-')\n";
		 pr "      r->%s[i++] = tok[j];\n" name;
		 pr "  }\n";
	     | `Bytes ->
		 pr "  if (sscanf (tok, \"%%\"SCNu64, &r->%s) != 1) {\n" name;
		 pr "    fprintf (stderr, \"%%s: failed to parse size '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
		 pr "    return -1;\n";
		 pr "  }\n";
	     | `Int ->
		 pr "  if (sscanf (tok, \"%%\"SCNi64, &r->%s) != 1) {\n" name;
		 pr "    fprintf (stderr, \"%%s: failed to parse int '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
		 pr "    return -1;\n";
		 pr "  }\n";
	     | `OptPercent ->
		 pr "  if (tok[0] == '\\0')\n";
		 pr "    r->%s = -1;\n" name;
		 pr "  else if (sscanf (tok, \"%%f\", &r->%s) != 1) {\n" name;
		 pr "    fprintf (stderr, \"%%s: failed to parse float '%%s' from token %%s\\n\", __func__, tok, \"%s\");\n" name;
		 pr "    return -1;\n";
		 pr "  }\n";
	    );
	    pr "  tok = next;\n";
	) cols;

	pr "  if (tok != NULL) {\n";
	pr "    fprintf (stderr, \"%%s: failed: extra tokens at end of string\\n\", __func__);\n";
	pr "    return -1;\n";
	pr "  }\n";
	pr "  return 0;\n";
	pr "}\n";
	pr "\n";

	pr "guestfs_lvm_int_%s_list *\n" typ;
	pr "parse_command_line_%ss (void)\n" typ;
	pr "{\n";
	pr "  char *out, *err;\n";
	pr "  char *p, *pend;\n";
	pr "  int r, i;\n";
	pr "  guestfs_lvm_int_%s_list *ret;\n" typ;
	pr "  void *newp;\n";
	pr "\n";
	pr "  ret = malloc (sizeof *ret);\n";
	pr "  if (!ret) {\n";
	pr "    reply_with_perror (\"malloc\");\n";
	pr "    return NULL;\n";
	pr "  }\n";
	pr "\n";
	pr "  ret->guestfs_lvm_int_%s_list_len = 0;\n" typ;
	pr "  ret->guestfs_lvm_int_%s_list_val = NULL;\n" typ;
	pr "\n";
	pr "  r = command (&out, &err,\n";
	pr "	       \"/sbin/lvm\", \"%ss\",\n" typ;
	pr "	       \"-o\", lvm_%s_cols, \"--unbuffered\", \"--noheadings\",\n" typ;
	pr "	       \"--nosuffix\", \"--separator\", \",\", \"--units\", \"b\", NULL);\n";
	pr "  if (r == -1) {\n";
	pr "    reply_with_error (\"%%s\", err);\n";
	pr "    free (out);\n";
	pr "    free (err);\n";
	pr "    return NULL;\n";
	pr "  }\n";
	pr "\n";
	pr "  free (err);\n";
	pr "\n";
	pr "  /* Tokenize each line of the output. */\n";
	pr "  p = out;\n";
	pr "  i = 0;\n";
	pr "  while (p) {\n";
	pr "    pend = strchr (p, '\\n');	/* Get the next line of output. */\n";
	pr "    if (pend) {\n";
	pr "      *pend = '\\0';\n";
	pr "      pend++;\n";
	pr "    }\n";
	pr "\n";
	pr "    while (*p && isspace (*p))	/* Skip any leading whitespace. */\n";
	pr "      p++;\n";
	pr "\n";
	pr "    if (!*p) {			/* Empty line?  Skip it. */\n";
	pr "      p = pend;\n";
	pr "      continue;\n";
	pr "    }\n";
	pr "\n";
	pr "    /* Allocate some space to store this next entry. */\n";
	pr "    newp = realloc (ret->guestfs_lvm_int_%s_list_val,\n" typ;
	pr "		    sizeof (guestfs_lvm_int_%s) * (i+1));\n" typ;
	pr "    if (newp == NULL) {\n";
	pr "      reply_with_perror (\"realloc\");\n";
	pr "      free (ret->guestfs_lvm_int_%s_list_val);\n" typ;
	pr "      free (ret);\n";
	pr "      free (out);\n";
	pr "      return NULL;\n";
	pr "    }\n";
	pr "    ret->guestfs_lvm_int_%s_list_val = newp;\n" typ;
	pr "\n";
	pr "    /* Tokenize the next entry. */\n";
	pr "    r = lvm_tokenize_%s (p, &ret->guestfs_lvm_int_%s_list_val[i]);\n" typ typ;
	pr "    if (r == -1) {\n";
	pr "      reply_with_error (\"failed to parse output of '%ss' command\");\n" typ;
        pr "      free (ret->guestfs_lvm_int_%s_list_val);\n" typ;
        pr "      free (ret);\n";
	pr "      free (out);\n";
	pr "      return NULL;\n";
	pr "    }\n";
	pr "\n";
	pr "    ++i;\n";
	pr "    p = pend;\n";
	pr "  }\n";
	pr "\n";
	pr "  ret->guestfs_lvm_int_%s_list_len = i;\n" typ;
	pr "\n";
	pr "  free (out);\n";
	pr "  return ret;\n";
	pr "}\n"

  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols]

(* Generate a lot of different functions for guestfish. *)
and generate_fish_cmds () =
  generate_header CStyle GPLv2;

  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "#include <string.h>\n";
  pr "#include <inttypes.h>\n";
  pr "\n";
  pr "#include <guestfs.h>\n";
  pr "#include \"fish.h\"\n";
  pr "\n";

  (* list_commands function, which implements guestfish -h *)
  pr "void list_commands (void)\n";
  pr "{\n";
  pr "  printf (\"    %%-16s     %%s\\n\", \"Command\", \"Description\");\n";
  pr "  list_builtin_commands ();\n";
  List.iter (
    fun (name, _, _, _, shortdesc, _) ->
      let name = replace name '_' '-' in
      pr "  printf (\"%%-20s %%s\\n\", \"%s\", \"%s\");\n"
	name shortdesc
  ) sorted_functions;
  pr "  printf (\"    Use -h <cmd> / help <cmd> to show detailed help for a command.\\n\");\n";
  pr "}\n";
  pr "\n";

  (* display_command function, which implements guestfish -h cmd *)
  pr "void display_command (const char *cmd)\n";
  pr "{\n";
  List.iter (
    fun (name, style, _, flags, shortdesc, longdesc) ->
      let name2 = replace name '_' '-' in
      let synopsis =
	match snd style with
	| P0 -> name2
	| args ->
	    sprintf "%s <%s>"
	      name2 (
		String.concat "> <" (
		  map_args (function
			    | String n -> n) args
		)
	      ) in

      let warnings =
	if List.mem ProtocolLimitWarning flags then
	  "\n\nBecause of the message protocol, there is a transfer limit 
of somewhere between 2MB and 4MB.  To transfer large files you should use
FTP."
	else "" in

      pr "  if (";
      pr "strcasecmp (cmd, \"%s\") == 0" name;
      if name <> name2 then
	pr " || strcasecmp (cmd, \"%s\") == 0" name2;
      pr ")\n";
      pr "    pod2text (\"%s - %s\", %S);\n"
	name2 shortdesc
	(" " ^ synopsis ^ "\n\n" ^ longdesc ^ warnings);
      pr "  else\n"
  ) functions;
  pr "    display_builtin_command (cmd);\n";
  pr "}\n";
  pr "\n";

  (* print_{pv,vg,lv}_list functions *)
  List.iter (
    function
    | typ, cols ->
	pr "static void print_%s (struct guestfs_lvm_%s *%s)\n" typ typ typ;
	pr "{\n";
	pr "  int i;\n";
	pr "\n";
	List.iter (
	  function
	  | name, `String ->
	      pr "  printf (\"%s: %%s\\n\", %s->%s);\n" name typ name
	  | name, `UUID ->
	      pr "  printf (\"%s: \");\n" name;
	      pr "  for (i = 0; i < 32; ++i)\n";
	      pr "    printf (\"%%c\", %s->%s[i]);\n" typ name;
	      pr "  printf (\"\\n\");\n"
	  | name, `Bytes ->
	      pr "  printf (\"%s: %%\" PRIu64 \"\\n\", %s->%s);\n" name typ name
	  | name, `Int ->
	      pr "  printf (\"%s: %%\" PRIi64 \"\\n\", %s->%s);\n" name typ name
	  | name, `OptPercent ->
	      pr "  if (%s->%s >= 0) printf (\"%s: %%g %%%%\\n\", %s->%s);\n"
		typ name name typ name;
	      pr "  else printf (\"%s: \\n\");\n" name
	) cols;
	pr "}\n";
	pr "\n";
	pr "static void print_%s_list (struct guestfs_lvm_%s_list *%ss)\n"
	  typ typ typ;
	pr "{\n";
	pr "  int i;\n";
	pr "\n";
	pr "  for (i = 0; i < %ss->len; ++i)\n" typ;
	pr "    print_%s (&%ss->val[i]);\n" typ typ;
	pr "}\n";
	pr "\n";
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols];

  (* run_<action> actions *)
  List.iter (
    fun (name, style, _, _, _, _) ->
      pr "static int run_%s (const char *cmd, int argc, char *argv[])\n" name;
      pr "{\n";
      (match fst style with
       | Err -> pr "  int r;\n"
       | RString _ -> pr "  char *r;\n"
       | RStringList _ -> pr "  char **r;\n"
       | RPVList _ -> pr "  struct guestfs_lvm_pv_list *r;\n"
       | RVGList _ -> pr "  struct guestfs_lvm_vg_list *r;\n"
       | RLVList _ -> pr "  struct guestfs_lvm_lv_list *r;\n"
      );
      iter_args (
	function
	| String name -> pr "  const char *%s;\n" name
      ) (snd style);

      (* Check and convert parameters. *)
      let argc_expected = nr_args (snd style) in
      pr "  if (argc != %d) {\n" argc_expected;
      pr "    fprintf (stderr, \"%%s should have %d parameter(s)\\n\", cmd);\n"
	argc_expected;
      pr "    fprintf (stderr, \"type 'help %%s' for help on %%s\\n\", cmd, cmd);\n";
      pr "    return -1;\n";
      pr "  }\n";
      iteri_args (
	fun i ->
	  function
	  | String name -> pr "  %s = argv[%d];\n" name i
      ) (snd style);

      (* Call C API function. *)
      pr "  r = guestfs_%s " name;
      generate_call_args ~handle:"g" style;
      pr ";\n";

      (* Check return value for errors and display command results. *)
      (match fst style with
       | Err -> pr "  return r;\n"
       | RString _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  printf (\"%%s\", r);\n";
	   pr "  free (r);\n";
	   pr "  return 0;\n"
       | RStringList _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_strings (r);\n";
	   pr "  free_strings (r);\n";
	   pr "  return 0;\n"
       | RPVList _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_pv_list (r);\n";
	   pr "  guestfs_free_lvm_pv_list (r);\n";
	   pr "  return 0;\n"
       | RVGList _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_vg_list (r);\n";
	   pr "  guestfs_free_lvm_vg_list (r);\n";
	   pr "  return 0;\n"
       | RLVList _ ->
	   pr "  if (r == NULL) return -1;\n";
	   pr "  print_lv_list (r);\n";
	   pr "  guestfs_free_lvm_lv_list (r);\n";
	   pr "  return 0;\n"
      );
      pr "}\n";
      pr "\n"
  ) functions;

  (* run_action function *)
  pr "int run_action (const char *cmd, int argc, char *argv[])\n";
  pr "{\n";
  List.iter (
    fun (name, _, _, _, _, _) ->
      let name2 = replace name '_' '-' in
      pr "  if (";
      pr "strcasecmp (cmd, \"%s\") == 0" name;
      if name <> name2 then
	pr " || strcasecmp (cmd, \"%s\") == 0" name2;
      pr ")\n";
      pr "    return run_%s (cmd, argc, argv);\n" name;
      pr "  else\n";
  ) functions;
  pr "    {\n";
  pr "      fprintf (stderr, \"%%s: unknown command\\n\", cmd);\n";
  pr "      return -1;\n";
  pr "    }\n";
  pr "  return 0;\n";
  pr "}\n";
  pr "\n"

(* Generate the POD documentation for guestfish. *)
and generate_fish_actions_pod () =
  List.iter (
    fun (name, style, _, _, _, longdesc) ->
      let name = replace name '_' '-' in
      pr "=head2 %s\n\n" name;
      pr " %s" name;
      iter_args (
	function
	| String n -> pr " %s" n
      ) (snd style);
      pr "\n";
      pr "\n";
      pr "%s\n\n" longdesc
  ) sorted_functions

(* Generate a C function prototype. *)
and generate_prototype ?(extern = true) ?(static = false) ?(semicolon = true)
    ?(single_line = false) ?(newline = false) ?(in_daemon = false)
    ?handle name style =
  if extern then pr "extern ";
  if static then pr "static ";
  (match fst style with
   | Err -> pr "int "
   | RString _ -> pr "char *"
   | RStringList _ -> pr "char **"
   | RPVList _ ->
       if not in_daemon then pr "struct guestfs_lvm_pv_list *"
       else pr "guestfs_lvm_int_pv_list *"
   | RVGList _ ->
       if not in_daemon then pr "struct guestfs_lvm_vg_list *"
       else pr "guestfs_lvm_int_vg_list *"
   | RLVList _ ->
       if not in_daemon then pr "struct guestfs_lvm_lv_list *"
       else pr "guestfs_lvm_int_lv_list *"
  );
  pr "%s (" name;
  let comma = ref false in
  (match handle with
   | None -> ()
   | Some handle -> pr "guestfs_h *%s" handle; comma := true
  );
  let next () =
    if !comma then (
      if single_line then pr ", " else pr ",\n\t\t"
    );
    comma := true
  in
  iter_args (
    function
    | String name -> next (); pr "const char *%s" name
  ) (snd style);
  pr ")";
  if semicolon then pr ";";
  if newline then pr "\n"

(* Generate C call arguments, eg "(handle, foo, bar)" *)
and generate_call_args ?handle style =
  pr "(";
  let comma = ref false in
  (match handle with
   | None -> ()
   | Some handle -> pr "%s" handle; comma := true
  );
  iter_args (
    fun arg ->
      if !comma then pr ", ";
      comma := true;
      match arg with
      | String name -> pr "%s" name
  ) (snd style);
  pr ")"

(* Generate the OCaml bindings interface. *)
and generate_ocaml_mli () =
  generate_header OCamlStyle LGPLv2;

  pr "\
(** For API documentation you should refer to the C API
    in the guestfs(3) manual page.  The OCaml API uses almost
    exactly the same calls. *)

type t
(** A [guestfs_h] handle. *)

exception Error of string
(** This exception is raised when there is an error. *)

val create : unit -> t

val close : t -> unit
(** Handles are closed by the garbage collector when they become
    unreferenced, but callers can also call this in order to
    provide predictable cleanup. *)

val launch : t -> unit
val wait_ready : t -> unit
val kill_subprocess : t -> unit

val add_drive : t -> string -> unit
val add_cdrom : t -> string -> unit
val config : t -> string -> string option -> unit

val set_path : t -> string option -> unit
val get_path : t -> string
val set_autosync : t -> bool -> unit
val get_autosync : t -> bool
val set_verbose : t -> bool -> unit
val get_verbose : t -> bool

";
  generate_ocaml_lvm_structure_decls ();

  (* The actions. *)
  List.iter (
    fun (name, style, _, _, shortdesc, _) ->
      generate_ocaml_prototype name style;
      pr "(** %s *)\n" shortdesc;
      pr "\n"
  ) sorted_functions

(* Generate the OCaml bindings implementation. *)
and generate_ocaml_ml () =
  generate_header OCamlStyle LGPLv2;

  pr "\
type t
exception Error of string
external create : unit -> t = \"ocaml_guestfs_create\"
external close : t -> unit = \"ocaml_guestfs_create\"
external launch : t -> unit = \"ocaml_guestfs_launch\"
external wait_ready : t -> unit = \"ocaml_guestfs_wait_ready\"
external kill_subprocess : t -> unit = \"ocaml_guestfs_kill_subprocess\"
external add_drive : t -> string -> unit = \"ocaml_guestfs_add_drive\"
external add_cdrom : t -> string -> unit = \"ocaml_guestfs_add_cdrom\"
external config : t -> string -> string option -> unit = \"ocaml_guestfs_config\"
external set_path : t -> string option -> unit = \"ocaml_guestfs_set_path\"
external get_path : t -> string = \"ocaml_guestfs_get_path\"
external set_autosync : t -> bool -> unit = \"ocaml_guestfs_set_autosync\"
external get_autosync : t -> bool = \"ocaml_guestfs_get_autosync\"
external set_verbose : t -> bool -> unit = \"ocaml_guestfs_set_verbose\"
external get_verbose : t -> bool = \"ocaml_guestfs_get_verbose\"

";
  generate_ocaml_lvm_structure_decls ();

  (* The actions. *)
  List.iter (
    fun (name, style, _, _, shortdesc, _) ->
      generate_ocaml_prototype ~is_external:true name style;
  ) sorted_functions

(* Generate the OCaml bindings C implementation. *)
and generate_ocaml_c () =
  generate_header CStyle LGPLv2;

  pr "#include <stdio.h>\n";
  pr "#include <stdlib.h>\n";
  pr "\n";
  pr "#include <guestfs.h>\n";
  pr "\n";
  pr "#include <caml/config.h>\n";
  pr "#include <caml/alloc.h>\n";
  pr "#include <caml/callback.h>\n";
  pr "#include <caml/fail.h>\n";
  pr "#include <caml/memory.h>\n";
  pr "#include <caml/mlvalues.h>\n";
  pr "\n";
  pr "#include \"guestfs_c.h\"\n";
  pr "\n";

  List.iter (
    fun (name, style, _, _, _, _) ->
      pr "CAMLprim value\n";
      pr "ocaml_guestfs_%s (value hv /* XXX */)\n" name;
      pr "{\n";
      pr "  CAMLparam1 (hv); /* XXX */\n";
      pr "/* XXX write something here */\n";
      pr "  CAMLreturn (Val_unit); /* XXX */\n";
      pr "}\n";
      pr "\n"
  ) sorted_functions

and generate_ocaml_lvm_structure_decls () =
  List.iter (
    fun (typ, cols) ->
      pr "type lvm_%s = {\n" typ;
      List.iter (
	function
	| name, `String -> pr "  %s : string;\n" name
	| name, `UUID -> pr "  %s : string;\n" name
	| name, `Bytes -> pr "  %s : int64;\n" name
	| name, `Int -> pr "  %s : int64;\n" name
	| name, `OptPercent -> pr "  %s : float option;\n" name
      ) cols;
      pr "}\n";
      pr "\n"
  ) ["pv", pv_cols; "vg", vg_cols; "lv", lv_cols]

and generate_ocaml_prototype ?(is_external = false) name style =
  if is_external then pr "external " else pr "val ";
  pr "%s : t -> " name;
  iter_args (
    function
    | String _ -> pr "string -> " (* note String is not allowed to be NULL *)
  ) (snd style);
  (match fst style with
   | Err -> pr "unit" (* all errors are turned into exceptions *)
   | RString _ -> pr "string"
   | RStringList _ -> pr "string list"
   | RPVList _ -> pr "lvm_pv list"
   | RVGList _ -> pr "lvm_vg list"
   | RLVList _ -> pr "lvm_lv list"
  );
  if is_external then pr " = \"ocaml_guestfs_%s\"" name;
  pr "\n"

let output_to filename =
  let filename_new = filename ^ ".new" in
  chan := open_out filename_new;
  let close () =
    close_out !chan;
    chan := stdout;
    Unix.rename filename_new filename;
    printf "written %s\n%!" filename;
  in
  close

(* Main program. *)
let () =
  check_functions ();

  let close = output_to "src/guestfs_protocol.x" in
  generate_xdr ();
  close ();

  let close = output_to "src/guestfs-structs.h" in
  generate_structs_h ();
  close ();

  let close = output_to "src/guestfs-actions.h" in
  generate_actions_h ();
  close ();

  let close = output_to "src/guestfs-actions.c" in
  generate_client_actions ();
  close ();

  let close = output_to "daemon/actions.h" in
  generate_daemon_actions_h ();
  close ();

  let close = output_to "daemon/stubs.c" in
  generate_daemon_actions ();
  close ();

  let close = output_to "fish/cmds.c" in
  generate_fish_cmds ();
  close ();

  let close = output_to "guestfs-structs.pod" in
  generate_structs_pod ();
  close ();

  let close = output_to "guestfs-actions.pod" in
  generate_actions_pod ();
  close ();

  let close = output_to "guestfish-actions.pod" in
  generate_fish_actions_pod ();
  close ();

  let close = output_to "ocaml/guestfs.mli" in
  generate_ocaml_mli ();
  close ();

  let close = output_to "ocaml/guestfs.ml" in
  generate_ocaml_ml ();
  close ();

  let close = output_to "ocaml/guestfs_c_actions.c" in
  generate_ocaml_c ();
  close ();
