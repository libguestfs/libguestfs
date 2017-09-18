(* virt-dib
 * Copyright (C) 2015 Red Hat Inc.
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

(** Parsing and handling of elements. *)

type element = {
  directory : string;           (** directory of the element *)
  hooks : hooks_map;            (** available hooks, and scripts for each hook*)
}
and hooks_map = (string, string list) Hashtbl.t (** hook name, scripts *)

val builtin_elements_blacklist : string list
(** These are the elements which we don't ever try to use. *)

val builtin_scripts_blacklist : string list
(** These are the scripts which we don't ever try to run.

    Usual reason could be that they are not compatible the way
    virt-dib works, e.g. they expect the tree of elements outside
    the chroot, which is not available in the appliance. *)

val load_elements : debug:int -> string list -> (string, element) Hashtbl.t
(** [load_elements ~debug paths] loads elements from the specified
    [paths]; returns a [Hashtbl.t] of {!element} structs indexed by
    the element name. *)

val load_dependencies : StringSet.elt list -> (string, element) Hashtbl.t -> StringSet.t
(** [load_dependencies element_set elements] returns the whole set of
    elements needed to use [element_set], including [element_list]
    themselves.  In other words, this recursively resolves the
    dependencies of [element_set]. *)

val copy_elements : StringSet.t -> (string, element) Hashtbl.t -> string list -> string -> unit
(** [copy_elements element_set elements blacklisted_scripts destdir]
    copies the elements in [element_set] (with the element definitions
    provided as [elements]) into the [destdir] directory.

    [blacklisted_scripts] contains names of scripts to never copy. *)

val load_hooks : debug:int -> string -> hooks_map
(** [load_hooks ~debug path] loads the hooks from the specified
    [path] (which usually represents an element). *)

val load_scripts : Guestfs.guestfs -> string -> string list
(** [load_scripts g path] loads the scripts from the specified [path]
    (which usually represents a directory of an hook). *)
