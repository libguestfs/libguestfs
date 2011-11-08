# libguestfs Ruby bindings -*- ruby -*-
# @configure_input@
# Copyright (C) 2009 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

require 'mkmf'

extension_name = '_guestfs'

dir_config(extension_name)

unless have_header("guestfs.h")
  raise "<guestfs.h> not found"
end
unless have_library("guestfs", "guestfs_create", "guestfs.h")
  raise "libguestfs not found"
end

create_header
create_makefile(extension_name)
