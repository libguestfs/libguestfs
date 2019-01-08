(* virt-v2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

(** Call into external Python code. *)

type script

val create : ?name:string -> string -> script
(** Create a Python script object.

    The optional parameter [?name] is a hint for the name of the script.

    The parameter is the Python code.  Usually this is
    [Some_source.code] where [some_source.ml] is generated from
    the Python file by [v2v/embed.sh] (see also [v2v/Makefile.am]). *)

val run_command : ?echo_cmd:bool -> ?stdout_fd:Unix.file_descr -> ?stderr_fd:Unix.file_descr -> script -> JSON.doc -> string list -> int
(** [run_command script params args] is a wrapper around
    {!Tools_utils.run_command} which runs the Python script with the
    supplied list of JSON parameters and the list of extra arguments.

    The JSON parameters are written into a temporary file and the
    filename is supplied as a parameter to the script, so the script
    must do this to read the parameters:

{v
with open(sys.argv[1], 'r') as fp:
    params = json.load(fp)
v}

    The extra arguments, if any, are passed verbatim on the
    script command line in [sys.argv[2:]].
 *)

val path : script -> string
(** Return the temporary path to the script.

    This temporary script is deleted when the program exits so don't
    try using/storing it beyond the lifetime of the program.

    This is used only where {!run_command} is not suitable. *)

val python : string
(** Return the name of the Python interpreter. *)

val error_unless_python_interpreter_found : unit -> unit
(** Check if the Python interpreter can be found on the path, and
    call [error] (which is fatal) if not. *)
