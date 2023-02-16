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

open Unix
open Printf

open Std_utils
open Pr
open Actions
open Structs
open Types

let perror msg = function
  | Unix_error (err, _, _) ->
      eprintf "%s: %s\n" msg (error_message err)
  | exn ->
      eprintf "%s: %s\n" msg (Printexc.to_string exn)

(* In some directories the actions are split across this many C
 * files.  You can increase this number in order to reduce the number
 * of lines in each file (hence making compilation faster), but you
 * also have to modify .../Makefile.am.
 *)
let nr_actions_files = 7
let actions_subsets =
  let h i { name } = i = Hashtbl.hash name mod nr_actions_files in
  Array.init nr_actions_files (fun i -> List.filter (h i) actions)
let output_to_subset fs f =
  for i = 0 to nr_actions_files-1 do
    ksprintf (fun filename -> output_to filename (f actions_subsets.(i))) fs i
  done

(* Main program. *)
let () =
  let lock_fd =
    try openfile "podwrapper.pl.in" [O_RDWR] 0
    with
    | Unix_error (ENOENT, _, _) ->
        eprintf "\
You are probably running this from the wrong directory.
Run it from the top source directory using the command
  make -C generator stamp-generator
";
        exit 1
    | exn ->
        perror "open: podwrapper.pl.in" exn;
        exit 1 in

  (* Acquire a lock so parallel builds won't try to run the generator
   * twice at the same time.  Subsequent builds will wait for the first
   * one to finish.  Note the lock is released implicitly when the
   * program exits.
   *)
  (try lockf lock_fd F_LOCK 1
   with exn ->
     perror "lock: podwrapper.pl.in" exn;
     exit 1);

  output_to "AUTHORS"
            Authors.generate_authors;

  output_to "common/errnostring/errnostring-gperf.gperf"
            Errnostring.generate_errnostring_gperf;
  output_to "common/errnostring/errnostring.c"
            Errnostring.generate_errnostring_c;
  output_to "common/errnostring/errnostring.h"
            Errnostring.generate_errnostring_h;
  output_to "common/protocol/guestfs_protocol.x"
            XDR.generate_xdr;
  output_to "common/structs/structs-cleanups.h"
            C.generate_client_structs_cleanups_h;
  output_to "common/structs/structs-cleanups.c"
            C.generate_client_structs_cleanups_c;
  output_to "common/structs/structs-print.c"
            C.generate_client_structs_print_c;
  output_to "common/structs/structs-print.h"
            C.generate_client_structs_print_h;
  output_to "lib/uefi.c"
            UEFI.generate_uefi_c;
  output_to "include/guestfs.h"
            C.generate_guestfs_h;
  output_to "lib/guestfs-internal-actions.h"
            C.generate_internal_actions_h;
  output_to "lib/bindtests.c"
            Bindtests.generate_bindtests;
  output_to "lib/guestfs-structs.pod"
            C.generate_structs_pod;
  output_to "lib/guestfs-actions.pod"
            C.generate_actions_pod;
  output_to "lib/guestfs-availability.pod"
            C.generate_availability_pod;
  output_to "lib/event-string.c"
            C.generate_event_string_c;
  output_to "lib/MAX_PROC_NR"
            C.generate_max_proc_nr;
  output_to "lib/libguestfs.syms"
            C.generate_linker_script;
  output_to "lib/structs-compare.c"
            C.generate_client_structs_compare;
  output_to "lib/structs-copy.c"
            C.generate_client_structs_copy;
  output_to "lib/structs-free.c"
            C.generate_client_structs_free;
  output_to "lib/actions-variants.c"
            C.generate_client_actions_variants;
  output_to_subset "lib/actions-%d.c"
                   C.generate_client_actions;
  output_to "tests/c-api/tests.c"
            Tests_c_api.generate_c_api_tests;

  output_to "daemon/actions.h"
            Daemon.generate_daemon_actions_h;
  output_to "daemon/stubs.h"
            Daemon.generate_daemon_stubs_h;
  output_to_subset "daemon/stubs-%d.c"
                   Daemon.generate_daemon_stubs;
  output_to "daemon/caml-stubs.c"
            Daemon.generate_daemon_caml_stubs;
  output_to "daemon/callbacks.ml"
            Daemon.generate_daemon_caml_callbacks_ml;
  output_to "daemon/dispatch.c"
            Daemon.generate_daemon_dispatch;
  output_to "daemon/names.c"
            Daemon.generate_daemon_names;
  output_to "daemon/optgroups.c"
            Daemon.generate_daemon_optgroups_c;
  output_to "daemon/optgroups.h"
            Daemon.generate_daemon_optgroups_h;
  output_to "daemon/optgroups.ml"
            Daemon.generate_daemon_optgroups_ml;
  output_to "daemon/optgroups.mli"
            Daemon.generate_daemon_optgroups_mli;
  output_to "daemon/lvm-tokenization.c"
            Daemon.generate_daemon_lvm_tokenization;
  output_to "daemon/structs-cleanups.c"
            Daemon.generate_daemon_structs_cleanups_c;
  output_to "daemon/structs-cleanups.h"
            Daemon.generate_daemon_structs_cleanups_h;
  let daemon_ocaml_interfaces =
    List.fold_left (
      fun set { impl } ->
        let ocaml_function =
          match impl with
          | OCaml f -> fst (String.split "." f)
          | C -> assert false in

        StringSet.add ocaml_function set
    ) StringSet.empty (actions |> impl_ocaml_functions) in
  StringSet.iter (
    fun modname ->
      let fn = Char.escaped (Char.lowercase_ascii (String.unsafe_get modname 0)) ^
               String.sub modname 1 (String.length modname - 1) in
      output_to (sprintf "daemon/%s.mli" fn)
                (Daemon.generate_daemon_caml_interface modname)
  ) daemon_ocaml_interfaces;

  output_to "fish/cmds-gperf.gperf"
            Fish.generate_fish_cmds_gperf;
  output_to "fish/cmds.c"
            Fish.generate_fish_cmds;
  output_to_subset "fish/entries-%d.c"
                   Fish.generate_fish_cmd_entries;
  output_to_subset "fish/run-%d.c"
                   Fish.generate_fish_run_cmds;
  output_to "fish/run.h"
            Fish.generate_fish_run_header;
  output_to "fish/completion.c"
            Fish.generate_fish_completion;
  output_to "fish/event-names.c"
            Fish.generate_fish_event_names;
  output_to "fish/fish-cmds.h"
            Fish.generate_fish_cmds_h;
  output_to "fish/guestfish-commands.pod"
            Fish.generate_fish_commands_pod;
  output_to "fish/guestfish-actions.pod"
            Fish.generate_fish_actions_pod;
  output_to "fish/prepopts.c"
            Fish.generate_fish_prep_options_c;
  output_to "fish/prepopts.h"
            Fish.generate_fish_prep_options_h;
  output_to "fish/guestfish-prepopts.pod"
            Fish.generate_fish_prep_options_pod;
  output_to ~perm:0o555 "fish/test-prep.sh"
            Fish.generate_fish_test_prep_sh;

  output_to "ocaml/guestfs.mli"
            OCaml.generate_ocaml_mli;
  output_to "ocaml/guestfs.ml"
            OCaml.generate_ocaml_ml;
  output_to "ocaml/guestfs-c-actions.c"
            OCaml.generate_ocaml_c;
  output_to "ocaml/guestfs-c-errnos.c"
            OCaml.generate_ocaml_c_errnos;
  output_to "daemon/structs.ml"
            OCaml.generate_ocaml_daemon_structs;
  output_to "daemon/structs.mli"
            OCaml.generate_ocaml_daemon_structs;
  output_to "ocaml/bindtests.ml"
            Bindtests.generate_ocaml_bindtests;

  output_to "perl/lib/Sys/Guestfs.xs"
            Perl.generate_perl_xs;
  output_to "perl/lib/Sys/Guestfs.pm"
            Perl.generate_perl_pm;
  output_to "perl/bindtests.pl"
            Bindtests.generate_perl_bindtests;

  output_to "python/actions.h"
            Python.generate_python_actions_h;
  output_to_subset "python/actions-%d.c"
                   Python.generate_python_actions;
  output_to "python/module.c"
            Python.generate_python_module;
  output_to "python/structs.c"
            Python.generate_python_structs;
  output_to "python/guestfs.py"
            Python.generate_python_py;
  output_to "python/bindtests.py"
            Bindtests.generate_python_bindtests;

  output_to "ruby/ext/guestfs/actions.h"
            Ruby.generate_ruby_h;
  output_to_subset "ruby/ext/guestfs/actions-%d.c"
                   Ruby.generate_ruby_c;
  output_to "ruby/ext/guestfs/module.c"
            Ruby.generate_ruby_module;
  output_to "ruby/bindtests.rb"
            Bindtests.generate_ruby_bindtests;

  output_to "java/com/redhat/et/libguestfs/GuestFS.java"
            Java.generate_java_java;
  List.iter (
    fun { s_name = typ; s_camel_name = jtyp } ->
      let cols = cols_of_struct typ in
      let filename = sprintf "java/com/redhat/et/libguestfs/%s.java" jtyp in
      output_to filename (Java.generate_java_struct jtyp cols)
  ) external_structs;
  delete_except_generated
    ~skip:["java/com/redhat/et/libguestfs/LibGuestFSException.java";
           "java/com/redhat/et/libguestfs/LibGuestFSOutOfMemory.java";
           "java/com/redhat/et/libguestfs/EventCallback.java"]
    "java/com/redhat/et/libguestfs/*.java";
  output_to "java/Makefile.inc"
            Java.generate_java_makefile_inc;
  output_to_subset "java/actions-%d.c"
                   Java.generate_java_c;
  output_to "java/com/redhat/et/libguestfs/.gitignore"
            Java.generate_java_gitignore;
  output_to "java/Bindtests.java"
            Bindtests.generate_java_bindtests;

  output_to "haskell/Guestfs.hs"
            Haskell.generate_haskell_hs;
  output_to "haskell/Bindtests.hs"
            Bindtests.generate_haskell_bindtests;

  output_to "csharp/Libguestfs.cs"
            Csharp.generate_csharp;

  output_to "php/extension/php_guestfs_php.h"
            Php.generate_php_h;
  output_to "php/extension/guestfs_php.c"
            Php.generate_php_c;
  output_to "php/extension/tests/guestfs_090_bindtests.phpt"
            Bindtests.generate_php_bindtests;

  output_to "erlang/guestfs.erl"
            Erlang.generate_erlang_erl;
  output_to "erlang/actions.h"
            Erlang.generate_erlang_actions_h;
  output_to_subset "erlang/actions-%d.c"
                   Erlang.generate_erlang_actions;
  output_to "erlang/dispatch.c"
            Erlang.generate_erlang_dispatch;
  output_to "erlang/structs.c"
            Erlang.generate_erlang_structs;
  output_to ~perm:0o555 "erlang/bindtests.erl"
            Bindtests.generate_erlang_bindtests;

  output_to "lua/lua-guestfs.c"
            Lua.generate_lua_c;
  output_to "lua/bindtests.lua"
            Bindtests.generate_lua_bindtests;

  output_to "golang/src/libguestfs.org/guestfs/guestfs.go"
            Golang.generate_golang_go;
  output_to "golang/bindtests/bindtests.go"
            Bindtests.generate_golang_bindtests;

  output_to "gobject/bindtests.js"
            Bindtests.generate_gobject_js_bindtests;
  output_to "gobject/Makefile.inc"
            GObject.generate_gobject_makefile;
  output_to "gobject/include/guestfs-gobject.h"
            GObject.generate_gobject_header;
  List.iter (
    fun { s_name = typ; s_cols = cols } ->
      let short = sprintf "struct-%s" typ in
      let filename =
        sprintf "gobject/include/guestfs-gobject/%s.h" short in
      output_to filename
                (GObject.generate_gobject_struct_header short typ cols);
      let filename = sprintf "gobject/src/%s.c" short in
      output_to filename
                (GObject.generate_gobject_struct_source short typ)
  ) external_structs;
  delete_except_generated "gobject/include/guestfs-gobject/struct-*.h";
  delete_except_generated "gobject/src/struct-*.c";
  List.iter (
    function
    | ({ name; style = (_, _, (_::_ as optargs)) } as f) ->
      let short = sprintf "optargs-%s" name in
      let filename =
        sprintf "gobject/include/guestfs-gobject/%s.h" short in
      output_to filename
                (GObject.generate_gobject_optargs_header short name f);
      let filename = sprintf "gobject/src/%s.c" short in
      output_to filename
                (GObject.generate_gobject_optargs_source short name optargs f)
    | { style = _, _, [] } -> ()
  ) (actions |> external_functions |> sort);
  delete_except_generated "gobject/include/guestfs-gobject/optargs-*.h";
  delete_except_generated "gobject/src/optargs-*.c";
  output_to "gobject/include/guestfs-gobject/tristate.h"
            GObject.generate_gobject_tristate_header;
  output_to "gobject/src/tristate.c"
            GObject.generate_gobject_tristate_source;
  output_to "gobject/include/guestfs-gobject/session.h"
            GObject.generate_gobject_session_header;
  output_to "gobject/src/session.c"
            GObject.generate_gobject_session_source;

  (* mlv2v may not be shipped in this source. *)
  if is_regular_file "common/mlv2v/Makefile.am" then (
    output_to "common/mlv2v/uefi.ml"
              UEFI.generate_uefi_ml;
    output_to "common/mlv2v/uefi.mli"
              UEFI.generate_uefi_mli;
  );

  (* mlcustomize may not be shipped in this source. *)
  if is_regular_file "common/mlcustomize/Makefile.am" then (
    output_to "common/mlcustomize/customize_cmdline.mli"
              Customize.generate_customize_cmdline_mli;
    output_to "common/mlcustomize/customize_cmdline.ml"
              Customize.generate_customize_cmdline_ml;
    output_to "common/mlcustomize/customize-synopsis.pod"
              Customize.generate_customize_synopsis_pod;
    output_to "common/mlcustomize/customize-options.pod"
              Customize.generate_customize_options_pod
  );

  output_to "rust/src/guestfs.rs"
            Rust.generate_rust;
  output_to "rust/src/bin/bindtests.rs"
            Bindtests.generate_rust_bindtests;

  (* Generate the list of files generated -- last. *)
  printf "generated %d lines of code\n" (get_lines_generated ());
  let files = List.sort compare (get_files_generated ()) in
  output_to "generator/files-generated.txt"
    (fun () -> List.iter (pr "%s\n") files)
