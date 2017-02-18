(* libguestfs
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

open Common_utils
open Types
open Utils

(* non_daemon_functions are any functions which don't get processed
 * in the daemon, eg. functions for setting and getting local
 * configuration values.
 *)

let non_daemon_functions =
  Actions_internal_tests.test_functions @
  Actions_internal_tests.test_support_functions @
  Actions_core.non_daemon_functions @
  Actions_core_deprecated.non_daemon_functions @
  Actions_debug.non_daemon_functions @
  Actions_hivex.non_daemon_functions @
  Actions_inspection.non_daemon_functions @
  Actions_inspection_deprecated.non_daemon_functions @
  Actions_properties.non_daemon_functions @
  Actions_properties_deprecated.non_daemon_functions @
  Actions_tsk.non_daemon_functions

(* daemon_functions are any functions which cause some action
 * to take place in the daemon.
 *)

let daemon_functions =
  Actions_augeas.daemon_functions @
  Actions_core.daemon_functions @
  Actions_core_deprecated.daemon_functions @
  Actions_debug.daemon_functions @
  Actions_hivex.daemon_functions @
  Actions_tsk.daemon_functions

(* Non-API meta-commands available only in guestfish.
 *
 * Note (1): The only fields which are actually used are the
 * shortname, fish_alias, shortdesc and longdesc.
 *
 * Note (2): to refer to other commands, use L</shortname>.
 *
 * Note (3): keep this list sorted by shortname.
 *)
let fish_commands = [
  { defaults with
    name = "alloc";
    fish_alias = ["allocate"];
    shortdesc = "allocate and add a disk file";
    longdesc = " alloc filename size

This creates an empty (zeroed) file of the given size, and then adds
so it can be further examined.

For more advanced image creation, see L</disk-create>.

Size can be specified using standard suffixes, eg. C<1M>.

To create a sparse file, use L</sparse> instead.  To create a
prepared disk image, see L</PREPARED DISK IMAGES>." };

  { defaults with
    name = "copy_in";
    shortdesc = "copy local files or directories into an image";
    longdesc = " copy-in local [local ...] /remotedir

C<copy-in> copies local files or directories recursively into the disk
image, placing them in the directory called F</remotedir> (which must
exist).  This guestfish meta-command turns into a sequence of
L</tar-in> and other commands as necessary.

Multiple local files and directories can be specified, but the last
parameter must always be a remote directory.  Wildcards cannot be
used." };

  { defaults with
    name = "copy_out";
    shortdesc = "copy remote files or directories out of an image";
    longdesc = " copy-out remote [remote ...] localdir

C<copy-out> copies remote files or directories recursively out of the
disk image, placing them on the host disk in a local directory called
C<localdir> (which must exist).  This guestfish meta-command turns
into a sequence of L</download>, L</tar-out> and other commands as
necessary.

Multiple remote files and directories can be specified, but the last
parameter must always be a local directory.  To download to the
current directory, use C<.> as in:

 copy-out /home .

Wildcards cannot be used in the ordinary command, but you can use
them with the help of L</glob> like this:

 glob copy-out /home/* ." };

  { defaults with
    name = "delete_event";
    shortdesc = "delete a previously registered event handler";
    longdesc = " delete-event name

Delete the event handler which was previously registered as C<name>.
If multiple event handlers were registered with the same name, they
are all deleted.

See also the guestfish commands C<event> and C<list-events>." };

  { defaults with
    name = "display";
    shortdesc = "display an image";
    longdesc = " display filename

Use C<display> (a graphical display program) to display an image
file.  It downloads the file, and runs C<display> on it.

To use an alternative program, set the C<GUESTFISH_DISPLAY_IMAGE>
environment variable.  For example to use the GNOME display program:

 export GUESTFISH_DISPLAY_IMAGE=eog

See also L<display(1)>." };

  { defaults with
    name = "echo";
    shortdesc = "display a line of text";
    longdesc = " echo [params ...]

This echos the parameters to the terminal." };

  { defaults with
    name = "edit";
    fish_alias = ["vi"; "emacs"];
    shortdesc = "edit a file";
    longdesc = " edit filename

This is used to edit a file.  It downloads the file, edits it
locally using your editor, then uploads the result.

The editor is C<$EDITOR>.  However if you use the alternate
commands C<vi> or C<emacs> you will get those corresponding
editors." };

  { defaults with
    name = "event";
    shortdesc = "register a handler for an event or events";
    longdesc = " event name eventset \"shell script ...\"

Register a shell script fragment which is executed when an
event is raised.  See L<guestfs(3)/guestfs_set_event_callback>
for a discussion of the event API in libguestfs.

The C<name> parameter is a name that you give to this event
handler.  It can be any string (even the empty string) and is
simply there so you can delete the handler using the guestfish
C<delete-event> command.

The C<eventset> parameter is a comma-separated list of one
or more events, for example C<close> or C<close,trace>.  The
special value C<*> means all events.

The third and final parameter is the shell script fragment
(or any external command) that is executed when any of the
events in the eventset occurs.  It is executed using
C<$SHELL -c>, or if C<$SHELL> is not set then F</bin/sh -c>.

The shell script fragment receives callback parameters as
arguments C<$1>, C<$2> etc.  The actual event that was
called is available in the environment variable C<$EVENT>.

 event \"\" close \"echo closed\"
 event messages appliance,library,trace \"echo $@\"
 event \"\" progress \"echo progress: $3/$4\"
 event \"\" * \"echo $EVENT $@\"

See also the guestfish commands C<delete-event> and C<list-events>." };

  { defaults with
    name = "glob";
    shortdesc = "expand wildcards in command";
    longdesc = " glob command args...

Expand wildcards in any paths in the args list, and run C<command>
repeatedly on each matching path.

See L</WILDCARDS AND GLOBBING>." };

  { defaults with
    name = "hexedit";
    shortdesc = "edit with a hex editor";
    longdesc = " hexedit <filename|device>
 hexedit <filename|device> <max>
 hexedit <filename|device> <start> <max>

Use hexedit (a hex editor) to edit all or part of a binary file
or block device.

This command works by downloading potentially the whole file or
device, editing it locally, then uploading it.  If the file or
device is large, you have to specify which part you wish to edit
by using C<max> and/or C<start> C<max> parameters.
C<start> and C<max> are specified in bytes, with the usual
modifiers allowed such as C<1M> (1 megabyte).

For example to edit the first few sectors of a disk you
might do:

 hexedit /dev/sda 1M

which would allow you to edit anywhere within the first megabyte
of the disk.

To edit the superblock of an ext2 filesystem on F</dev/sda1>, do:

 hexedit /dev/sda1 0x400 0x400

(assuming the superblock is in the standard location).

This command requires the external L<hexedit(1)> program.  You
can specify another program to use by setting the C<HEXEDITOR>
environment variable.

See also L</hexdump>." };

  { defaults with
    name = "lcd";
    shortdesc = "change working directory";
    longdesc = " lcd directory

Change the local directory, ie. the current directory of guestfish
itself.

Note that C<!cd> won't do what you might expect." };

  { defaults with
    name = "list_events";
    shortdesc = "list event handlers";
    longdesc = " list-events

List the event handlers registered using the guestfish
C<event> command." };

  { defaults with
    name = "man";
    fish_alias = ["manual"];
    shortdesc = "open the manual";
    longdesc = "  man

Opens the manual page for guestfish." };

  { defaults with
    name = "more";
    fish_alias = ["less"];
    shortdesc = "view a file";
    longdesc = " more filename

 less filename

This is used to view a file.

The default viewer is C<$PAGER>.  However if you use the alternate
command C<less> you will get the C<less> command specifically." };

  { defaults with
    name = "reopen";
    shortdesc = "close and reopen libguestfs handle";
    longdesc = "  reopen

Close and reopen the libguestfs handle.  It is not necessary to use
this normally, because the handle is closed properly when guestfish
exits.  However this is occasionally useful for testing." };

  { defaults with
    name = "setenv";
    shortdesc = "set an environment variable";
    longdesc = "  setenv VAR value

Set the environment variable C<VAR> to the string C<value>.

To print the value of an environment variable use a shell command
such as:

 !echo $VAR" };

  { defaults with
    name = "sparse";
    shortdesc = "create a sparse disk image and add";
    longdesc = " sparse filename size

This creates an empty sparse file of the given size, and then adds
so it can be further examined.

In all respects it works the same as the L</alloc> command, except that
the image file is allocated sparsely, which means that disk blocks are
not assigned to the file until they are needed.  Sparse disk files
only use space when written to, but they are slower and there is a
danger you could run out of real disk space during a write operation.

For more advanced image creation, see L</disk-create>.

Size can be specified using standard suffixes, eg. C<1M>.

See also the guestfish L</scratch> command." };

  { defaults with
    name = "supported";
    shortdesc = "list supported groups of commands";
    longdesc = " supported

This command returns a list of the optional groups
known to the daemon, and indicates which ones are
supported by this build of the libguestfs appliance.

See also L<guestfs(3)/AVAILABILITY>." };

  { defaults with
    name = "time";
    shortdesc = "print elapsed time taken to run a command";
    longdesc = " time command args...

Run the command as usual, but print the elapsed time afterwards.  This
can be useful for benchmarking operations." };

  { defaults with
    name = "unsetenv";
    shortdesc = "unset an environment variable";
    longdesc = "  unsetenv VAR

Remove C<VAR> from the environment." };

]

(*----------------------------------------------------------------------*)

(* Some post-processing of the basic lists of actions. *)

(* Add the name of the C function:
 * c_name = short name, used by C bindings so we know what to export
 * c_function = full name that non-C bindings should call
 * c_optarg_prefix = prefix for optarg / bitmask names
 *)
let test_functions, non_daemon_functions, daemon_functions =
  let make_c_function f =
    match f with
    | { style = _, _, [] } ->
      { f with
          c_name = f.name;
          c_function = "guestfs_" ^ f.name;
          c_optarg_prefix = "GUESTFS_" ^ String.uppercase_ascii f.name }
    | { style = _, _, (_::_); once_had_no_optargs = false } ->
      { f with
          c_name = f.name;
          c_function = "guestfs_" ^ f.name ^ "_argv";
          c_optarg_prefix = "GUESTFS_" ^ String.uppercase_ascii f.name }
    | { style = _, _, (_::_); once_had_no_optargs = true } ->
      { f with
          c_name = f.name ^ "_opts";
          c_function = "guestfs_" ^ f.name ^ "_opts_argv";
          c_optarg_prefix = "GUESTFS_" ^ String.uppercase_ascii f.name
                            ^ "_OPTS";
          non_c_aliases = [ f.name ^ "_opts" ] }
  in
  let test_functions =
    List.map make_c_function Actions_internal_tests.test_functions in
  let non_daemon_functions = List.map make_c_function non_daemon_functions in
  let daemon_functions = List.map make_c_function daemon_functions in
  test_functions, non_daemon_functions, daemon_functions

(* Create a camel-case version of each name, unless the camel_name
 * field was set above.
 *)
let non_daemon_functions, daemon_functions =
  let make_camel_case name =
    List.fold_left (
      fun a b ->
        a ^ String.uppercase_ascii (Str.first_chars b 1) ^ Str.string_after b 1
    ) "" (Str.split (Str.regexp "_") name)
  in
  let make_camel_case_if_not_set f =
    if f.camel_name = "" then
      { f with camel_name = make_camel_case f.name }
    else
      f
  in
  let non_daemon_functions =
    List.map make_camel_case_if_not_set non_daemon_functions in
  let daemon_functions =
    List.map make_camel_case_if_not_set daemon_functions in
  non_daemon_functions, daemon_functions

(* Before we add the non_daemon_functions and daemon_functions to
 * a single list, verify the proc_nr field which should be the only
 * difference between them.  (Note more detailed checking is done
 * in checks.ml).
 *)
let () =
  List.iter (
    function
    | { name = name; proc_nr = None } ->
      failwithf "daemon function %s should have proc_nr = Some n > 0" name
    | { name = name; proc_nr = Some n } when n <= 0 ->
      failwithf "daemon function %s should have proc_nr = Some n > 0" name
    | { proc_nr = Some _ } -> ()
  ) daemon_functions;

  List.iter (
    function
    | { name = name; proc_nr = Some _ } ->
      failwithf "non-daemon function %s should have proc_nr = None" name
    | { proc_nr = None } -> ()
  ) non_daemon_functions

(* This is used to generate the lib/MAX_PROC_NR file which
 * contains the maximum procedure number, a surrogate for the
 * ABI version number.  See lib/Makefile.am for the details.
 *)
let max_proc_nr =
  let proc_nrs = List.map (
    function { proc_nr = Some n } -> n | { proc_nr = None } -> assert false
  ) daemon_functions in
  List.fold_left max 0 proc_nrs

(* All functions. *)
let actions = non_daemon_functions @ daemon_functions

(* Filters which can be applied. *)
let is_non_daemon_function = function
  | { proc_nr = None } -> true
  | { proc_nr = Some _ } -> false
let non_daemon_functions = List.filter is_non_daemon_function

let is_daemon_function f = not (is_non_daemon_function f)
let daemon_functions = List.filter is_daemon_function

let is_external { visibility = v } = match v with
  | VPublic | VPublicNoFish | VStateTest | VBindTest | VDebug -> true
  | VInternal -> false
let external_functions = List.filter is_external

let is_internal f = not (is_external f)
let internal_functions = List.filter is_internal

let is_documented { visibility = v } = match v with
  | VPublic | VPublicNoFish | VStateTest -> true
  | VBindTest | VDebug | VInternal -> false
let documented_functions = List.filter is_documented

let is_fish { visibility = v; style = (_, args, _) } =
  (* Internal functions are not exported to guestfish. *)
  match v with
  | VPublicNoFish | VStateTest | VBindTest | VInternal -> false
  | VPublic | VDebug ->
    (* Functions that take Pointer parameters cannot be used in
     * guestfish, since there is no way the user could safely
     * generate a pointer.
     *)
    not (List.exists (function Pointer _ -> true | _ -> false) args)
let fish_functions = List.filter is_fish

(* In some places we want the functions to be displayed sorted
 * alphabetically, so this is useful:
 *)
let sort = List.sort action_compare
