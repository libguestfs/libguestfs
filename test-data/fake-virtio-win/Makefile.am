# libguestfs test images
# Copyright (C) 2009-2015 Red Hat Inc.
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

# Fake virtio-win (Windows virtio) drivers.
#
# Tests in the v2v subdirectory can set VIRTIO_WIN to point to this
# directory, or to the .iso file in this directory, in order to test
# conversions.
#
# Note that the "drivers" are not real!

include $(top_srcdir)/subdir-rules.mk

drivers = \
	drivers/i386/Win7/qxl.cat \
	drivers/i386/Win7/qxl.inf \
	drivers/i386/Win7/qxl.sys \
	drivers/i386/Win7/netkvm.cat \
	drivers/i386/Win7/netkvm.inf \
	drivers/i386/Win7/netkvm.sys \
	drivers/i386/Win7/vioscsi.cat \
	drivers/i386/Win7/vioscsi.inf \
	drivers/i386/Win7/vioscsi.sys \
	drivers/i386/Win7/viostor.cat \
	drivers/i386/Win7/viostor.inf \
	drivers/i386/Win7/viostor.sys

EXTRA_DIST = $(drivers)

check_DATA = fake-virtio-win.iso

CLEANFILES = fake-virtio-win.iso

fake-virtio-win.iso: $(drivers)
	$(GENISOIMAGE) -J -r -o $@ -graft-points drivers=drivers
