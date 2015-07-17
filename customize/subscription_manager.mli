(* virt-customize
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

type sm_credentials = {
  sm_username : string;
  sm_password : string;
}

type sm_pool =
| PoolAuto                           (** Automatic entitlements. *)
| PoolId of string                   (** Specific pool. *)

val parse_credentials_selector : string -> sm_credentials
(** Parse the selector field in --sm-credentials.  Exits if the format
    is not valid. *)

val parse_pool_selector : string -> sm_pool
(** Parse the selector field in --sm-attach.  Exits if the format
    is not valid. *)
