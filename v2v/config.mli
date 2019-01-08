(* virt-v2v
 * Copyright (C) 2019 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

val virt_v2v_nbdkit_python_plugin : string
(** Return the name of the nbdkit python plugin used by
    [virt-v2v -o rhv-upload].

    As above this must also be the Python 3 version of the plugin,
    unless you change it.  The configure command to change this is:

    [./configure --with-virt-v2v-nbdkit-python-plugin=...] *)
