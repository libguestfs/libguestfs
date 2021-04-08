# libguestfs Go examples
# Copyright (C) 2013 Red Hat Inc.
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

include $(top_srcdir)/subdir-rules.mk

EXTRA_DIST = \
	LICENSE \
	create-disk/go.mod \
	create-disk/create-disk.go \
	inspect-vm/go.mod \
	inspect-vm/inspect-vm.go \
	guestfs-golang.pod

man_MANS = guestfs-golang.3
noinst_DATA = $(top_builddir)/website/guestfs-golang.3.html

guestfs-golang.3 $(top_builddir)/website/guestfs-golang.3.html: stamp-guestfs-golang.pod

stamp-guestfs-golang.pod: guestfs-golang.pod \
		create-disk/create-disk.go inspect-vm/inspect-vm.go
	$(PODWRAPPER) \
	  --section 3 \
	  --man guestfs-golang.3 \
	  --html $(top_builddir)/website/guestfs-golang.3.html \
	  --verbatim $(srcdir)/create-disk/create-disk.go:@EXAMPLE1@ \
	  --verbatim $(srcdir)/inspect-vm/inspect-vm.go:@EXAMPLE2@ \
	  --license examples \
	  $<
	touch $@
