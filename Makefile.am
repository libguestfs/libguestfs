# libguestfs
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

SUBDIRS = src daemon examples

EXTRA_DIST = make-initramfs.sh

# Build the root filesystem.
# Currently this is arch-dependent, so it seems like putting it in
# $(libdir) is best.  When we build cross-architecture filesystems we
# should probably move them to $(datadir).

fsdir = $(libdir)/guestfs

fs_DATA = initramfs.$(REPO).$(host_cpu).img vmlinuz.$(REPO).$(host_cpu)

$(fs_DATA): make-initramfs.sh.in daemon/guestfsd
	$(builddir)/make-initramfs.sh

.PHONY: daemon/guestfsd

# Make clean.

CLEANFILES = $(fs_DATA)

clean-local:
	rm -rf initramfs
