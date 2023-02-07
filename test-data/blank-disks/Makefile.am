# libguestfs test images
# Copyright (C) 2009-2023 Red Hat Inc.
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

files = \
	blank-disk-1s.raw \
	blank-disk-1s.qcow2 \
	blank-disk-1K.raw \
	blank-disk-1K.qcow2 \
	blank-disk-1M.raw \
	blank-disk-1M.qcow2 \
	blank-disk-with-backing.qcow2

noinst_DATA = $(files)

CLEANFILES += $(files)

# Blank disk images in various sizes and formats.
blank-disk-1s.raw:
	qemu-img create -f raw $@ 512

blank-disk-1s.qcow2:
	qemu-img create -f qcow2 -o preallocation=metadata $@ 512

blank-disk-1K.raw:
	qemu-img create -f raw $@ 1K

blank-disk-1K.qcow2:
	qemu-img create -f qcow2 -o preallocation=metadata $@ 1K

blank-disk-1M.raw:
	qemu-img create -f raw $@ 1M

blank-disk-1M.qcow2:
	qemu-img create -f qcow2 -o preallocation=metadata $@ 1M

blank-disk-with-backing.qcow2: blank-disk-1M.raw
	qemu-img create -f qcow2 -b $^ -F raw $@
