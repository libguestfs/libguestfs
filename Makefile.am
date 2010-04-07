# libguestfs
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

ACLOCAL_AMFLAGS = -I m4

SUBDIRS = gnulib/lib src

if ENABLE_DAEMON
SUBDIRS += daemon
endif
if ENABLE_APPLIANCE
SUBDIRS += appliance
endif

SUBDIRS += fish po examples images
SUBDIRS += gnulib/tests capitests regressions test-tool

if HAVE_PERL
SUBDIRS += perl
endif

if HAVE_INSPECTOR
SUBDIRS += inspector
endif
if HAVE_TOOLS
SUBDIRS += tools
endif

if HAVE_FUSE
SUBDIRS += fuse
endif

if HAVE_OCAML
SUBDIRS += ocaml ocaml/examples
endif
if HAVE_PYTHON
SUBDIRS += python
endif
if HAVE_RUBY
SUBDIRS += ruby
endif
if HAVE_JAVA
SUBDIRS += java
endif
if HAVE_HASKELL
SUBDIRS += haskell
endif

EXTRA_DIST = \
	$(generator_built) \
	html/pod.css \
	HACKING TODO \
	libguestfs.pc libguestfs.pc.in \
	recipes/LICENSE \
	recipes/README \
	recipes/*.html \
	recipes/*.sh \
	recipes/*.example \
	html/recipes.css \
	make-recipes.sh \
	contrib/README \
	bindtests \
	.gitignore \
	m4/.gitignore

# HTML versions of manual pages.

noinst_DATA = html/guestfs.3.html html/guestfish.1.html

html/guestfs.3.html: src/guestfs.pod \
		src/guestfs-actions.pod \
		src/guestfs-availability.pod \
		src/guestfs-structs.pod
	mkdir -p html
	sed \
	  -e '/@ACTIONS@/rsrc/guestfs-actions.pod' \
	  -e 's/@ACTIONS@//' \
	  -e '/@AVAILABILITY@/rsrc/guestfs-availability.pod' \
	  -e 's/@AVAILABILITY@//' \
	  -e '/@STRUCTS@/rsrc/guestfs-structs.pod' \
	  -e 's/@STRUCTS@//' \
	  < $< | \
	pod2html \
	  --css 'pod.css' \
	  --title "libguestfs API documentation" \
	  --htmldir html \
	  --outfile $@

html/guestfish.1.html: fish/guestfish.pod fish/guestfish-actions.pod
	mkdir -p html
	sed \
	  -e '/@ACTIONS@/rfish/guestfish-actions.pod' -e 's/@ACTIONS@//' \
	  < $< | \
	pod2html \
	  --css 'pod.css' \
	  --title "guestfish, libguestfs filesystem interactive shell" \
	  --htmldir html \
	  --outfile $@

# Recipes web page.
html/recipes.html: $(wildcard recipes/*.sh) $(wildcard recipes/*.html) $(wildcard recipes/*.example) Makefile make-recipes.sh
	mkdir -p html
	rm -f $@ $@-t
	sh make-recipes.sh recipes/*.sh > $@-t
	mv $@-t $@

HTMLFILES = \
	html/guestfs.3.html \
	html/guestfish.1.html \
	html/guestmount.1.html \
	html/virt-cat.1.html \
	html/virt-df.1.html \
	html/virt-edit.1.html \
	html/virt-inspector.1.html \
	html/virt-list-filesystems.1.html \
	html/virt-list-partitions.1.html \
	html/virt-ls.1.html \
	html/virt-make-fs.1.html \
	html/virt-rescue.1.html \
	html/virt-resize.1.html \
	html/virt-tar.1.html \
	html/virt-win-reg.1.html \
	html/recipes.html \
	html/pod.css html/recipes.css

TEXTFILES = README TODO HACKING

WEBSITEDIR = $(HOME)/d/redhat/websites/libguestfs

website: $(HTMLFILES) $(TEXTFILES)
	cp $(HTMLFILES) $(WEBSITEDIR)
	for f in $(TEXTFILES); do cp $$f $(WEBSITEDIR)/$$f.txt; done
	cd $(WEBSITEDIR) && \
	date=`date +%F`; \
	sed -e "s/SUBST_VERSION/$(VERSION)/" \
	    -e "s/SUBST_DATE/$$date/" \
	< index.html.in > index.html

# Generate the ChangeLog automatically from the gitlog.

dist-hook:
	$(top_srcdir)/build-aux/gitlog-to-changelog > ChangeLog
	cp ChangeLog $(distdir)/ChangeLog

# Update the list of translatable files in po/POTFILES.in.
all-local:
	cd $(srcdir); \
	find $(DIST_SUBDIRS) \
	    -name '*.c' -o -name '*.pl' -o -name '*.pm' -o \
	    -name 'virt-cat' -o \
	    -name 'virt-df' -o \
	    -name 'virt-edit' -o \
	    -name 'virt-inspector' -o \
	    -name 'virt-list-filesystems' -o \
	    -name 'virt-list-partitions' -o \
	    -name 'virt-ls' -o \
	    -name 'virt-make-fs' -o \
	    -name 'virt-rescue' -o \
	    -name 'virt-resize' -o \
	    -name 'virt-tar' -o \
	    -name 'virt-win-reg' | \
	grep -v '^perl/blib/' | \
	grep -v '^capitests/' | \
	grep -v '^daemon/lib/' | \
	grep -v '^daemon/tests/' | \
	grep -v '^examples/' | \
	grep -v '^gnulib/' | \
	grep -v '^perl/examples/' | \
	grep -v '/guestfs_protocol.c' | \
	grep -v '/rc_protocol.c' | \
	grep -v 'appliance/debian/root' | \
	LC_ALL=C sort | \
	sed 's,^\./,,' > po/POTFILES.in

# Pkgconfig.

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = libguestfs.pc

# Make clean.

CLEANFILES = $(fs_DATA) \
	emptydisk \
	pod2htm?.tmp \
	html/*.html \
	guestfs.3 guestfish.1

clean-local:
	rm -rf initramfs

# If you don't want to run all of the tests ('make check') then this
# will just run libguestfs-test-tool for a quick check.  Note this
# is NOT a substitute for proper testing!

quickcheck:
	LIBGUESTFS_PATH=appliance \
	test-tool/libguestfs-test-tool \
	  --helper test-tool/libguestfs-test-tool-helper
