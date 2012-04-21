(* virt-sysprep
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

(** Structure used to describe sysprep operations. *)

type flag = [ `Created_files ]

type operation = {
  name : string;
  (** Operation name, also used to enable the operation on the command
      line.  Must contain only alphanumeric and '-' (dash)
      character. *)

  enabled_by_default : bool;
  (** If true, then enabled by default when no [--enable] option is
      given on the command line. *)

  heading : string;
  (** One-line description, NO trailing period. *)

  pod_description : string option;
  (** POD-format long description, used for the man page. *)

  extra_args : ((Arg.key * Arg.spec * Arg.doc) * string) list;
  (** Extra command-line arguments, if any.  eg. The [hostname]
      operation has an extra [--hostname] parameter.

      Each element of the list is the argspec (see {!Arg.spec} etc.)
      and the corresponding full POD documentation.

      You can decide the types of the arguments, whether they are
      mandatory etc. *)

  perform : Guestfs.guestfs -> string -> flag list;
  (** The function which is called to perform this operation, when
      enabled.

      The parameters are [g] (libguestfs handle) and [root] (the
      operating system root filesystem).  Inspection has been performed
      already on this handle so if the operation depends on OS type,
      call [g#inspect_get_type], [g#inspect_get_distro] etc. in order to
      determine that.  The guest operating system's disks have been
      mounted up, and this function must not unmount them.

      In the rare case of a multiboot operating system, it is possible
      for this function to be called multiple times.

      On success, the function can return a list of flags (or an
      empty list).  See {!flag}.

      On error the function should raise an exception.  The function
      also needs to be careful to {i suppress} exceptions for things
      which are not errors, eg. deleting non-existent files. *)
}

val register_operation : operation -> unit
(** Register an operation. *)

val bake : unit -> unit
(** 'Bake' is called after all modules have been registered.  We
    finalize the list of operations, sort it, and run some checks. *)

val extra_args : unit -> (Arg.key * Arg.spec * Arg.doc) list
(** Get the list of extra arguments for the command line. *)

val dump_pod : unit -> unit
(** Dump the perldoc (POD) for the manual page
    (implements [--dump-pod]). *)

val dump_pod_options : unit -> unit
(** Dump the perldoc (POD) for the [extra_args]
    (implements [--dump-pod-options]). *)

val list_operations : unit -> unit
(** List supported operations
    (implements [--list-operations]). *)

type set
(** A (sub-)set of operations. *)

val empty_set : set
(** Empty set of operations. *)

val add_to_set : string -> set -> set
(** [add_to_set name set] adds the operation named [name] to [set].

    Note that this will raise [Not_found] if [name] is not
    a valid operation name. *)

val perform_operations : ?operations:set -> ?quiet:bool -> Guestfs.guestfs -> string -> flag list
(** Perform all operations, or the subset listed in the [operations] set. *)
