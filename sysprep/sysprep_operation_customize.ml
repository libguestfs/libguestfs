(* virt-sysprep
 * Copyright (C) 2014 Red Hat Inc.
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

open Sysprep_operation
open Common_gettext.Gettext

module G = Guestfs

let customize_args, get_ops =
  let args, get_ops = Customize_cmdline.argspec () in
  let args = List.map (
    fun (spec, v, longdesc) ->
      { extra_argspec = spec;
        extra_pod_argval = v; extra_pod_description = longdesc }
  ) args in
  args, get_ops

let customize_perform ~quiet g root side_effects =
  let ops = get_ops () in
  Customize_run.run ~quiet g root ops;
  side_effects#created_file () (* XXX Did we? *)

let op = {
  defaults with
    order = 99;                         (* Run it after everything. *)
    name = "customize";
    enabled_by_default = true;
    heading = s_"Customize the guest";
    pod_description = Some (s_"\
Customize the guest by providing L<virt-customize(1)> options
for installing packages, editing files and so on.");
    extra_args = customize_args;
    perform_on_filesystems = Some customize_perform;
}

let () = register_operation op
