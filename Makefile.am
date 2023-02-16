# libguestfs
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

include $(top_srcdir)/common-rules.mk

ACLOCAL_AMFLAGS = -I m4

# The generator - must be before anything else.
SUBDIRS = common/mlstdutils generator

# Files and other test data used by the tests.  Must be before any
# tests run.
SUBDIRS += test-data

# Basic source for the library.
SUBDIRS += gnulib/lib
SUBDIRS += common/errnostring common/protocol common/qemuopts
SUBDIRS += common/utils
SUBDIRS += common/structs
SUBDIRS += include lib docs examples

# The daemon and the appliance.
SUBDIRS += common/mlutils
SUBDIRS += common/mlpcre
if ENABLE_DAEMON
SUBDIRS += daemon
endif
if ENABLE_APPLIANCE
SUBDIRS += appliance
endif

# Tests.
SUBDIRS += tests

# Common code used by the tools.
SUBDIRS += common/edit
SUBDIRS += common/options
SUBDIRS += common/parallel
SUBDIRS += common/progress
SUBDIRS += common/visit
SUBDIRS += common/windows

# Small tools written in C.
SUBDIRS += test-tool fish rescue

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
if HAVE_RUST
SUBDIRS += rust
endif

# Unconditional because nothing is built yet.
SUBDIRS += csharp

# guestmount
if HAVE_FUSE
SUBDIRS += fuse
endif

# After all source files were used we can generate the translation strings
SUBDIRS += po

# po-docs must come after tools, inspector.
if HAVE_PO4A
SUBDIRS += po-docs
endif

EXTRA_DIST = \
	AUTHORS HACKING TODO \
	.gitignore \
	.gitpublish \
	.lvimrc \
	.mailmap \
	bugs-in-changelog.sh \
	bindtests \
	build-aux/config.rpath \
	check-mli.sh \
	common/.gitignore \
	common/README \
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
	logo/fish-10yrs.svg logo/fish-10yrs.png \
	logo/virt-builder.svg \
	podcheck.pl \
	tests/test-functions.sh \
	tmp/.gitignore \
	valgrind-suppressions \
	website/bugs.png \
	website/communicate.png \
	website/documentation.png \
	website/download.png \
	website/download/builder/README \
	website/download/builder/index \
	website/download/builder/index.asc \
	website/draft.png \
	website/draft.svg \
	website/easytoread.css \
	website/feed.css \
	website/fish-5yrs.svg \
	website/fish-10yrs.svg \
	website/fish.png \
	website/git.png \
	website/index.css \
	website/index.html.in \
	website/pod.css \
	website/standard.css

WEBSITESDIR = $(HOME)/d/websites

BUILDERFILES = \
	website/download/builder/README \
	website/download/builder/index \
	website/download/builder/index.asc

noinst_DATA = \
	website/index.html \
	website/README.txt \
	website/TODO.txt

website/README.txt: README
	cp $< $@

website/TODO.txt: TODO
	cp $< $@

maintainer-upload-website:
	cp website/*.{css,html,png,svg,txt} $(WEBSITESDIR)/libguestfs/
	cp $(BUILDERFILES) $(WEBSITESDIR)/libguestfs-builder/

# When doing 'make dist' update a few files automatically.
#
#  docs/C_SOURCE_FILES
#                 - source files scanned for internal documentation
#  po/POTFILES    - files with ordinary extensions, but not OCaml files

dist-hook: docs/C_SOURCE_FILES po/POTFILES

# This has to be in the top-level Makefile.am so that we have access
# to DIST_SUBDIRS.
docs/C_SOURCE_FILES: configure.ac
	rm -f $@ $@-t
	find $(DIST_SUBDIRS) -name '*.[ch]' | \
	grep -v -E '^(builder/index-parse\.|builder/index-scan\.|examples/|gobject/|java/com_redhat_et_libguestfs|perl/|php/extension/config\.h|ruby/ext/guestfs/extconf\.h|tests/|test-data/)' | \
	grep -v -E '/(guestfs|rc)_protocol\.' | \
	grep -v -E '.*/errnostring\.' | \
	grep -v -E '.*-gperf\.' | \
	grep -v -E '/dummy.c$$' | \
	LC_ALL=C sort -u > $@-t
	mv $@-t $@

# For more information about translations, see po/Makefile.am.
po/POTFILES: configure.ac
	rm -f $@ $@-t
	cd $(srcdir); \
	find $(DIST_SUBDIRS) -name '*.c' | \
	grep -v -E '^(examples|perl/(blib|examples)|po-docs|tests|test-data)/' | \
	grep -v -E '/((guestfs|rc)_protocol\.c|dummy\.c)$$' | \
	grep -v -E '^python/utils\.c$$' | \
	grep -v -E '^perl/lib/Sys/Guestfs\.c$$' | \
	grep -v -E '.*-(tests|gperf)\.c$$' | \
	LC_ALL=C sort -u > $@-t
	mv $@-t $@

# Try to stop people using 'make install' without 'DESTDIR'.
install:
	@if test "x$(DESTDIR)" != "x" || test "x$(REALLY_INSTALL)" = "xyes"; \
	then \
	    $(MAKE) install-recursive; \
	else \
	    echo "***"; \
	    echo "*** Using 'make install' is usually a very bad idea."; \
	    echo "*** Use the './run' script instead - see the guestfs-building(1) man page."; \
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

CLEANFILES += \
	pod2htm?.tmp \
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
	  check-direct \
	  check-valgrind-direct \
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

check-root: build-test-guests
	@if test "$$(id -u)" -ne 0; then \
	  echo "***"; \
	  echo "*** error: You must run 'check-root' as root."; \
	  echo "***"; \
	  exit 1; \
	fi
	@errors=0; \
	for f in `grep -l '^$@:' $(SUBDIRS:%=%/Makefile.am)`; do \
	  echo $(MAKE) -C `dirname $$f` $@; \
	  $(MAKE) -C `dirname $$f` $@ || (( errors++ )); \
	done; \
	exit $$(( $$errors ? 1 : 0 ))

build-test-guests:
	$(MAKE) -C test-data/phony-guests check

# Some tests which run at the top level.

TESTS = check-mli.sh

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
	git tag -a "v$(VERSION)" -m "Version $(VERSION) ($(BRANCH_TYPE))" -f

# Maintainer only: compare authors (found in git commit messages) to
# generator/authors.ml.
maintainer-check-authors:
	rm -f $@ $@-t
	git shortlog -s | \
	    $(AWK) -F'\t' '{print $$2}' | \
	    sort -f | \
	    while read author; do \
	        if ! grep -sqiF "\"$$author\"" generator/authors.ml; then \
	            echo "FAIL: $$author" is missing from generator/authors.ml; \
	            exit 1; \
	        fi; \
	    done
	@echo PASS: AUTHORS test

# Maintainer only: check no files are missing from EXTRA_DIST rules,
# and that all generated files have been included in the tarball.
# (Note you must have done 'make dist')

maintainer-check-extra-dist:
	zcat $(PACKAGE_NAME)-$(VERSION).tar.gz | tar tf - | sort | \
	  sed 's,^$(PACKAGE_NAME)-$(VERSION)/,,' > tmp/tarfiles
	( git ls-files ; \
	  cd common; git ls-files | sed 's,^,common/,' ) | \
	  grep -v '^common$$' | \
	  grep -v '^common/mlcustomize/' | \
	  grep -v '^common/mldrivers/' | \
	  grep -v '^common/mlgettext/' | \
	  grep -v '^common/mlprogress/' | \
	  grep -v '^common/mltools/' | \
	  grep -v '^common/mlv2v/' | \
	  grep -v '^common/mlvisit/' | \
	  grep -v '^common/mlxml/' | \
	  grep -v '^intltool-.*\.in' | \
	  grep -v '^\.gitmodules' | \
	  sort > tmp/gitfiles
	comm -13 tmp/tarfiles tmp/gitfiles > tmp/comm-out
	@echo Checking for differences between EXTRA_DIST and git ...
	cat tmp/comm-out
	[ ! -s tmp/comm-out ]
	@echo Checking for generated files missing from the tarball ...
	@for f in `cat generator/files-generated.txt | grep -v '^common/mlcustomize' | grep -v '^common/mlv2v/'`; do \
	  if ! grep -sq "^$$f\$$" tmp/tarfiles; then \
	    echo generated file missing from tarball: $$f; \
	    exit 1; \
	  fi; \
	done
	rm tmp/tarfiles tmp/gitfiles tmp/comm-out
	@echo PASS: EXTRA_DIST tests

# Provide help on common Makefile targets.

help:
	@echo
	@echo "make                              Build everything."
	@echo
	@echo "make check                        Run the standard tests"
	@echo "make -k check                       ... and display all errors at once."
	@echo
	@echo "make check-valgrind               Run a subset of the tests under valgrind."
	@echo "make check-direct                 Test using direct backend."
	@echo "make check-valgrind-direct        Test valgrind + direct backend."
	@echo "make check-with-upstream-qemu     Test using upstream qemu."
	@echo "make check-with-upstream-libvirt  Test using upstream libvirt."
	@echo "make check-slow                   Slow/long-running tests."
	@echo "sudo make check-root              Tests which must be run as root."
	@echo
	@echo "make check-all                    Runs all 'check*' rules except check-root."
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
