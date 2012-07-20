(* libguestfs OCaml bindings
 * Copyright (C) 2012 Red Hat Inc.
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

(* Test guestfs_mount_local. *)

open Unix
open Printf

let (//) = Filename.concat

(* Some settings. *)
let total_time = 60.                 (* seconds, excluding launch *)
let debug = true                     (* overview debugging messages *)

let rec main () =
  Random.self_init ();

  let fuse_writable =
    try access "/dev/fuse" [W_OK]; true with Unix_error _ -> false in
  if not fuse_writable then (
    printf "%s: test skipped because /dev/fuse is not writable.\n"
      Sys.executable_name;
    exit 77
  );

  (* Allow the test to be skipped by setting this environment variable.
   * This is for RHEL 5, where FUSE doesn't work very reliably.
   *)
  let () =
    let name = "SKIP_TEST_GUESTFS_500_MOUNT_LOCAL_ML" in
    let value = try Sys.getenv name with Not_found -> "" in
    if value <> "" then (
      printf "%s: test skipped because %s is set.\n"
        Sys.executable_name name;
      exit 77
    )
  in

  let filename = "test1.img" in
  let fd = openfile filename [O_WRONLY;O_CREAT;O_NOCTTY;O_TRUNC] 0o666 in
  ftruncate fd (500 * 1024 * 1024);
  close fd;

  let mp = "mp" in
  (try rmdir mp with Unix_error _ -> ());
  mkdir mp 0o700;

  start_test filename mp;

  unlink filename;
  rmdir mp;

  Gc.compact ()

and start_test filename mp =
  (* Create a filesystem for the tests. *)
  let g = new Guestfs.guestfs () in

  g#add_drive_opts filename;
  g#launch ();

  g#part_disk "/dev/sda" "mbr";
  g#mkfs "ext2" "/dev/sda1";
  g#mount "/dev/sda1" "/";

  (* Randomly mount the filesystem and repeat.  Keep going until we
   * finish the test.
   *)
  let start_t = time () in
  let rec loop () =
    let t = time () in
    if t -. start_t < total_time then (
      if debug then eprintf "%s < mounting filesystem\n%!" mp;
      g#mount_local mp;

      (* Run test in an exec'd subprocess. *)
      let args = [| Sys.executable_name; "--test"; mp |] in
      let pid = fork () in
      if pid = 0 then (			(* child *)
        try execv Sys.executable_name args
        with exn -> prerr_endline (Printexc.to_string exn); exit 1
      );

      (* Run FUSE main loop.  This processes requests until the
       * subprocess unmounts the filesystem.
       *)
      g#mount_local_run ();

      let _, status = waitpid [] pid in
      (match status with
       | WEXITED 0 -> ()
       | WEXITED i ->
           eprintf "test subprocess failed (exit code %d)\n" i;
           exit 1
       | WSIGNALED i | WSTOPPED i ->
           eprintf "test subprocess signaled/stopped (signal %d)\n" i;
           exit 1
      );
      loop ()
    )
  in
  loop ();

  g#shutdown ();
  g#close ()

(* This is run in a child program. *)
and test_mountpoint mp =
  if debug then eprintf "%s | testing filesystem\n%!" mp;

  (* Run through the same set of tests repeatedly a number of times.
   * The aim of this stress test is repeated mount/unmount, not testing
   * FUSE itself, so we don't do much here.
   *)
  for pass = 0 to Random.int 32 do
    mkdir (mp // "tmp.d") 0o700;
    let chan = open_out (mp // "file") in
    let s = String.make (Random.int (128 * 1024)) (Char.chr (Random.int 256)) in
    output_string chan s;
    close_out chan;
    rename (mp // "tmp.d") (mp // "newdir");
    link (mp // "file") (mp // "newfile");
    if Random.int 32 = 0 then sleep 1;
    rmdir (mp // "newdir");
    unlink (mp // "file");
    unlink (mp // "newfile")
  done;

  if debug then eprintf "%s > unmounting filesystem\n%!" mp;

  unmount mp

(* We may need to retry this a few times because of processes which
 * run in the background jumping into mountpoints.  Only display
 * errors if it still fails after many retries.
 *)
and unmount mp =
  let logfile = sprintf "%s.fusermount.log" mp in
  let unlink_logfile () =
    try unlink logfile with Unix_error _ -> ()
  in
  unlink_logfile ();

  let run_command () =
    Sys.command (sprintf "fusermount -u %s >> %s 2>&1"
                   (Filename.quote mp) (Filename.quote logfile)) = 0
  in

  let rec loop tries =
    if tries <= 5 then (
      if not (run_command ()) then (
        sleep 1;
        loop (tries+1)
      )
    ) else (
      ignore (Sys.command (sprintf "cat %s" (Filename.quote logfile)));
      eprintf "fusermount: %s: failed, see earlier error messages\n" mp;
      exit 1
    )
  in
  loop 0;

  unlink_logfile ()

let () =
  match Array.to_list Sys.argv with
  | [ _; "--test"; mp ] -> test_mountpoint mp
  | [ _ ] -> main ()
  | _ ->
    eprintf "%s: unknown arguments given to program\n" Sys.executable_name;
    exit 1
