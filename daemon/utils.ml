(* guestfs-inspection
 * Copyright (C) 2009-2017 Red Hat Inc.
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

open Unix
open Printf

open Std_utils

external get_verbose_flag : unit -> bool = "guestfs_int_daemon_get_verbose_flag" "noalloc"
external is_device_parameter : string -> bool = "guestfs_int_daemon_is_device_parameter" "noalloc"
external is_root_device : string -> bool = "guestfs_int_daemon_is_root_device" "noalloc"
external prog_exists : string -> bool = "guestfs_int_daemon_prog_exists" "noalloc"
external udev_settle : ?filename:string -> unit -> unit = "guestfs_int_daemon_udev_settle" "noalloc"

let commandr ?(fold_stdout_on_stderr = false) prog args =
  if verbose () then
    eprintf "command:%s %s\n%!"
            (if fold_stdout_on_stderr then " fold-stdout-on-stderr" else "")
            (stringify_args (prog :: args));

  let argv = Array.of_list (prog :: args) in

  let stdin_fd = openfile "/dev/null" [O_RDONLY] 0 in
  let stdout_file, stdout_fd =
    let filename, chan = Filename.open_temp_file "cmd" ".out" in
    filename, descr_of_out_channel chan in
  let stderr_file, stderr_fd =
    let filename, chan = Filename.open_temp_file "cmd" ".err" in
    filename, descr_of_out_channel chan in

  let pid = fork () in
  if pid = 0 then (
    (* Child process. *)
    dup2 stdin_fd stdin;
    close stdin_fd;
    if not fold_stdout_on_stderr then
      dup2 stdout_fd stdout
    else
      dup2 stderr_fd stdout;
    close stdout_fd;
    dup2 stderr_fd stderr;
    close stderr_fd;

    execvp prog argv
  );

  (* Parent process. *)
  close stdin_fd;
  close stdout_fd;
  close stderr_fd;
  let _, status = waitpid [] pid in
  let r =
    match status with
    | WEXITED i -> i
    | WSIGNALED i ->
       failwithf "external command ‘%s’ killed by signal %d" prog i
    | WSTOPPED i ->
       failwithf "external command ‘%s’ stopped by signal %d" prog i in

  if verbose () then
    eprintf "command: %s returned %d\n" prog r;

  let stdout = read_whole_file stdout_file in
  let stderr = read_whole_file stderr_file in

  (try unlink stdout_file with _ -> ());
  (try unlink stderr_file with _ -> ());

  if verbose () then (
    if stdout <> "" then (
      eprintf "command: %s: stdout:\n%s%!" prog stdout;
      if not (String.is_suffix stdout "\n") then eprintf "\n%!"
    );
    if stderr <> "" then (
      eprintf "command: %s: stderr:\n%s%!" prog stderr;
      if not (String.is_suffix stderr "\n") then eprintf "\n%!"
    )
  );

  (* Strip trailing \n from stderr but NOT from stdout. *)
  let stderr = String.chomp stderr in

  (r, stdout, stderr)

let command ?fold_stdout_on_stderr prog args =
  let r, stdout, stderr = commandr ?fold_stdout_on_stderr prog args in
  if r <> 0 then
    failwithf "%s exited with status %d: %s" prog r stderr;
  stdout

(* XXX This function is copied from C, but is misconceived.  It
 * cannot by design work for devices like /dev/md0.  It would be
 * better if it checked for the existence of devices and partitions
 * in /sys/block so we know what the kernel thinks is a device or
 * partition.  The same applies to APIs such as part_to_partnum
 * and part_to_dev which rely on this function.
 *)
let split_device_partition dev =
  (* Skip /dev/ prefix if present. *)
  let dev =
    if String.is_prefix dev "/dev/" then
      String.sub dev 5 (String.length dev - 5)
    else dev in

  (* Find the partition number (if present). *)
  let dev, part =
    let n = String.length dev in
    let i = ref n in
    while !i >= 1 && Char.isdigit dev.[!i-1] do
      decr i
    done;
    let i = !i in
    if i = n then
      dev, 0 (* no partition number, whole device *)
    else
      String.sub dev 0 i, int_of_string (String.sub dev i (n-i)) in

  (* Deal with device names like /dev/md0p1. *)
  (* XXX This function is buggy (as was the old C function) when
   * presented with a whole device like /dev/md0.
   *)
  let dev =
    let n = String.length dev in
    if n < 2 || dev.[n-1] <> 'p' || not (Char.isdigit dev.[n-2]) then
      dev
    else (
      let i = ref (n-1) in
      while !i >= 0 && Char.isdigit dev.[!i] do
        decr i;
      done;
      let i = !i in
      String.sub dev 0 i
    ) in

  dev, part

let rec sort_device_names devs =
  List.sort compare_device_names devs

and compare_device_names a b =
  (* This takes the device name like "/dev/sda1" and returns ("sda", 1). *)
  let dev_a, part_a = split_device_partition a
  and dev_b, part_b = split_device_partition b in

  (* Skip "sd|hd|ubd..." so that /dev/sda and /dev/vda sort together.
   * (This is what the old C function did, but it's not clear if it
   * is still relevant. XXX)
   *)
  let skip_prefix dev =
    let n = String.length dev in
    if n >= 2 && dev.[1] = 'd' then
      String.sub dev 2 (String.length dev - 2)
    else if n >= 3 && dev.[2] = 'd' then
      String.sub dev 3 (String.length dev - 3)
    else
      dev in
  let dev_a = skip_prefix dev_a
  and dev_b = skip_prefix dev_b in

  (* If device name part is longer, it is always greater, eg.
   * "/dev/sdz" < "/dev/sdaa".
   *)
  let r = compare (String.length dev_a) (String.length dev_b) in
  if r <> 0 then r
  else (
    (* Device name parts are the same length, so do a regular compare. *)
    let r = compare dev_a dev_b in
    if r <> 0 then r
    else (
      (* Device names are identical, so compare partition numbers. *)
      compare part_a part_b
    )
  )

let proc_unmangle_path path =
  let n = String.length path in
  let b = Buffer.create n in
  let rec loop i =
    if i < n-3 && path.[i] = '\\' then (
      let to_int c = Char.code c - Char.code '0' in
      let v =
        (to_int path.[i+1] lsl 6) lor
        (to_int path.[i+2] lsl 3) lor
        to_int path.[i+3] in
      Buffer.add_char b (Char.chr v);
      loop (i+4)
    )
    else if i < n then (
      Buffer.add_char b path.[i];
      loop (i+1)
    )
    else
      Buffer.contents b
  in
  loop 0

let is_small_file path =
  is_regular_file path &&
    (stat path).st_size <= 2 * 1048 * 1024

let read_small_file filename =
  if not (is_small_file filename) then (
    eprintf "%s: not a regular file or too large\n" filename;
    None
  )
  else (
    let content = read_whole_file filename in
    let lines = String.nsplit "\n" content in
    Some lines
  )

let unix_canonical_path path =
  let is_absolute = String.length path > 0 && path.[0] = '/' in
  let path = String.nsplit "/" path in
  let path = List.filter ((<>) "") path in
  (if is_absolute then "/" else "") ^ String.concat "/" path
