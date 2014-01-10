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

open Printf

open Common_utils
open Sysprep_operation
open Common_gettext.Gettext

module G = Guestfs

let timezone = ref None

let timezone_perform (g : Guestfs.guestfs) root =
  match !timezone with
  | None -> []
  | Some tz ->
    if Timezone.set_timezone ~prog g root tz then [ `Created_files ] else []

let op = {
  defaults with
    name = "timezone";
    enabled_by_default = true;
    heading = s_"Change the default timezone of the guest";

    pod_description = Some (s_"\
This operation changes the default timezone of the guest to the value
given in the I<--timezone> parameter.

If the I<--timezone> parameter is not given, then the timezone is not
changed.

This parameter affects the default timezone that users see when they log
in, but they can still change their timezone per-user account.");

    pod_notes = Some (s_"\
Currently this can only set the timezone on Linux guests.");

    extra_args = [
      let set_timezone str = timezone := Some str in
      { extra_argspec = "--timezone", Arg.String set_timezone, s_"timezone" ^ " " ^ s_"New timezone";
        extra_pod_argval = Some "TIMEZONE";
        extra_pod_description = s_"\
Change the timezone.  Use a location string such as C<Europe/London>"
      }
    ];

    perform_on_filesystems = Some timezone_perform;
}

let () = register_operation op
