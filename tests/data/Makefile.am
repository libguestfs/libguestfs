# libguestfs test images
# Copyright (C) 2009-2014 Red Hat Inc.
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
	README-binfiles \
	filesanddirs-10M.tar.xz \
	filesanddirs-100M.tar.xz \
	helloworld.tar \
	helloworld.tar.gz \
	helloworld.tar.xz \
	mbr-ext2-empty.img.gz \
	empty known-1 known-2 known-3 known-4 known-5 \
	bin-aarch64-dynamic \
	bin-armv7-dynamic \
	bin-i586-dynamic \
	bin-sparc-dynamic \
	bin-win32.exe \
	bin-win64.exe \
	bin-x86_64-dynamic \
	lib-aarch64.so \
	lib-armv7.so \
	lib-i586.so \
	lib-sparc.so \
	lib-win32.dll \
	lib-win64.dll \
	lib-x86_64.so \
	test-grep.txt \
	minimal

images_files_src = \
	$(srcdir)/helloworld.tar \
	$(srcdir)/helloworld.tar.gz \
	$(srcdir)/helloworld.tar.xz \
	$(srcdir)/empty \
	$(srcdir)/known-1 \
	$(srcdir)/known-2 \
	$(srcdir)/known-3 \
	$(srcdir)/known-4 \
	$(srcdir)/known-5 \
	$(srcdir)/bin-aarch64-dynamic \
	$(srcdir)/bin-armv7-dynamic \
	$(srcdir)/bin-i586-dynamic \
	$(srcdir)/bin-sparc-dynamic \
	$(srcdir)/bin-win32.exe \
	$(srcdir)/bin-win64.exe \
	$(srcdir)/bin-x86_64-dynamic \
	$(srcdir)/lib-aarch64.so \
	$(srcdir)/lib-armv7.so \
	$(srcdir)/lib-i586.so \
	$(srcdir)/lib-sparc.so \
	$(srcdir)/lib-win32.dll \
	$(srcdir)/lib-win64.dll \
	$(srcdir)/lib-x86_64.so \
	$(srcdir)/test-grep.txt \
	$(srcdir)/minimal

images_files_build = \
	100kallzeroes \
	100kallnewlines \
	100kallspaces \
	100krandom \
	10klines \
	bin-x86_64-dynamic.gz \
	blank-disk-1s.raw \
	blank-disk-1s.qcow2 \
	blank-disk-1K.raw \
	blank-disk-1K.qcow2 \
	blank-disk-1M.raw \
	blank-disk-1M.qcow2 \
	blank-disk-with-backing.qcow2 \
	hello.b64 \
	initrd \
	initrd-x86_64.img \
	initrd-x86_64.img.gz \
	lib-i586.so.xz \
	test-grep.txt.gz

check_DATA = $(images_files_build) test.iso

CLEANFILES = $(images_files_build) test.iso

images_files = $(images_files_src) $(images_files_build)

test.iso: $(images_files)
	rm -f $@ $@-t
	mkdir -p directory
	ln -sf /10klines abssymlink
	$(GENISOIMAGE) -J -r -graft-points \
	  -o $@-t \
	  $(images_files) /directory=directory abssymlink
	rmdir directory
	rm abssymlink
	mv $@-t $@

100kallzeroes:
	rm -f $@ $@-t
	dd if=/dev/zero of=$@-t bs=1024 count=100
	mv $@-t $@

100kallnewlines: 100kallzeroes
	rm -f $@ $@-t
	tr '\0' '\n' < $< > $@-t
	mv $@-t $@

100kallspaces: 100kallzeroes
	rm -f $@ $@-t
	tr '\0' ' ' < $< > $@-t
	mv $@-t $@

100krandom:
	rm -f $@ $@-t
	dd if=/dev/urandom of=$@-t bs=1024 count=100
	mv $@-t $@

10klines:
	rm -f $@ $@-t
	i=0; \
	while [ $$i -lt 10000 ]; do \
	  echo "$${i}abcdefghijklmnopqrstuvwxyz"; \
	  i=$$(($$i+1)); \
	done > $@-t
	mv $@-t $@

# Blank disk images in various sizes and formats.
blank-disk-1s.raw:
	rm -f $@
	../../fish/guestfish sparse $@ 512

blank-disk-1s.qcow2:
	qemu-img create -f qcow2 -o preallocation=metadata $@ 512

blank-disk-1K.raw:
	rm -f $@
	../../fish/guestfish sparse $@ 1K

blank-disk-1K.qcow2:
	qemu-img create -f qcow2 -o preallocation=metadata $@ 1K

blank-disk-1M.raw:
	rm -f $@
	../../fish/guestfish sparse $@ 1M

blank-disk-1M.qcow2:
	qemu-img create -f qcow2 -o preallocation=metadata $@ 1M

blank-disk-with-backing.qcow2: blank-disk-1M.raw
	qemu-img create -f qcow2 -b $^ $@

hello.b64:
	echo "hello" | base64 > $@

# When builddir != srcdir, names like 'empty' are rewritten as
# '../../tests/data/empty'.  We need to copy the files into a fresh
# subdirectory in order to create the initrd correctly.
initrd: empty known-1 known-2 known-3 known-4 known-5
	rm -rf init.tmp $@ $@-t
	mkdir -p init.tmp
	cp $^ init.tmp
	(cd init.tmp; ls -1 * | cpio -o -H newc | gzip --best) > $@-t
	rm -r init.tmp
	mv $@-t $@

# Create a dummy initrd with a single file called 'bin/nash' which
# is used to test the file_architecture function.
initrd-x86_64.img: bin-x86_64-dynamic
	rm -rf bin $@ $@-t
	mkdir bin
	cp $< bin/nash
	echo bin/nash | cpio -o -H newc > $@-t
	mv $@-t $@
	rm -rf bin $@-t

initrd-x86_64.img.gz: initrd-x86_64.img
	rm -f $@ $@-t
	gzip --best -c $< > $@-t
	mv $@-t $@

test-grep.txt.gz: test-grep.txt
	rm -f $@ $@-t
	gzip --best -c $< > $@-t
	mv $@-t $@

bin-x86_64-dynamic.gz: bin-x86_64-dynamic
	rm -f $@ $@-t
	gzip --best -c $< > $@-t
	mv $@-t $@

lib-i586.so.xz: lib-i586.so
	rm -f $@ $@-t
	xz -c $< > $@-t
	mv $@-t $@
