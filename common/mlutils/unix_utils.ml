(* mllib
 * Copyright (C) 2009-2017 Red Hat Inc.
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

module Dev_t = struct
  external makedev : int -> int -> int = "guestfs_int_mllib_dev_t_makedev" "noalloc"
  external major : int -> int = "guestfs_int_mllib_dev_t_major" "noalloc"
  external minor : int -> int = "guestfs_int_mllib_dev_t_minor" "noalloc"
end

module Env = struct
  external unsetenv : string -> unit = "guestfs_int_mllib_unsetenv" "noalloc"
end

module Exit = struct
  external _exit : int -> 'a = "guestfs_int_mllib_exit" "noalloc"
end

module Fnmatch = struct
  (* NB: These flags must appear in the same order as unix_utils-c.c *)
  type flag =
    | FNM_NOESCAPE
    | FNM_PATHNAME
    | FNM_PERIOD
    | FNM_FILE_NAME
    | FNM_LEADING_DIR
    | FNM_CASEFOLD

  external fnmatch : string -> string -> flag list -> bool =
    "guestfs_int_mllib_fnmatch"
end

module Fsync = struct
  external sync : unit -> unit = "guestfs_int_mllib_sync" "noalloc"
  external file : string -> unit = "guestfs_int_mllib_fsync_file"
end

module Mkdtemp = struct
  external mkdtemp : string -> string = "guestfs_int_mllib_mkdtemp"

  let temp_dir ?(base_dir = Filename.temp_dir_name) prefix =
    mkdtemp (Filename.concat base_dir (prefix ^ "XXXXXX"))
end

module Realpath = struct
  external realpath : string -> string = "guestfs_int_mllib_realpath"
end

module StatVFS = struct
  external free_space : string -> int64 =
    "guestfs_int_mllib_statvfs_free_space"
end
