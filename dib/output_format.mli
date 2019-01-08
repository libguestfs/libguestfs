(* virt-dib
 * Copyright (C) 2012-2019 Red Hat Inc.
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

(** Handling of output formats. *)

(** Structure used to describe output formats. *)
type format = {
  name : string;
  (** The name of the format, which is exposed via the [--formats]
      command line parameter.  Must contain only alphanumeric and
      '-' (dash) character. *)

  extra_args : extra_arg list;
  (** Extra command-line arguments, if any.  eg. The [docker]
      format has an extra [--docker-target] parameter.

      For a description of each list element, see {!extra_arg} below.

      You can decide the types of the arguments, whether they are
      mandatory etc. *)

  output_to_file : bool;
  (** Whether the format writes to a file.  Most of the formats
      produce a file as result, although some (e.g. docker) do
      not. *)

  check_prerequisites : (unit -> unit) option;
  (** The function which is called after the command line processing
      to check whether the requirements for this format (available
      tools, values for command line arguments, etc) are fulfilled. *)

  check_appliance_prerequisites : (Guestfs.guestfs -> unit) option;
  (** The function which is called after the appliance start to check
      whether the requirements in the appliance for this format
      (available features, filesystems, etc) are fulfilled. *)

  run_on_filesystem : (Guestfs.guestfs -> string -> string -> unit) option;
  (** The function which is called to perform the export while the
      guest is mounted.

      The parameters are:
      - [g]: the libguestfs handle
      - [filename]: the output filename for the format, or an empty
        string if {!output_to_file} is [false]
      - [tmpdir]: the temporary directory currently in use *)

  run_on_file : (string -> (string * string) -> string -> unit) option;
  (** The function which is called to perform the export using the
      temporary disk as reference.

      The parameters are:
      - [filename]: the output filename for the format, or an empty
        string if {!output_to_file} is [false]
      - [tmpdisk]: a tuple representing the temporary disk, as
        [(filename, format)]
      - [tmpdir]: the temporary directory currently in use *)
}

and extra_arg = {
  extra_argspec : Getopt.keys * Getopt.spec * Getopt.doc;
  (** The argspec.  See [Getopt] module in [common/mltools]. *)
}

val defaults : format
(** This is so formats can write [let op = { defaults with ... }]. *)

val register_format : format -> unit
(** Register a format. *)

val bake : unit -> unit
(** 'Bake' is called after all modules have been registered.  We
    finalize the list of formats, sort it, and run some checks. *)

val extra_args : unit -> Getopt.speclist
(** Get the list of extra arguments for the command line. *)

val list_formats : unit -> string list
(** List supported formats. *)

type set
(** A (sub-)set of formats. *)

val empty_set : set
(** Empty set of formats. *)

val add_to_set : string -> set -> set
(** [add_to_set name set] adds the format named [name] to [set].

    Note that this will raise [Not_found] if [name] is not
    a valid format name. *)

val set_mem : string -> set -> bool
(** Check whether the specified format is in the set. *)

val set_cardinal : set -> int
(** Return the size of the formats set. *)

val check_formats_prerequisites : formats:set -> unit
(** Check the prerequisites in all the formats listed in the [formats] set. *)

val check_formats_appliance_prerequisites : formats:set -> Guestfs.guestfs -> unit
(** Check the appliance prerequisites in all the formats listed in the
    [formats] set. *)

val run_formats_on_filesystem : formats:set -> Guestfs.guestfs -> string -> string -> unit
(** Run the filesystem-based export for all the formats listed in the
    [formats] set. *)

val run_formats_on_file : formats:set -> string -> (string * string) -> string -> unit
(** Run the disk-based export for all the formats listed in the
    [formats] set. *)

val get_filenames : formats:set -> string -> string list
(** Return the list of all the output filenames for formats in the
    [formats] set.  Only formats with {!output_to_file} as [true]
    will be taken into account. *)
