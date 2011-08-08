# libguestfs test images
# Copyright (C) 2009-2010 Red Hat Inc.
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

include $(top_srcdir)/subdir-rules.mk

# Old RHEL 5 autoconf doesn't have builddir.
builddir ?= $(top_builddir)/images

EXTRA_DIST = \
	helloworld.tar \
	helloworld.tar.gz \
	helloworld.tar.xz \
	mbr-ext2-empty.img.gz \
	empty known-1 known-2 known-3 known-4 known-5 \
	bin-i586-dynamic \
	bin-sparc-dynamic \
	bin-win32.exe \
	bin-win64.exe \
	bin-x86_64-dynamic \
	lib-i586.so \
	lib-sparc.so \
	lib-win32.dll \
	lib-win64.dll \
	lib-x86_64.so \
	test-grep.txt \
	guest-aux/make-debian-img.sh \
	guest-aux/debian-packages \
	guest-aux/make-fedora-img.sh \
	guest-aux/fedora-name.db.txt \
	guest-aux/fedora-name.db \
	guest-aux/fedora-packages.db.txt \
	guest-aux/fedora-packages.db \
	guest-aux/make-ubuntu-img.sh \
	guest-aux/make-windows-img.sh \
	guest-aux/windows-software \
	guest-aux/windows-software.reg \
	guest-aux/windows-system \
	guest-aux/windows-system.reg \
	guest-aux/minimal-hive

noinst_DATA = test.iso

# This is 'check_DATA' because we don't need it until 'make check'
# time and we need the tools we have built in order to make it.
check_DATA = debian.img fedora.img ubuntu.img windows.img

CLEANFILES = \
	test.iso test.sqsh \
	100kallzeroes 100kallnewlines 100kallspaces 100krandom 10klines \
	initrd $(check_DATA)

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
	$(srcdir)/bin-i586-dynamic \
	$(srcdir)/bin-sparc-dynamic \
	$(srcdir)/bin-win32.exe \
	$(srcdir)/bin-win64.exe \
	$(srcdir)/bin-x86_64-dynamic \
	$(srcdir)/lib-i586.so \
	$(srcdir)/lib-sparc.so \
	$(srcdir)/lib-win32.dll \
	$(srcdir)/lib-win64.dll \
	$(srcdir)/lib-x86_64.so \
	$(srcdir)/test-grep.txt

images_files_build = \
	$(builddir)/100kallzeroes \
	$(builddir)/100kallnewlines \
	$(builddir)/100kallspaces \
	$(builddir)/100krandom \
	$(builddir)/10klines \
	$(builddir)/abssymlink \
	$(builddir)/hello.b64 \
	$(builddir)/initrd \
	$(builddir)/initrd-x86_64.img \
	$(builddir)/initrd-x86_64.img.gz \
	$(builddir)/test-grep.txt.gz

images_files = $(images_files_src) $(images_files_build)

test.iso: $(images_files)
	rm -f $@ $@-t
	mkdir -p directory
	$(GENISOIMAGE) -J -r -graft-points \
	  -o $@-t \
	  $(images_files) /directory=directory
	rmdir directory
	mv $@-t $@

$(builddir)/100kallzeroes:
	rm -f $@ $@-t
	dd if=/dev/zero of=$@-t bs=1024 count=100
	mv $@-t $@

$(builddir)/100kallnewlines: $(builddir)/100kallzeroes
	rm -f $@ $@-t
	tr '\0' '\n' < $< > $@-t
	mv $@-t $@

$(builddir)/100kallspaces: $(builddir)/100kallzeroes
	rm -f $@ $@-t
	tr '\0' ' ' < $< > $@-t
	mv $@-t $@

$(builddir)/100krandom:
	rm -f $@ $@-t
	dd if=/dev/urandom of=$@-t bs=1024 count=100
	mv $@-t $@

$(builddir)/10klines:
	rm -f $@ $@-t
	i=0; \
	while [ $$i -lt 10000 ]; do \
	  echo "$${i}abcdefghijklmnopqrstuvwxyz"; \
	  i=$$(($$i+1)); \
	done > $@-t
	mv $@-t $@

$(builddir)/abssymlink:
	ln -sf /10klines $@

$(builddir)/hello.b64:
	echo "hello" | base64 > $@

$(builddir)/initrd: empty known-1 known-2 known-3 known-4 known-5
	rm -f $@ $@-t
	for f in $^; do echo $$f; done | cpio -o -H newc | gzip --best > $@-t
	mv $@-t $@

# Create a dummy initrd with a single file called 'bin/nash' which
# is used to test the Sys::Guestfs::Lib::file_architecture function.
$(builddir)/initrd-x86_64.img: bin-x86_64-dynamic
	rm -rf bin $@ $@-t
	mkdir bin
	cp $< bin/nash
	echo bin/nash | cpio -o -H newc > $@-t
	mv $@-t $@
	rm -rf bin $@-t

$(builddir)/initrd-x86_64.img.gz: initrd-x86_64.img
	rm -f $@ $@-t
	gzip --best -c $< > $@-t
	mv $@-t $@

$(builddir)/test-grep.txt.gz: test-grep.txt
	rm -f $@ $@-t
	gzip --best -c $< > $@-t
	mv $@-t $@

# Make a (dummy) Fedora image.
fedora.img: guest-aux/make-fedora-img.sh \
		guest-aux/fedora-name.db \
		guest-aux/fedora-packages.db
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	TMPDIR=$(top_builddir) \
	bash $<

guest-aux/fedora-name.db: guest-aux/fedora-name.db.txt
	rm -f $@ $@-t
	$(DB_LOAD) $@-t < $<
	mv $@-t $@

guest-aux/fedora-packages.db: guest-aux/fedora-packages.db.txt
	rm -f $@ $@-t
	$(DB_LOAD) $@-t < $<
	mv $@-t $@

# Make a (dummy) Debian image.
debian.img: guest-aux/make-debian-img.sh
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	TMPDIR=$(top_builddir) \
	bash $<

# Make a (dummy) Ubuntu image.
ubuntu.img: guest-aux/make-ubuntu-img.sh
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	TMPDIR=$(top_builddir) \
	bash $<

# Make a (dummy) Windows image.
windows.img: guest-aux/make-windows-img.sh \
	     guest-aux/windows-software guest-aux/windows-system
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	TMPDIR=$(top_builddir) \
	bash $<

# Since users might not have the tools needed to create this, we
# also distribute these files.
guest-aux/windows-software: guest-aux/windows-software.reg
	rm -f $@ $@-t
	cp guest-aux/minimal-hive $@-t
	hivexregedit --merge $@-t --prefix 'HKEY_LOCAL_MACHINE\SOFTWARE' $<
	mv $@-t $@

guest-aux/windows-system: guest-aux/windows-system.reg
	rm -f $@ $@-t
	cp guest-aux/minimal-hive $@-t
	hivexregedit --merge $@-t --prefix 'HKEY_LOCAL_MACHINE\SYSTEM' $<
	mv $@-t $@
