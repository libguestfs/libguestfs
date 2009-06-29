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

EXTRA_DIST	= \
	helloworld.tar \
	helloworld.tar.gz \
	mbr-ext2-empty.img.gz \
	empty known-1 known-2 known-3

noinst_DATA = test.sqsh

CLEANFILES = test.sqsh

squash_files = helloworld.tar helloworld.tar.gz empty known-1 known-2 known-3 \
	100kallzeroes 100kallnewlines 100kallspaces 100krandom 10klines \
	initrd

test.sqsh: $(squash_files)
	rm -f $@
	$(MKSQUASHFS) $(squash_files) $@

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

initrd: empty known-1 known-2 known-3
	rm -f $@ $@-t
	for f in $^; do echo $$f; done | cpio -o -H newc | gzip --best > $@-t
	mv $@-t $@
