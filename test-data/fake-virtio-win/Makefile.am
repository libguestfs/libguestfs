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
	drivers/amd64/Win2003/netkvm.cat \
	drivers/amd64/Win2003/netkvm.inf \
	drivers/amd64/Win2003/netkvm.sys \
	drivers/amd64/Win2003/viostor.cat \
	drivers/amd64/Win2003/viostor.inf \
	drivers/amd64/Win2003/viostor.sys \
	drivers/amd64/Win2008/netkvm.cat \
	drivers/amd64/Win2008/netkvm.inf \
	drivers/amd64/Win2008/netkvm.sys \
	drivers/amd64/Win2008R2/netkvm.cat \
	drivers/amd64/Win2008R2/netkvm.inf \
	drivers/amd64/Win2008R2/netkvm.sys \
	drivers/amd64/Win2008R2/qxl.cat \
	drivers/amd64/Win2008R2/qxldd.dll \
	drivers/amd64/Win2008R2/qxl.inf \
	drivers/amd64/Win2008R2/qxl.sys \
	drivers/amd64/Win2008R2/vioscsi.cat \
	drivers/amd64/Win2008R2/vioscsi.inf \
	drivers/amd64/Win2008R2/vioscsi.sys \
	drivers/amd64/Win2008R2/viostor.cat \
	drivers/amd64/Win2008R2/viostor.inf \
	drivers/amd64/Win2008R2/viostor.sys \
	drivers/amd64/Win2008/vioscsi.cat \
	drivers/amd64/Win2008/vioscsi.inf \
	drivers/amd64/Win2008/vioscsi.sys \
	drivers/amd64/Win2008/viostor.cat \
	drivers/amd64/Win2008/viostor.inf \
	drivers/amd64/Win2008/viostor.sys \
	drivers/amd64/Win2012/netkvm.cat \
	drivers/amd64/Win2012/netkvm.inf \
	drivers/amd64/Win2012/netkvm.sys \
	drivers/amd64/Win2012R2/netkvm.cat \
	drivers/amd64/Win2012R2/netkvm.inf \
	drivers/amd64/Win2012R2/netkvm.sys \
	drivers/amd64/Win2012R2/vioscsi.cat \
	drivers/amd64/Win2012R2/vioscsi.inf \
	drivers/amd64/Win2012R2/vioscsi.sys \
	drivers/amd64/Win2012R2/viostor.cat \
	drivers/amd64/Win2012R2/viostor.inf \
	drivers/amd64/Win2012R2/viostor.sys \
	drivers/amd64/Win2012/vioscsi.cat \
	drivers/amd64/Win2012/vioscsi.inf \
	drivers/amd64/Win2012/vioscsi.sys \
	drivers/amd64/Win2012/viostor.cat \
	drivers/amd64/Win2012/viostor.inf \
	drivers/amd64/Win2012/viostor.sys \
	drivers/amd64/Win7/netkvm.cat \
	drivers/amd64/Win7/netkvm.inf \
	drivers/amd64/Win7/netkvm.sys \
	drivers/amd64/Win7/qxl.cat \
	drivers/amd64/Win7/qxldd.dll \
	drivers/amd64/Win7/qxl.inf \
	drivers/amd64/Win7/qxl.sys \
	drivers/amd64/Win7/vioscsi.cat \
	drivers/amd64/Win7/vioscsi.inf \
	drivers/amd64/Win7/vioscsi.sys \
	drivers/amd64/Win7/viostor.cat \
	drivers/amd64/Win7/viostor.inf \
	drivers/amd64/Win7/viostor.sys \
	drivers/amd64/Win8.1/netkvm.cat \
	drivers/amd64/Win8.1/netkvm.inf \
	drivers/amd64/Win8.1/netkvm.sys \
	drivers/amd64/Win8.1/vioscsi.cat \
	drivers/amd64/Win8.1/vioscsi.inf \
	drivers/amd64/Win8.1/vioscsi.sys \
	drivers/amd64/Win8.1/viostor.cat \
	drivers/amd64/Win8.1/viostor.inf \
	drivers/amd64/Win8.1/viostor.sys \
	drivers/amd64/Win8/netkvm.cat \
	drivers/amd64/Win8/netkvm.inf \
	drivers/amd64/Win8/netkvm.sys \
	drivers/amd64/Win8/vioscsi.cat \
	drivers/amd64/Win8/vioscsi.inf \
	drivers/amd64/Win8/vioscsi.sys \
	drivers/amd64/Win8/viostor.cat \
	drivers/amd64/Win8/viostor.inf \
	drivers/amd64/Win8/viostor.sys \
	drivers/i386/Win2003/netkvm.cat \
	drivers/i386/Win2003/netkvm.inf \
	drivers/i386/Win2003/netkvm.sys \
	drivers/i386/Win2003/viostor.cat \
	drivers/i386/Win2003/viostor.inf \
	drivers/i386/Win2003/viostor.sys \
	drivers/i386/Win2008/netkvm.cat \
	drivers/i386/Win2008/netkvm.inf \
	drivers/i386/Win2008/netkvm.sys \
	drivers/i386/Win2008/vioscsi.cat \
	drivers/i386/Win2008/vioscsi.inf \
	drivers/i386/Win2008/vioscsi.sys \
	drivers/i386/Win2008/viostor.cat \
	drivers/i386/Win2008/viostor.inf \
	drivers/i386/Win2008/viostor.sys \
	drivers/i386/Win7/netkvm.cat \
	drivers/i386/Win7/netkvm.inf \
	drivers/i386/Win7/netkvm.sys \
	drivers/i386/Win7/qxl.cat \
	drivers/i386/Win7/qxldd.dll \
	drivers/i386/Win7/qxl.inf \
	drivers/i386/Win7/qxl.sys \
	drivers/i386/Win7/vioscsi.cat \
	drivers/i386/Win7/vioscsi.inf \
	drivers/i386/Win7/vioscsi.sys \
	drivers/i386/Win7/viostor.cat \
	drivers/i386/Win7/viostor.inf \
	drivers/i386/Win7/viostor.sys \
	drivers/i386/Win8.1/netkvm.cat \
	drivers/i386/Win8.1/netkvm.inf \
	drivers/i386/Win8.1/netkvm.sys \
	drivers/i386/Win8.1/vioscsi.cat \
	drivers/i386/Win8.1/vioscsi.inf \
	drivers/i386/Win8.1/vioscsi.sys \
	drivers/i386/Win8.1/viostor.cat \
	drivers/i386/Win8.1/viostor.inf \
	drivers/i386/Win8.1/viostor.sys \
	drivers/i386/Win8/netkvm.cat \
	drivers/i386/Win8/netkvm.inf \
	drivers/i386/Win8/netkvm.sys \
	drivers/i386/Win8/vioscsi.cat \
	drivers/i386/Win8/vioscsi.inf \
	drivers/i386/Win8/vioscsi.sys \
	drivers/i386/Win8/viostor.cat \
	drivers/i386/Win8/viostor.inf \
	drivers/i386/Win8/viostor.sys \
	drivers/i386/WinXP/netkvm.cat \
	drivers/i386/WinXP/netkvm.inf \
	drivers/i386/WinXP/netkvm.sys \
	drivers/i386/WinXP/qxl.cat \
	drivers/i386/WinXP/qxldd.dll \
	drivers/i386/WinXP/qxl.inf \
	drivers/i386/WinXP/qxl.sys \
	drivers/i386/WinXP/viostor.cat \
	drivers/i386/WinXP/viostor.inf \
	drivers/i386/WinXP/viostor.sys

EXTRA_DIST = $(drivers)

check_DATA = fake-virtio-win.iso

CLEANFILES = fake-virtio-win.iso

fake-virtio-win.iso: $(drivers)
	$(GENISOIMAGE) -J -r -o $@ -graft-points drivers=drivers
