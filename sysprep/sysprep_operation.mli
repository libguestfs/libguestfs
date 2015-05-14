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

(** Defines the interface between the main program and sysprep operations. *)

class filesystem_side_effects : object
  method created_file : unit -> unit
  method get_created_file : bool
  method changed_file : unit -> unit
  method get_changed_file : bool
end
(** The callback should indicate if it has side effects by calling
    methods in this class. *)

class device_side_effects : object end
(** There are currently no device side-effects.  For future use. *)

type 'side_effects callback = verbose:bool -> quiet:bool -> Guestfs.guestfs -> string -> 'side_effects -> unit
(** [callback ~verbose ~quiet g root side_effects] is called to do work.

    If the operation has side effects such as creating files, it
    should indicate that by calling the [side_effects] object. *)

(** Structure used to describe sysprep operations. *)
type operation = {
  order : int;
  (** This is used to control the order in which operations run.  The
      default is [0], so most operations run in alphabetical order at
      the same level.  You can make an operation run after others by
      giving it a [>0] order.  You can make an operation run before
      others by giving it a [<0] order. *)

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

  pod_notes : string option;
  (** POD-format notes, used for the man page to describe any
      problems, shortcomings or bugs with this operation. *)

  extra_args : extra_arg list;
  (** Extra command-line arguments, if any.  eg. The [hostname]
      operation has an extra [--hostname] parameter.

      For a description of each list element, see {!extra_arg} below.

      You can decide the types of the arguments, whether they are
      mandatory etc. *)

  not_enabled_check_args : unit -> unit;
  (** If the operation is [not] enabled (or disabled), this function is
      called after argument parsing and can be used to check that
      no useless extra_args were passed by the user. *)

  perform_on_filesystems : filesystem_side_effects callback option;
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

      If the callback has side effects such as create files, it should
      call the appropriate method in {!filesystem_side_effects}.

      On error the function should raise an exception.  The function
      also needs to be careful to {i suppress} exceptions for things
      which are not errors, eg. deleting non-existent files. *)

  perform_on_devices : device_side_effects callback option;
  (** This is the same as {!perform_on_filesystems} except that
      the guest filesystem(s) are {i not} mounted.  This allows the
      operation to work directly on block devices, LVs etc. *)
}

and extra_arg = {
  extra_argspec : Arg.key * Arg.spec * Arg.doc;
  (** The argspec.  See OCaml [Arg] module. *)

  extra_pod_argval : string option;
  (** The argument value, used only in the virt-sysprep man page. *)

  extra_pod_description : string;
  (** The long description, used only in the virt-sysprep man page. *)
}

val defaults : operation
(** This is so operations can write [let op = { defaults with ... }]. *)

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

val add_defaults_to_set : set -> set
(** [add_defaults_to_set set] adds to [set] all the operations enabled
    by default. *)

val add_all_to_set : set -> set
(** [add_all_to_set set] adds to [set] all the available operations. *)

val remove_from_set : string -> set -> set
(** [remove_from_set name set] remove the operation named [name] from [set].

    Note that this will raise [Not_found] if [name] is not
    a valid operation name. *)

val remove_defaults_from_set : set -> set
(** [remove_defaults_from_set set] removes from [set] all the operations
    enabled by default. *)

val remove_all_from_set : set -> set
(** [remove_all_from_set set] removes from [set] all the available
    operations. *)

val not_enabled_check_args : ?operations:set -> unit -> unit
(** Call [not_enabled_check_args] on all operations in the set
    which are {i not} enabled. *)

val perform_operations_on_filesystems : ?operations:set -> verbose:bool -> quiet:bool -> Guestfs.guestfs -> string -> filesystem_side_effects -> unit
(** Perform all operations, or the subset listed in the [operations] set. *)

val perform_operations_on_devices : ?operations:set -> verbose:bool -> quiet:bool -> Guestfs.guestfs -> string -> device_side_effects -> unit
(** Perform all operations, or the subset listed in the [operations] set. *)
