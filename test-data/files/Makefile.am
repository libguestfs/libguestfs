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

EXTRA_DIST = \
	filesanddirs-10M.tar.xz \
	filesanddirs-100M.tar.xz \
	helloworld.tar \
	helloworld.tar.gz \
	helloworld.tar.xz \
	mbr-ext2-empty.img.gz \
	empty known-1 known-2 known-3 known-4 known-5 \
	test-grep.txt \
	minimal

noinst_DATA = \
	100kallzeroes \
	100kallnewlines \
	100kallspaces \
	100krandom \
	10klines \
	bin-x86_64-dynamic.gz \
	hello.b64 \
	initrd \
	initrd-x86_64.img \
	initrd-x86_64.img.gz \
	lib-i586.so.xz \
	lib-i586.so.zst \
	test-grep.txt.gz

CLEANFILES += $(noinst_DATA)

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

hello.b64:
	echo "hello" | base64 > $@

# When builddir != srcdir, names like 'empty' are rewritten as
# '../../test-data/files/empty'.  We need to copy the files into a fresh
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
initrd-x86_64.img: $(top_srcdir)/test-data/binaries/bin-x86_64-dynamic
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

bin-x86_64-dynamic.gz: $(top_srcdir)/test-data/binaries/bin-x86_64-dynamic
	rm -f $@ $@-t
	gzip --best -c $< > $@-t
	mv $@-t $@

lib-i586.so.xz: $(top_srcdir)/test-data/binaries/lib-i586.so
	rm -f $@ $@-t
	xz -c $< > $@-t
	mv $@-t $@

lib-i586.so.zst: $(top_srcdir)/test-data/binaries/lib-i586.so
	rm -f $@ $@-t
	zstd -c $< > $@-t
	mv $@-t $@
