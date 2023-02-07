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

SUBDIRS  = binaries
SUBDIRS += blank-disks
if ENABLE_APPLIANCE
SUBDIRS += phony-guests
endif
SUBDIRS += files
SUBDIRS += .

# Build an ISO containing various files from the subdirectories, which
# is used by tests/c-api and a few guestfish tests and regression
# tests.

image_files = \
	$(srcdir)/binaries/bin-aarch64-dynamic \
	$(srcdir)/binaries/bin-armv7-dynamic \
	$(srcdir)/binaries/bin-i586-dynamic \
	$(srcdir)/binaries/bin-ia64-dynamic \
	$(srcdir)/binaries/bin-mipsel-dynamic \
	$(srcdir)/binaries/bin-ppc64-dynamic \
	$(srcdir)/binaries/bin-ppc64le-dynamic \
	$(srcdir)/binaries/bin-riscv64-dynamic \
	$(srcdir)/binaries/bin-s390x-dynamic \
	$(srcdir)/binaries/bin-sparc-dynamic \
	$(srcdir)/binaries/bin-win32.exe \
	$(srcdir)/binaries/bin-win64.exe \
	$(srcdir)/binaries/bin-x86_64-dynamic \
	$(srcdir)/binaries/lib-aarch64.so \
	$(srcdir)/binaries/lib-armv7.so \
	$(srcdir)/binaries/lib-i586.so \
	$(srcdir)/binaries/lib-ia64.so \
	$(srcdir)/binaries/lib-mipsel.so \
	$(srcdir)/binaries/lib-ppc64.so \
	$(srcdir)/binaries/lib-ppc64le.so \
	$(srcdir)/binaries/lib-riscv64.so \
	$(srcdir)/binaries/lib-s390x.so \
	$(srcdir)/binaries/lib-sparc.so \
	$(srcdir)/binaries/lib-win32.dll \
	$(srcdir)/binaries/lib-win64.dll \
	$(srcdir)/binaries/lib-x86_64.so \
	$(srcdir)/files/helloworld.tar \
	$(srcdir)/files/helloworld.tar.gz \
	$(srcdir)/files/helloworld.tar.xz \
	$(srcdir)/files/empty \
	$(srcdir)/files/known-1 \
	$(srcdir)/files/known-2 \
	$(srcdir)/files/known-3 \
	$(srcdir)/files/known-4 \
	$(srcdir)/files/known-5 \
	$(srcdir)/files/test-grep.txt \
	$(srcdir)/files/minimal \
	blank-disks/blank-disk-1s.raw \
	blank-disks/blank-disk-1s.qcow2 \
	blank-disks/blank-disk-1K.raw \
	blank-disks/blank-disk-1K.qcow2 \
	blank-disks/blank-disk-1M.raw \
	blank-disks/blank-disk-1M.qcow2 \
	blank-disks/blank-disk-with-backing.qcow2 \
	files/100kallzeroes \
	files/100kallnewlines \
	files/100kallspaces \
	files/100krandom \
	files/10klines \
	files/bin-x86_64-dynamic.gz \
	files/hello.b64 \
	files/initrd \
	files/initrd-x86_64.img \
	files/initrd-x86_64.img.gz \
	files/lib-i586.so.xz \
	files/lib-i586.so.zst \
	files/test-grep.txt.gz

noinst_DATA = test.iso

CLEANFILES += test.iso

test.iso: $(images_files)
	rm -rf d
	rm -f $@ $@-t
	mkdir d
	cp $(image_files) d/
	mkdir -p d/directory
	cd d && ln -sf /10klines abssymlink
	cd d && $(MKISOFS) -J -r -o ../$@-t .
	rm -rf d
	mv $@-t $@
