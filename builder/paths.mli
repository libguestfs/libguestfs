(* virt-builder
 * Copyright (C) 2014-2017 Red Hat Inc.
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

val xdg_cache_home : string option
(** [$XDG_CACHE_HOME/virt-builder] or [$HOME/.cache/virt-builder] or [None]. *)

val xdg_config_home : unit -> string option
(** [$XDG_CONFIG_HOME/prog] or [$HOME/.config/prog] or [None]. *)

val xdg_config_dirs : unit -> string list
(** [$XDG_CONFIG_DIRS] (which is a colon-separated path), split.  Empty
    elements are removed from the list.  If the environment variable
    is not set [["/etc/xdg"]] is returned instead. *)
