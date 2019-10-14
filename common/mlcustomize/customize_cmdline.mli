(* libguestfs generated file
 * WARNING: THIS FILE IS GENERATED FROM THE FOLLOWING FILES:
 *          generator/customize.ml
 *          and from the code in the generator/ subdirectory.
 * ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.
 *
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

(** Command line argument parsing, both for the virt-customize binary
    and for the other tools that share the same code. *)

type ops = {
  ops : op list;
  flags : flags;
}
and op = [
  | `AppendLine of string * string
      (* --append-line FILE:LINE *)
  | `Chmod of string * string
      (* --chmod PERMISSIONS:FILE *)
  | `CommandsFromFile of string
      (* --commands-from-file FILENAME *)
  | `Copy of string * string
      (* --copy SOURCE:DEST *)
  | `CopyIn of string * string
      (* --copy-in LOCALPATH:REMOTEDIR *)
  | `Delete of string
      (* --delete PATH *)
  | `Edit of string * string
      (* --edit FILE:EXPR *)
  | `FirstbootScript of string
      (* --firstboot SCRIPT *)
  | `FirstbootCommand of string
      (* --firstboot-command 'CMD+ARGS' *)
  | `FirstbootPackages of string list
      (* --firstboot-install PKG,PKG.. *)
  | `Hostname of string
      (* --hostname HOSTNAME *)
  | `InstallPackages of string list
      (* --install PKG,PKG.. *)
  | `Link of string * string list
      (* --link TARGET:LINK[:LINK..] *)
  | `Mkdir of string
      (* --mkdir DIR *)
  | `Move of string * string
      (* --move SOURCE:DEST *)
  | `Password of string * Password.password_selector
      (* --password USER:SELECTOR *)
  | `RootPassword of Password.password_selector
      (* --root-password SELECTOR *)
  | `Script of string
      (* --run SCRIPT *)
  | `Command of string
      (* --run-command 'CMD+ARGS' *)
  | `Scrub of string
      (* --scrub FILE *)
  | `SMAttach of Subscription_manager.sm_pool
      (* --sm-attach SELECTOR *)
  | `SMRegister
      (* --sm-register *)
  | `SMRemove
      (* --sm-remove *)
  | `SMUnregister
      (* --sm-unregister *)
  | `SSHInject of string * Ssh_key.ssh_key_selector
      (* --ssh-inject USER[:SELECTOR] *)
  | `Truncate of string
      (* --truncate FILE *)
  | `TruncateRecursive of string
      (* --truncate-recursive PATH *)
  | `Timezone of string
      (* --timezone TIMEZONE *)
  | `Touch of string
      (* --touch FILE *)
  | `UninstallPackages of string list
      (* --uninstall PKG,PKG.. *)
  | `Update
      (* --update *)
  | `Upload of string * string
      (* --upload FILE:DEST *)
  | `Write of string * string
      (* --write FILE:CONTENT *)
]
and flags = {
  scrub_logfile : bool;
      (* --no-logfile *)
  password_crypto : Password.password_crypto option;
      (* --password-crypto md5|sha256|sha512 *)
  selinux_relabel : bool;
      (* --selinux-relabel *)
  sm_credentials : Subscription_manager.sm_credentials option;
      (* --sm-credentials SELECTOR *)
}

type argspec = Getopt.keys * Getopt.spec * Getopt.doc
val argspec : unit -> (argspec * string option * string) list * (unit -> ops)
(** This returns a pair [(list, get_ops)].

    [list] is a list of the command line arguments, plus some extra data.

    [get_ops] is a function you can call {i after} command line parsing
    which will return the actual operations specified by the user on the
    command line. *)