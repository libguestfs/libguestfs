(* virt-v2v
 * Copyright (C) 2009-2018 Red Hat Inc.
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

(** Convert a Linux guest to run on KVM.

    This module converts certain Enterprise Linux guests to run on
    KVM.  RHEL, SuSE, Fedora, CentOS, OracleLinux, Debian, Ubuntu,
    Mint and Kali are supported by this module.

    No functions are exported.  When the module is linked to virt-v2v
    it registers itself with
    {!Modules_list.register_convert_module}. *)
