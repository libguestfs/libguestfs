# libguestfs
# Copyright (C) 2009-2016 Red Hat Inc.
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

include $(top_srcdir)/common-rules.mk

ACLOCAL_AMFLAGS = -I m4

# The generator - must be before anything else.
SUBDIRS = generator

# Must be the first tests that run.
if ENABLE_APPLIANCE
SUBDIRS += tests/qemu
endif

# Files and other test data used by the tests.  Must be before any
# tests run, except tests/qemu.
SUBDIRS += test-data

# Gnulib - must be built and tested before the library.
SUBDIRS += gnulib/lib
if ENABLE_GNULIB_TESTS
SUBDIRS += gnulib/tests
endif

# Basic source for the library.
SUBDIRS += src docs examples po

# The daemon and the appliance.
if ENABLE_DAEMON
SUBDIRS += daemon
SUBDIRS += tests/daemon
endif
if ENABLE_APPLIANCE
SUBDIRS += appliance
endif

# Tests - order is important.
if ENABLE_APPLIANCE
SUBDIRS += tests/c-api
SUBDIRS += tests/tmpdirs
SUBDIRS += tests/protocol
SUBDIRS += tests/events
SUBDIRS += tests/parallel
SUBDIRS += tests/create
SUBDIRS += tests/disks
SUBDIRS += tests/discard
SUBDIRS += tests/mountable
SUBDIRS += tests/network
SUBDIRS += tests/lvm
SUBDIRS += tests/luks
SUBDIRS += tests/md
SUBDIRS += tests/selinux
SUBDIRS += tests/relabel
SUBDIRS += tests/ntfsclone
SUBDIRS += tests/btrfs
SUBDIRS += tests/xfs
SUBDIRS += tests/charsets
SUBDIRS += tests/xml
SUBDIRS += tests/mount-local
#SUBDIRS += tests/9p
SUBDIRS += tests/rsync
SUBDIRS += tests/bigdirs
SUBDIRS += tests/disk-labels
SUBDIRS += tests/hotplug
SUBDIRS += tests/nbd
SUBDIRS += tests/http
SUBDIRS += tests/syslinux
SUBDIRS += tests/journal
SUBDIRS += tests/relative-paths
SUBDIRS += tests/regressions
endif

# libguestfs-test-tool
SUBDIRS += test-tool

# Guestfish.
SUBDIRS += fish

# virt-tools in C.
SUBDIRS += align cat diff df edit format inspector make-fs rescue
if HAVE_P2V
SUBDIRS += p2v
endif

# bash-completion
SUBDIRS += bash

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
if HAVE_GOLANG
SUBDIRS += golang golang/examples
endif

# Unconditional because nothing is built yet.
SUBDIRS += csharp

# OCaml tools.  Note 'mllib' and 'customize' contain shared code used
# by other OCaml tools, so these must come first.
if HAVE_OCAML
SUBDIRS += \
	mllib \
	customize \
	builder builder/website \
	get-kernel \
	resize \
	sparsify \
	sysprep \
	v2v
if HAVE_OCAML_PKG_LIBVIRT
SUBDIRS += v2v/test-harness
endif
if HAVE_FUSE
SUBDIRS += dib
endif
endif

# Perl tools.
if HAVE_TOOLS
SUBDIRS += tools
endif

# guestmount
if HAVE_FUSE
SUBDIRS += fuse
endif

# Miscellaneous utilities.
if HAVE_BOOT_ANALYSIS
SUBDIRS += utils/boot-analysis
endif
SUBDIRS += \
	utils/boot-benchmark \
	utils/qemu-boot \
	utils/qemu-speed-test

# po-docs must come after tools, inspector.
if HAVE_PO4A
SUBDIRS += po-docs
endif

EXTRA_DIST = \
	BUGS HACKING TODO \
	.gitignore \
	.lvimrc \
	.mailmap \
	bootstrap \
	bugs-in-changelog.sh \
	autogen.sh \
	bindtests \
	cfg.mk \
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
	contrib/windows-icons.pl \
	libtool-kill-dependency_libs.sh \
	logo/fish.svg logo/fish.png \
	logo/fish-5yrs.svg logo/fish-5yrs.png \
	logo/virt-builder.svg \
	m4/.gitignore \
	ocaml-link.sh \
	tests/automake2junit.ml \
	tmp/.gitignore \
	update-bugs.sh \
	utils/README \
	valgrind-suppressions \
	website/bugs.png \
	website/communicate.png \
	website/documentation.png \
	website/download.png \
	website/draft.png \
	website/draft.svg \
	website/easytoread.css \
	website/feed.css \
	website/fish-5yrs.svg \
	website/fish.png \
	website/git.png \
	website/index.css \
	website/index.html.in \
	website/pod.css \
	website/standard.css \
	zanata.xml \
	zanata-pull.sh

# XXX Eventually move builder/website under website/ top level directory.
BUILDERFILES = \
	builder/website/README \
	builder/website/index \
	builder/website/index.asc

WEBSITEDIR = $(HOME)/d/websites/libguestfs

noinst_DATA = \
	website/index.html \
	website/README.txt \
	website/TODO.txt

website/README.txt: README
	cp $< $@

website/TODO.txt: TODO
	cp $< $@

maintainer-upload-website:
	cp website/*.{css,html,png,svg,txt} $(WEBSITEDIR)/
	cp $(BUILDERFILES) $(WEBSITEDIR)/download/builder/

# When doing 'make dist' update a few files automatically.
dist-hook:
	git log --decorate=false > ChangeLog
	cp ChangeLog $(distdir)/ChangeLog
	$(top_srcdir)/update-bugs.sh > BUGS-t
	mv BUGS-t BUGS
	cp BUGS $(distdir)/BUGS
	git shortlog -s | $(AWK) -F'\t' '{print $$2}' | sort -f > AUTHORS-t
	mv AUTHORS-t AUTHORS
	cp AUTHORS $(distdir)/AUTHORS

# Update the list of translatable files.  These are separated into:
#
#  po/POTFILES - files with ordinary extensions, but not OCaml files
#  po/POTFILES-pl - Perl files that don't end in *.pl, which need a
#                   special xgettext option [not generated here]
#  po/POTFILES-ml - OCaml files, which need a special tool to translate
#
# See po/Makefile.am.
#
# This has to be in the top-level Makefile.am so that we have access
# to DIST_SUBDIRS.
all-local:
	cd $(srcdir); \
	find $(DIST_SUBDIRS) -name '*.c' -o -name '*.pl' -o -name '*.pm' | \
	grep -v -E '^(examples|gnulib|gobject/docs|perl/(blib|examples)|po-docs|tests|test-data)/' | \
	grep -v -E '/((guestfs|rc)_protocol\.c)$$' | \
	grep -v -E '^python/utils\.c$$' | \
	LC_ALL=C sort > po/POTFILES
	cd $(srcdir); \
	find builder customize dib get-kernel mllib resize sparsify sysprep v2v -name '*.ml' | \
	LC_ALL=C sort > po/POTFILES-ml

# Try to stop people using 'make install' without 'DESTDIR'.
install:
	@if test "x$(DESTDIR)" != "x" || test "x$(REALLY_INSTALL)" = "xyes"; \
	then \
	    $(MAKE) install-recursive; \
	else \
	    echo "***"; \
	    echo "*** Using 'make install' is usually a very bad idea."; \
	    echo "*** Use the './run' script instead - see the README."; \
	    echo "***"; \
	    echo "*** You can override this by setting REALLY_INSTALL=yes, but don't do that."; \
	    echo "***"; \
	    exit 1; \
	fi

# Test installed packages.
installcheck-local: installcheck.sh
	$(builddir)/installcheck.sh

# NB. podwrapper is an internal tool, so the man page mustn't be installed.
# It should be noinst_MANS but that doesn't work.
noinst_DATA += podwrapper.1
podwrapper.1: podwrapper.pl
	$(PODWRAPPER) \
	  --section 1 \
	  --man $@-t \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	mv $@-t $@

# Make clean.

CLEANFILES = \
	*~ \
	pod2htm?.tmp \
	podwrapper.1 \
	qemu-wrapper.sh \
	tmp/disk* \
	tmp/run-* \
	tmp/valgrind-*.log \
	website/*~ \
	website/*.html

clean-local:
	-rm -rf tmp/libguestfs??????
	-rm -rf tmp/guestfs.*
	-rm -rf tmp/.guestfs-*
	-rm -rf tmp/null.*
	-find tmp -type s -delete
	-find . -name '*~' -delete
	-find . -name '*.bak' -delete
	-find . -name '*.orig' -delete

# If you don't want to run all of the tests ('make check') then this
# will just run libguestfs-test-tool for a quick check.  Note this
# is NOT a substitute for proper testing!

quickcheck:
	$(top_builddir)/run test-tool/libguestfs-test-tool $(QUICKCHECK_TEST_TOOL_ARGS)

# Non-standard tests.

check-all:
	$(MAKE) -j1 \
	  check \
	  check-valgrind \
	  check-valgrind-local-guests \
	  check-direct \
	  check-valgrind-direct \
	  check-uml \
	  check-valgrind-uml \
	  check-with-upstream-qemu \
	  check-with-upstream-libvirt \
	  check-slow

check-release:
	$(MAKE) -j1 \
	  check \
	  check-valgrind \
	  check-direct \
	  check-valgrind-direct
	$(MAKE) -j1 \
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

check-direct:
	@backend=`$(top_builddir)/run ./fish/guestfish get-backend`; \
	if [ "$$backend" != "direct" ]; then \
	  $(MAKE) LIBGUESTFS_BACKEND=direct check || exit $$?; \
	fi

check-with-appliance: check-direct

check-valgrind-direct:
	@backend=`$(top_builddir)/run ./fish/guestfish get-backend`; \
	if [ "$$backend" != "direct" ]; then \
	  $(MAKE) LIBGUESTFS_BACKEND=direct check-valgrind || exit $$?; \
	fi

check-valgrind-with-appliance: check-valgrind-direct

# Tests which currently fail under UML:
# - blockdev --setro seems to have no effect on /dev/ubd* devices [*]
# - RHBZ#914931: test is sent a SIGTERM, apparently by UML [*]
# - tests/md/test-inspect-fstab-md.sh hangs at various places during the
#   test, eg. running mdadm, mounting MD filesystem [*]
# [*] = likely to be a bug in UML itself
SKIP_TESTS_FAILING_IN_UML = \
	SKIP_TEST_BLOCKDEV_GETRO=1 \
	SKIP_TEST_BLOCKDEV_SETRO=1 \
	SKIP_TEST_RHBZ914931=1 \
	SKIP_TEST_INSPECT_FSTAB_MD_SH=1

check-uml:
	$(MAKE) LIBGUESTFS_BACKEND=uml $(SKIP_TESTS_FAILING_IN_UML) check

check-valgrind-uml:
	$(MAKE) LIBGUESTFS_BACKEND=uml $(SKIP_TESTS_FAILING_IN_UML) check-valgrind

QEMUDIR = $(HOME)/d/qemu
QEMUBINARY = $(QEMUDIR)/x86_64-softmmu/qemu-system-x86_64

check-with-upstream-qemu:
	rm -f $(top_builddir)/qemu-wrapper.sh
	$(MAKE) check-with-upstream-qemu-1 || exit $$?

check-with-upstream-qemu-1: $(top_builddir)/qemu-wrapper.sh
	$(QEMUBINARY) --version
	$(MAKE) LIBGUESTFS_HV=$(abs_top_builddir)/qemu-wrapper.sh check

$(top_builddir)/qemu-wrapper.sh: Makefile
	rm -f $@ $@-t
	echo -e "#!/bin/sh\nexec" "$(QEMUBINARY)" -L "$(QEMUDIR)/pc-bios" \"\$$@\" > $@-t
	chmod +x,-w $@-t
	mv $@-t $@

LIBVIRTDIR = $(HOME)/d/libvirt

check-with-upstream-libvirt:
	@backend=`$(top_builddir)/run ./fish/guestfish get-backend`; \
	if [ "$$backend" = "libvirt" ] && [ -x "$(LIBVIRTDIR)/run" ]; then \
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
	$(MAKE) -C test-data/phony-guests check

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

# Commit everything in current directory to HEAD, and set commit
# message to current version (only for maintainer).

maintainer-commit:
	git commit -a -m "Version $(VERSION)."

# Tag HEAD with current version (only for maintainer).

maintainer-tag:
	git tag -a $(VERSION) -m "Version $(VERSION) ($(BRANCH_TYPE))" -f

# Maintainer only: check EXTRA_DIST rule is complete.
# (Note you must have done 'make dist')

maintainer-check-extra-dist:
	zcat $(PACKAGE_NAME)-$(VERSION).tar.gz | tar tf - | sort | \
	  sed 's,^$(PACKAGE_NAME)-$(VERSION)/,,' > tmp/tarfiles
	git ls-files | \
	  grep -v '^intltool-.*\.in' | \
	  grep -v '^\.gitmodules' | \
	  grep -v '^\.gnulib' | \
	  sort > tmp/gitfiles
	comm -13 tmp/tarfiles tmp/gitfiles > tmp/comm-out
	cat tmp/comm-out
	[ ! -s tmp/comm-out ]
	rm tmp/tarfiles tmp/gitfiles tmp/comm-out

# Provide help on common Makefile targets.

help:
	@echo
	@echo "make                              Build everything."
	@echo
	@echo "make check                        Run the standard tests"
	@echo "make -k check                       ... and display all errors at once."
	@echo
	@echo "make check-valgrind               Run a subset of the tests under valgrind."
	@echo "make check-valgrind-local-guests  Test under valgrind using local guests."
	@echo "make check-direct                 Test using direct backend."
	@echo "make check-valgrind-direct        Test valgrind + direct backend."
	@echo "make check-uml                    Test using User-Mode Linux."
	@echo "make check-valgrind-uml           Test valgrind + User-Mode Linux."
	@echo "make check-with-upstream-qemu     Test using upstream qemu."
	@echo "make check-with-upstream-libvirt  Test using upstream libvirt."
	@echo "make check-slow                   Slow/long-running tests."
	@echo
	@echo "make check-all                    Runs all 'check*' rules."
	@echo "make check-release                Runs 'check*' rules required for release."
	@echo
	@echo "make installcheck                 Test installed libguestfs packages."
	@echo
	@echo "make print-subdirs                Print subdirectories."
	@echo
	@echo "make install                      Install everything."
	@echo
	@echo "make clean                        Clean everything."
	@echo
	@echo "To run programs without installing:"
	@echo "  ./run ./fish/guestfish [or any other program]"
	@echo
	@echo "For more information, see guestfs-hacking(1); and README."
	@echo
