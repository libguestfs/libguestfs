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

(** Inspect the source disk.

   This handles the [--root] command line option. *)

val inspect_source : Types.root_choice -> Guestfs.guestfs -> Types.inspect
(** Inspect the source disk, returning inspection data.

    Before calling this, the disks must be added to the handle
    and the handle must be launched.

    After calling this, the filesystems are mounted up.

    Depending on the contents of [root_choice] (the [--root] command
    line option) this function may even be interactive. *)
