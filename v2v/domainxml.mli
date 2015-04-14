(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

(** [virsh dumpxml] but with non-broken authentication handling.

    If you do [virsh dumpxml foo] and if the libvirt source (eg. ESX)
    requires an interactive password, then virsh unhelpfully sends the
    password prompt to stdout, which is the same place we would be
    reading the XML from.  This file works around this brokenness. *)

val dumpxml : ?password:string -> ?conn:string -> string -> string
(** [dumpxml ?password ?conn dom] returns the libvirt XML of domain [dom].
    The optional [?conn] parameter is the libvirt connection URI.
    [dom] may be a guest name or UUID. *)

val pool_dumpxml : ?conn:string -> string -> string
(** [pool_dumpxml ?conn pool] returns the libvirt XML of pool [pool].
    The optional [?conn] parameter is the libvirt connection URI.
    [pool] may be a pool name or UUID. *)

val vol_dumpxml : ?conn:string -> string -> string -> string
(** [vol_dumpxml ?conn pool vol] returns the libvirt XML of volume [vol],
    which is part of the pool [pool].
    The optional [?conn] parameter is the libvirt connection URI.
    [pool] may be a pool name or UUID. *)
