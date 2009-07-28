# libguestfs test images
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

# Old RHEL 5 autoconf doesn't have builddir.
builddir ?= $(top_builddir)/images

EXTRA_DIST = \
	helloworld.tar \
	helloworld.tar.gz \
	mbr-ext2-empty.img.gz \
	empty known-1 known-2 known-3

noinst_DATA = test.sqsh

CLEANFILES = \
	test.sqsh \
	100kallzeroes 100kallnewlines 100kallspaces 100krandom 10klines \
	initrd

squash_files_src = \
	$(srcdir)/helloworld.tar \
	$(srcdir)/helloworld.tar.gz \
	$(srcdir)/empty \
	$(srcdir)/known-1 \
	$(srcdir)/known-2 \
	$(srcdir)/known-3

squash_files_build = \
	$(builddir)/100kallzeroes \
	$(builddir)/100kallnewlines \
	$(builddir)/100kallspaces \
	$(builddir)/100krandom \
	$(builddir)/10klines \
	$(builddir)/initrd

squash_files = $(squash_files_src) $(squash_files_build)

test.sqsh: $(squash_files)
	rm -f $@
	$(MKSQUASHFS) $(squash_files) $@

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

$(builddir)/initrd: empty known-1 known-2 known-3
	rm -f $@ $@-t
	for f in $^; do echo $$f; done | cpio -o -H newc | gzip --best > $@-t
	mv $@-t $@
