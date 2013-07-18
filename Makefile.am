# libguestfs
# Copyright (C) 2009-2013 Red Hat Inc.
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

-include $(top_builddir)/localenv

include $(top_srcdir)/subdir-rules.mk
include $(top_srcdir)/common-rules.mk

ACLOCAL_AMFLAGS = -I m4

# Gnulib - must be built and tested before the library.
SUBDIRS = gnulib/lib gnulib/tests

# Basic source for the library.
SUBDIRS += tests/data generator src examples po

if ENABLE_DAEMON
SUBDIRS += daemon
endif
SUBDIRS += appliance

# Tests - order is important.
if ENABLE_APPLIANCE
SUBDIRS += tests/qemu
SUBDIRS += tests/guests
SUBDIRS += tests/c-api
SUBDIRS += tests/tmpdirs
SUBDIRS += tests/protocol
SUBDIRS += tests/parallel
SUBDIRS += tests/disks
SUBDIRS += tests/lvm
SUBDIRS += tests/luks
SUBDIRS += tests/md
SUBDIRS += tests/selinux
SUBDIRS += tests/ntfsclone
SUBDIRS += tests/btrfs
SUBDIRS += tests/charsets
SUBDIRS += tests/xml
SUBDIRS += tests/mount-local
#SUBDIRS += tests/9p
SUBDIRS += tests/rsync
SUBDIRS += tests/bigdirs
SUBDIRS += tests/disk-labels
SUBDIRS += tests/hotplug
SUBDIRS += tests/regressions
endif

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
if HAVE_LUA
SUBDIRS += lua lua/examples
endif
if HAVE_GOBJECT
SUBDIRS += gobject
endif

# Unconditional because nothing is built yet.
SUBDIRS += csharp

# OCaml tools.
if HAVE_OCAML
SUBDIRS += mllib resize sparsify sysprep
endif

# Perl tools.
if HAVE_TOOLS
SUBDIRS += tools
endif

# guestmount
if HAVE_FUSE
SUBDIRS += fuse
endif

# po-docs must come after tools, inspector.
if HAVE_PO4A
SUBDIRS += po-docs
endif

EXTRA_DIST = \
	$(generator_built) \
	BUGS HACKING ROADMAP TODO \
	.gitignore \
	.lvimrc \
	.mailmap \
	.tx/config \
	bugs-in-changelog.sh \
	autogen.sh \
	bindtests \
	contrib/autobuild/autobuild.sh \
	contrib/intro/libguestfs-intro.html \
	contrib/intro/overview.png \
	contrib/intro/overview.svg \
	contrib/intro/talk.txt \
	contrib/intro/tools.png \
	contrib/intro/tools.svg \
	contrib/intro/virt-manager-t.png \
	contrib/intro/virt-manager.png \
	contrib/intro/vmm-icons-t.png \
	contrib/intro/vmm-icons.png \
	contrib/intro/win7.xml \
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
	guestfs-release-notes.pod \
	guestfs-release-notes.txt \
	html/draft.png \
	html/draft.svg \
	html/pod.css \
	libtool-kill-dependency_libs.sh \
	logo/fish.svg logo/fish.png \
	m4/.gitignore \
	tmp/.gitignore \
	tx-pull.sh \
	update-bugs.sh \
	valgrind-suppressions

# The website.
HTMLFILES = \
	html/guestfs.3.html \
	html/guestfs-examples.3.html \
	html/guestfs-erlang.3.html \
	html/guestfs-faq.1.html \
	html/guestfs-java.3.html \
	html/guestfs-lua.3.html \
	html/guestfs-ocaml.3.html \
	html/guestfs-performance.1.html \
	html/guestfs-perl.3.html \
	html/guestfs-python.3.html \
	html/guestfs-recipes.1.html \
	html/guestfs-release-notes.1.html \
	html/guestfs-ruby.3.html \
	html/guestfs-testing.1.html \
	html/guestfsd.8.html \
	html/guestfish.1.html \
	html/guestmount.1.html \
	html/libguestfs-make-fixed-appliance.1.html \
	html/libguestfs-test-tool.1.html \
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

HTMLSUPPORTFILES = html/draft.png html/pod.css

TEXTFILES = BUGS README ROADMAP TODO

WEBSITEDIR = $(HOME)/d/redhat/websites/libguestfs

# For reasons not fully understood, we need to rebuild all the
# man pages and HTMLFILES from scratch here.
website: $(HTMLFILES) $(TEXTFILES)
	find -name 'stamp-*.pod' -delete
	$(MAKE)
	cp $(HTMLFILES) $(HTMLSUPPORTFILES) $(WEBSITEDIR)
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
	git shortlog -se | awk -F'\t' '{print $$2}' | sort -f > AUTHORS-t
	mv AUTHORS-t AUTHORS
	cp AUTHORS $(distdir)/AUTHORS

# Update the list of translatable files (po/POTFILES po/POTFILES-ml).
# This has to be in the top-level Makefile.am so that we have access
# to DIST_SUBDIRS.
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
	sed 's,^\./,,' > po/POTFILES
	cd $(srcdir); \
	find resize sparsify sysprep -name '*.ml' | \
	LC_ALL=C sort > po/POTFILES-ml

# Manual pages in top level directory.

man_MANS = \
	guestfs-release-notes.1
noinst_DATA = \
	$(top_builddir)/html/guestfs-release-notes.1.html

guestfs-release-notes.1 guestfs-release-notes.txt $(top_builddir)/html/guestfs-release-notes.1.html: stamp-guestfs-release-notes.pod

stamp-guestfs-release-notes.pod: guestfs-release-notes.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-release-notes.1 \
	  --text guestfs-release-notes.txt \
	  --html $(top_builddir)/html/guestfs-release-notes.1.html \
	  --license GPLv2+ \
	  $<
	touch $@

# NB. podwrapper is an internal tool, so the man page mustn't be installed.
noinst_MANS = podwrapper.1
podwrapper.1: podwrapper.pl
	$(PODWRAPPER) \
	  --section 1 \
	  --man $@-t \
	  --license GPLv2+ \
	  $<
	mv $@-t $@

# Make clean.

CLEANFILES = \
	*~ \
	html/*.html \
	pod2htm?.tmp \
	podwrapper.1 \
	qemu-wrapper.sh \
	stamp-guestfs-release-notes.pod \
	tmp/disk* \
	tmp/run-* \
	tmp/valgrind-*.log

clean-local:
	-rm -rf tmp/libguestfs??????
	-rm -rf tmp/guestfs.*
	-rm -rf tmp/.guestfs-*

# If you don't want to run all of the tests ('make check') then this
# will just run libguestfs-test-tool for a quick check.  Note this
# is NOT a substitute for proper testing!

quickcheck:
	$(top_builddir)/run test-tool/libguestfs-test-tool $(QUICKCHECK_TEST_TOOL_ARGS)

# Non-standard tests.

extra-tests:
	$(MAKE) -j1 \
	  check-valgrind \
	  check-valgrind-local-guests \
	  check-with-appliance \
	  check-valgrind-with-appliance \
	  check-with-upstream-qemu \
	  check-with-upstream-libvirt \
	  check-slow

check-all:
	$(MAKE) -j1 \
	  check \
	  check-valgrind \
	  check-valgrind-local-guests \
	  check-with-appliance \
	  check-valgrind-with-appliance \
	  check-with-upstream-qemu \
	  check-with-upstream-libvirt \
	  check-slow

check-release:
	$(MAKE) -j1 \
	  check \
	  check-valgrind \
	  check-with-appliance \
	  check-valgrind-with-appliance \
	  check-slow

check-valgrind: build-test-guests
	@errors=0; \
	for f in `grep -l '^$@:' $(SUBDIRS:%=%/Makefile.am)`; do \
	  echo $(MAKE) -C `dirname $$f` $@; \
	  $(MAKE) -C `dirname $$f` $@ || (( errors++ )); \
	done; \
	exit $$(( $$errors ? 1 : 0 ))

check-valgrind-local-guests:
	@GUESTS=`$(top_builddir)/run ./pick-guests.pl 5`; \
	errors=0; \
	for f in `grep -l '^$@:' $(SUBDIRS:%=%/Makefile.am)`; do \
	  echo $(MAKE) GUESTS="$$GUESTS" -C `dirname $$f` $@; \
	  $(MAKE) GUESTS="$$GUESTS" -C `dirname $$f` $@ || (( errors++ )); \
	done; \
	exit $$(( $$errors ? 1 : 0 ))

check-with-appliance:
	@method=`$(top_builddir)/run ./fish/guestfish get-attach-method`; \
	if [ "$$method" != "appliance" ]; then \
	  $(MAKE) LIBGUESTFS_ATTACH_METHOD=appliance check || exit $$?; \
	fi

check-valgrind-with-appliance:
	@method=`$(top_builddir)/run ./fish/guestfish get-attach-method`; \
	if [ "$$method" != "appliance" ]; then \
	  $(MAKE) LIBGUESTFS_ATTACH_METHOD=appliance check-valgrind || exit $$?; \
	fi

QEMUDIR = $(HOME)/d/qemu
QEMUBINARY = $(QEMUDIR)/x86_64-softmmu/qemu-system-x86_64

check-with-upstream-qemu:
	rm -f $(top_builddir)/qemu-wrapper.sh
	$(MAKE) check-with-upstream-qemu-1 || exit $$?

check-with-upstream-qemu-1: $(top_builddir)/qemu-wrapper.sh
	$(QEMUBINARY) --version
	$(MAKE) LIBGUESTFS_QEMU=$(abs_top_builddir)/qemu-wrapper.sh check

$(top_builddir)/qemu-wrapper.sh: Makefile
	rm -f $@ $@-t
	echo -e "#!/bin/sh\nexec" "$(QEMUBINARY)" -L "$(QEMUDIR)/pc-bios" \"\$$@\" > $@-t
	chmod +x,-w $@-t
	mv $@-t $@

LIBVIRTDIR = $(HOME)/d/libvirt

check-with-upstream-libvirt:
	@method=`$(top_builddir)/run ./fish/guestfish get-attach-method`; \
	if [ "$$method" = "libvirt" ] && [ -x "$(LIBVIRTDIR)/run" ]; then \
	  $(LIBVIRTDIR)/run $(MAKE) check || exit $$?; \
	fi

check-slow: build-test-guests
	@errors=0; \
	for f in `grep -l '^$@:' $(SUBDIRS:%=%/Makefile.am)`; do \
	  echo $(MAKE) -C `dirname $$f` $@; \
	  $(MAKE) -C `dirname $$f` $@ || (( errors++ )); \
	done; \
	exit $$(( $$errors ? 1 : 0 ))

build-test-guests:
	$(MAKE) -C tests/guests check

# Print subdirs.
#
# If you want to selectively run tests, or if the test suite fails half
# way through, use:
#
#   make print-subdirs
#
# to print the subdirectories, select the ones you want to run / the
# remaining ones, and do:
#
#   make check SUBDIRS="..."

print-subdirs:
	@echo $(SUBDIRS)

# Tag HEAD with current version (only for maintainer).

maintainer-tag:
	git tag -a $(VERSION) -m "Version $(VERSION) ($(BRANCH_TYPE))" -f

# Provide help on common Makefile targets.

help:
	@echo
	@echo "make                              Build everything."
	@echo
	@echo "make check                        Run the standard tests"
	@echo "make -k check                       ... and display all errors at once."
	@echo
	@echo "make extra-tests                  Runs all of the following tests:"
	@echo "  make check-valgrind                Run a subset of the tests under valgrind."
	@echo "  make check-valgrind-local-guests   Test under valgrind using local guests."
	@echo "  make check-with-appliance          Test using appliance attach-method."
	@echo "  make check-valgrind-with-appliance Test valgrind + appliance attach-method."
	@echo "  make check-with-upstream-qemu      Test using upstream qemu."
	@echo "  make check-with-upstream-libvirt   Test using upstream libvirt."
	@echo "  make check-slow                    Slow/long-running tests."
	@echo
	@echo "make check-all                    Runs all 'check*' rules."
	@echo "make check-release                Runs 'check*' rules required for release."
	@echo
	@echo "make syntax-check -j1 -k          Check syntax and style problems in the code."
	@echo "make print-subdirs                Print subdirectories."
	@echo
	@echo "make install                      Install everything."
	@echo
	@echo "make clean                        Clean everything."
	@echo
	@echo "To run programs without installing:"
	@echo "  ./run ./fish/guestfish [or any other program]"
	@echo
	@echo "For more information, see EXTENDING LIBGUESTFS in guestfs(3); and README."
	@echo
