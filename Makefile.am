# libguestfs
# Copyright (C) 2009-2012 Red Hat Inc.
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

ACLOCAL_AMFLAGS = -I m4

# Gnulib - must be built and tested before the library.
SUBDIRS = gnulib/lib gnulib/tests

# Basic source for the library.
SUBDIRS += tests/data generator src examples po

if ENABLE_DAEMON
SUBDIRS += daemon
endif
if ENABLE_APPLIANCE
SUBDIRS += appliance
endif

# Tests - order is important.
if ENABLE_APPLIANCE
SUBDIRS += tests/qemu
SUBDIRS += tests/guests
SUBDIRS += tests/c-api
SUBDIRS += tests/protocol
SUBDIRS += tests/lvm
SUBDIRS += tests/luks
SUBDIRS += tests/md
SUBDIRS += tests/regressions
endif

# Extra tests don't run by default.  You have to do 'make extra-tests'.
SUBDIRS += tests/extra

# libguestfs-test-tool
SUBDIRS += test-tool

# Guestfish.
SUBDIRS += fish

# virt-tools in C.
SUBDIRS += align cat df edit format inspector rescue

# Language bindings.
if HAVE_PERL
SUBDIRS += perl perl/examples
endif
if HAVE_OCAML
SUBDIRS += ocaml ocaml/examples
endif
if HAVE_PYTHON
SUBDIRS += python python/examples
endif
if HAVE_RUBY
SUBDIRS += ruby ruby/examples
endif
if HAVE_JAVA
SUBDIRS += java java/examples
endif
if HAVE_HASKELL
SUBDIRS += haskell
endif
if HAVE_PHP
SUBDIRS += php
endif
if HAVE_ERLANG
SUBDIRS += erlang erlang/examples
endif
if HAVE_GOBJECT
SUBDIRS += gobject
endif

# Unconditional because nothing is built yet.
SUBDIRS += csharp

# OCaml tools.
if HAVE_OCAML
SUBDIRS += resize sparsify
endif

# Perl tools.
if HAVE_TOOLS
SUBDIRS += tools
endif

# guestmount
if HAVE_FUSE
SUBDIRS += fuse
endif

# virt-tools in shell.  This uses guestmount and virt-inspector.
if HAVE_FUSE
SUBDIRS += clone
endif

# po-docs must come after tools, inspector.
if HAVE_PO4A
SUBDIRS += po-docs
endif

EXTRA_DIST = \
	$(generator_built) \
	BUGS HACKING RELEASE-NOTES ROADMAP TODO \
	.gitignore \
	bugs-in-changelog.sh \
	autogen.sh \
	bindtests \
	contrib/autobuild/autobuild.sh \
	contrib/guestfsd-in-wine.sh \
	contrib/intro/libguestfs-intro.html \
	contrib/intro/overview.svg \
	contrib/intro/talk.txt \
	contrib/intro/tools.svg \
	contrib/make-check-on-installed.pl \
	contrib/README \
	contrib/visualize-alignment/.gitignore \
	contrib/visualize-alignment/guestfish-add-mount.qtr \
	contrib/visualize-alignment/guestfish-lv-ext4-4k.qtr \
	contrib/visualize-alignment/guestfish-lv-ext4-4k-write-hello.qtr \
	contrib/visualize-alignment/guestfish-N-fs-10M-aligned-part-disk.qtr \
	contrib/visualize-alignment/guestfish-N-fs-10M.qtr \
	contrib/visualize-alignment/guestfish-write-hello.qtr \
	contrib/visualize-alignment/qemu-0.13-trace-block-device-access.patch \
	contrib/visualize-alignment/README \
	contrib/visualize-alignment/tracetops.ml \
	debian/.gitignore \
	debian/changelog \
	debian/compat \
	debian/control \
	debian/copyright \
	debian/docs \
	debian/guestfish.dirs \
	debian/guestfish.install \
	debian/guestfsd.dirs \
	debian/guestfsd.install \
	debian/guestmount.dirs \
	debian/guestmount.install \
	debian/libguestfs-dev.dirs \
	debian/libguestfs-dev.install \
	debian/libguestfs-doc.docs \
	debian/libguestfs-perl.examples \
	debian/libguestfs-perl.install \
	debian/libguestfs-tools.dirs \
	debian/libguestfs-tools.install \
	debian/libguestfs0.dirs \
	debian/libguestfs0.install \
	debian/patches/series \
	debian/python-guestfs.install \
	debian/pyversions \
	debian/rules \
	debian/shlibs.local \
	debian/watch \
	html/pod.css \
	libguestfs.pc libguestfs.pc.in \
	libtool-kill-dependency_libs.sh \
	logo/fish.svg logo/fish.png \
	m4/.gitignore \
	po/remove-potcdate.sin \
	update-bugs.sh

# The website.
HTMLFILES = \
	html/guestfs.3.html \
	html/guestfs-examples.3.html \
	html/guestfs-erlang.3.html \
	html/guestfs-java.3.html \
	html/guestfs-ocaml.3.html \
	html/guestfs-perl.3.html \
	html/guestfs-python.3.html \
	html/guestfs-recipes.1.html \
	html/guestfs-ruby.3.html \
	html/guestfs-testing.1.html \
	html/guestfish.1.html \
	html/guestmount.1.html \
	html/virt-alignment-scan.1.html \
	html/virt-cat.1.html \
	html/virt-copy-in.1.html \
	html/virt-copy-out.1.html \
	html/virt-df.1.html \
	html/virt-edit.1.html \
	html/virt-filesystems.1.html \
	html/virt-format.1.html \
	html/virt-inspector.1.html \
	html/virt-list-filesystems.1.html \
	html/virt-list-partitions.1.html \
	html/virt-ls.1.html \
	html/virt-make-fs.1.html \
	html/virt-rescue.1.html \
	html/virt-resize.1.html \
	html/virt-sparsify.1.html \
	html/virt-sysprep.1.html \
	html/virt-tar.1.html \
	html/virt-tar-in.1.html \
	html/virt-tar-out.1.html \
	html/virt-win-reg.1.html

TEXTFILES = BUGS README RELEASE-NOTES ROADMAP TODO

WEBSITEDIR = $(HOME)/d/redhat/websites/libguestfs

# For reasons not fully understood, we need to rebuild all the
# man pages and HTMLFILES from scratch here.
website: $(HTMLFILES) $(TEXTFILES)
	find -name 'stamp-*.pod' -delete
	$(MAKE)
	cp $(HTMLFILES) $(WEBSITEDIR)
	for f in $(TEXTFILES); do cp $$f $(WEBSITEDIR)/$$f.txt; done
	cd $(WEBSITEDIR) && \
	date=`date +%F`; \
	sed -e "s/SUBST_VERSION/$(VERSION)/" \
	    -e "s/SUBST_DATE/$$date/" \
	< index.html.in > index.html

# When doing 'make dist' update a few files automatically.
dist-hook:
	$(top_srcdir)/build-aux/gitlog-to-changelog > ChangeLog
	cp ChangeLog $(distdir)/ChangeLog
	$(top_srcdir)/update-bugs.sh > BUGS-t
	mv BUGS-t BUGS
	cp BUGS $(distdir)/BUGS
	git log --pretty="format:%an <%ae>" | sort -u | uniq -w 10 | \
		grep -v rjones | \
		grep -v "Richard Jones" \
		> AUTHORS-t
	mv AUTHORS-t AUTHORS
	cp AUTHORS $(distdir)/AUTHORS

# Update the list of translatable files in po/POTFILES.in.
all-local:
	cd $(srcdir); \
	find $(DIST_SUBDIRS) \
	    -name '*.c' -o -name '*.pl' -o -name '*.pm' | \
	grep -v '^perl/blib/' | \
	grep -v '^tests/' | \
	grep -v '^daemon/lib/' | \
	grep -v '^daemon/tests/' | \
	grep -v '^examples/' | \
	grep -v '^gnulib/' | \
	grep -v '^perl/examples/' | \
	grep -v '/guestfs_protocol.c' | \
	grep -v '/rc_protocol.c' | \
	grep -v '^po-docs/' | \
	grep -v '^images/' | \
	LC_ALL=C sort | \
	sed 's,^\./,,' > po/POTFILES.in

# Pkgconfig.

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = libguestfs.pc

# Make clean.

CLEANFILES = \
	pod2htm?.tmp \
	html/*.html

# If you don't want to run all of the tests ('make check') then this
# will just run libguestfs-test-tool for a quick check.  Note this
# is NOT a substitute for proper testing!

quickcheck:
	./run test-tool/libguestfs-test-tool $(QUICKCHECK_TEST_TOOL_ARGS)

# Run extra-tests in tests/extra/ subdirectory.

extra-tests:
	make -C tests/extra $@

# Make binary distribution.

BINTMPDIR = /tmp/libguestfs-bin
bindist:
	rm -rf $(BINTMPDIR)
	mkdir $(BINTMPDIR)
	$(MAKE)
	$(MAKE) DESTDIR=$(BINTMPDIR) install
	-find $(BINTMPDIR) -type d -exec rmdir --ignore-fail-on-non-empty {} \;
	(cd $(BINTMPDIR) && tar cf - .) | \
	  gzip -c -9 > libguestfs-$(VERSION)-$(DISTRO)-$(host_cpu).tar.gz
