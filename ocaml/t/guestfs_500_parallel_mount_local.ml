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

(* Test guestfs_mount_local, from a higher level language (it will
 * mostly be used first from Python), in parallel threads.  OCaml
 * allows us to test this at a reasonable speed.
 *)

open Unix
open Printf

let (//) = Filename.concat

(* See [exit.c]. *)
external _exit : int -> 'a = "ocaml_guestfs__exit"

(* Some settings. *)
let total_time = 60.                 (* seconds, excluding launch *)
let debug = true                     (* overview debugging messages *)
let min_threads = 2
let max_threads = 12
let mbytes_per_thread = 900

let clip low high v = min high (max low v)

let rec main () =
  Random.self_init ();

  (* Choose the number of threads based on the amount of free memory. *)
  let nr_threads =
    let mbytes =
      let cmd = "LANG=C free -m | grep 'buffers/cache' | awk '{print $NF}'" in
      let chan = open_process_in cmd in
      let mbytes = input_line chan in
      match close_process_in chan with
      | WEXITED 0 -> Some (int_of_string mbytes)
      | _ -> None in
    match mbytes with
    | None -> min_threads (* default *)
    | Some mbytes ->
      clip min_threads max_threads (mbytes / mbytes_per_thread) in

  let threads = ref [] in
  for i = 1 to nr_threads do
    let filename = sprintf "test%d.img" i in
    let mp = sprintf "mp%d" i in
    (try rmdir mp with Unix_error _ -> ());
    mkdir mp 0o700;

    if debug then eprintf "%s : starting thread\n%!" mp;
    let t = Thread.create start_thread (filename, mp) in
    threads := (t, filename, mp) :: !threads
  done;

  (* Wait until the threads terminate and delete the files and mountpoints. *)
  List.iter (
    fun (t, filename, mp) ->
      Thread.join t;

      if debug then eprintf "%s : cleaning up thread\n%!" mp;
      unlink filename;
      rmdir mp
  ) !threads;

  Gc.compact ()

and start_thread (filename, mp) =
  (* Create a filesystem for the tests. *)
  let g = new Guestfs.guestfs () in

  let fd = openfile filename [O_WRONLY;O_CREAT;O_NOCTTY;O_TRUNC] 0o666 in
  ftruncate fd (500 * 1024 * 1024);
  close fd;

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
        with exn -> prerr_endline (Printexc.to_string exn); _exit 1
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
