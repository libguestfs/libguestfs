(* libguestfs
 * Copyright (C) 2009-2010 Red Hat Inc.
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

open Unix
open Printf

open Generator_pr
open Generator_structs

open Generator_c
open Generator_xdr
open Generator_daemon
open Generator_capitests
open Generator_fish
open Generator_ocaml
open Generator_perl
open Generator_python
open Generator_ruby
open Generator_java
open Generator_haskell
open Generator_csharp
open Generator_php
open Generator_bindtests

let perror msg = function
  | Unix_error (err, _, _) ->
      eprintf "%s: %s\n" msg (error_message err)
  | exn ->
      eprintf "%s: %s\n" msg (Printexc.to_string exn)

(* Main program. *)
let () =
  let lock_fd =
    try openfile "HACKING" [O_RDWR] 0
    with
    | Unix_error (ENOENT, _, _) ->
        eprintf "\
You are probably running this from the wrong directory.
Run it from the top source directory using the command
  make -C generator stamp-generator
";
        exit 1
    | exn ->
        perror "open: HACKING" exn;
        exit 1 in

  (* Acquire a lock so parallel builds won't try to run the generator
   * twice at the same time.  Subsequent builds will wait for the first
   * one to finish.  Note the lock is released implicitly when the
   * program exits.
   *)
  (try lockf lock_fd F_LOCK 1
   with exn ->
     perror "lock: HACKING" exn;
     exit 1);

  output_to "src/guestfs_protocol.x" generate_xdr;
  output_to "src/guestfs-structs.h" generate_structs_h;
  output_to "src/guestfs-actions.h" generate_actions_h;
  output_to "src/guestfs-internal-actions.h" generate_internal_actions_h;
  output_to "src/actions.c" generate_client_actions;
  output_to "src/bindtests.c" generate_bindtests;
  output_to "src/guestfs-structs.pod" generate_structs_pod;
  output_to "src/guestfs-actions.pod" generate_actions_pod;
  output_to "src/guestfs-availability.pod" generate_availability_pod;
  output_to "src/MAX_PROC_NR" generate_max_proc_nr;
  output_to "src/libguestfs.syms" generate_linker_script;
  output_to "daemon/actions.h" generate_daemon_actions_h;
  output_to "daemon/stubs.c" generate_daemon_actions;
  output_to "daemon/names.c" generate_daemon_names;
  output_to "daemon/optgroups.c" generate_daemon_optgroups_c;
  output_to "daemon/optgroups.h" generate_daemon_optgroups_h;
  output_to "capitests/tests.c" generate_tests;
  output_to "fish/cmds.c" generate_fish_cmds;
  output_to "fish/completion.c" generate_fish_completion;
  output_to "fish/guestfish-actions.pod" generate_fish_actions_pod;
  output_to "fish/prepopts.c" generate_fish_prep_options_c;
  output_to "fish/prepopts.h" generate_fish_prep_options_h;
  output_to "ocaml/guestfs.mli" generate_ocaml_mli;
  output_to "ocaml/guestfs.ml" generate_ocaml_ml;
  output_to "ocaml/guestfs_c_actions.c" generate_ocaml_c;
  output_to "ocaml/bindtests.ml" generate_ocaml_bindtests;
  output_to "perl/Guestfs.xs" generate_perl_xs;
  output_to "perl/lib/Sys/Guestfs.pm" generate_perl_pm;
  output_to "perl/bindtests.pl" generate_perl_bindtests;
  output_to "python/guestfs-py.c" generate_python_c;
  output_to "python/guestfs.py" generate_python_py;
  output_to "python/bindtests.py" generate_python_bindtests;
  output_to "ruby/ext/guestfs/_guestfs.c" generate_ruby_c;
  output_to "ruby/bindtests.rb" generate_ruby_bindtests;
  output_to "java/com/redhat/et/libguestfs/GuestFS.java" generate_java_java;

  List.iter (
    fun (typ, jtyp) ->
      let cols = cols_of_struct typ in
      let filename = sprintf "java/com/redhat/et/libguestfs/%s.java" jtyp in
      output_to filename (generate_java_struct jtyp cols);
  ) java_structs;

  output_to "java/Makefile.inc" generate_java_makefile_inc;
  output_to "java/com_redhat_et_libguestfs_GuestFS.c" generate_java_c;
  output_to "java/Bindtests.java" generate_java_bindtests;
  output_to "haskell/Guestfs.hs" generate_haskell_hs;
  output_to "haskell/Bindtests.hs" generate_haskell_bindtests;
  output_to "csharp/Libguestfs.cs" generate_csharp;
  output_to "php/extension/php_guestfs_php.h" generate_php_h;
  output_to "php/extension/guestfs_php.c" generate_php_c;

  (* Always generate this file last, and unconditionally.  It's used
   * by the Makefile to know when we must re-run the generator.
   *)
  let chan = open_out "generator/stamp-generator" in
  fprintf chan "1\n";
  close_out chan;

  printf "generated %d lines of code\n" (get_lines_generated ())
