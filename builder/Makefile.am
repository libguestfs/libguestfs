# libguestfs virt-builder tool
# Copyright (C) 2013 Red Hat Inc.
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

AM_YFLAGS = -d
AM_CFLAGS = \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/src \
	-I$(top_srcdir)/fish \
	-pthread \
	$(LIBLZMA_CFLAGS)

EXTRA_DIST = \
	$(SOURCES) \
	virt-builder.pod \
	virt-index-validate.pod \
	test-virt-builder.sh \
	test-virt-builder-list.sh \
	test-virt-builder-planner.sh

CLEANFILES = *~ *.cmi *.cmo *.cmx *.cmxa *.o virt-builder

# Alphabetical order.
SOURCES = \
	builder.ml \
	cmdline.ml \
	downloader.mli \
	downloader.ml \
	get_kernel.mli \
	get_kernel.ml \
	index_parser.mli \
	index_parser.ml \
	index-parser-c.c \
	list_entries.mli \
	list_entries.ml \
	paths.ml \
	pxzcat.ml \
	pxzcat.mli \
	pxzcat-c.c \
	setlocale.ml \
	setlocale.mli \
	setlocale-c.c \
	sigchecker.mli \
	sigchecker.ml

man_MANS =
noinst_DATA =

if HAVE_OCAML

# Note this list must be in dependency order.
OBJECTS = \
	$(top_builddir)/mllib/libdir.cmx \
	$(top_builddir)/mllib/common_gettext.cmx \
	$(top_builddir)/mllib/common_utils.cmx \
	$(top_builddir)/mllib/urandom.cmx \
	$(top_builddir)/mllib/random_seed.cmx \
	$(top_builddir)/mllib/hostname.cmx \
	$(top_builddir)/mllib/timezone.cmx \
	$(top_builddir)/mllib/firstboot.cmx \
	$(top_builddir)/mllib/perl_edit.cmx \
	$(top_builddir)/mllib/crypt-c.o \
	$(top_builddir)/mllib/crypt.cmx \
	$(top_builddir)/mllib/fsync-c.o \
	$(top_builddir)/mllib/fsync.cmx \
	$(top_builddir)/mllib/password.cmx \
	$(top_builddir)/mllib/planner.cmx \
	$(top_builddir)/mllib/config.cmx \
	$(top_builddir)/fish/guestfish-uri.o \
	$(top_builddir)/mllib/uri-c.o \
	$(top_builddir)/mllib/uRI.cmx \
	$(top_builddir)/mllib/mkdtemp-c.o \
	$(top_builddir)/mllib/mkdtemp.cmx \
	index-scan.o \
	index-struct.o \
	index-parse.o \
	index-parser-c.o \
	pxzcat-c.o \
	pxzcat.cmx \
	setlocale-c.o \
	setlocale.cmx \
	paths.cmx \
	get_kernel.cmx \
	downloader.cmx \
	sigchecker.cmx \
	index_parser.cmx \
	list_entries.cmx \
	cmdline.cmx \
	builder.cmx

bin_SCRIPTS = virt-builder

# -I $(top_builddir)/src/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/src/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/mllib
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

OCAMLCFLAGS = -g -warn-error CDEFLMPSUVYZX $(OCAMLPACKAGES)
OCAMLOPTFLAGS = $(OCAMLCFLAGS)

OCAMLCLIBS  = \
	$(LIBLZMA_LIBS) \
	$(LIBXML2_LIBS) \
	-L../src/.libs -lutils \
	-L../gnulib/lib/.libs -lgnu \
	-pthread -lpthread \
	-lncurses -lcrypt

virt-builder: $(OBJECTS)
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) \
	  mlguestfs.cmxa -linkpkg $^ \
	  -cclib '$(OCAMLCLIBS)' \
	  $(OCAML_GCOV_LDFLAGS) \
	  -o $@

.mli.cmi:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
.ml.cmo:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
.ml.cmx:
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -c $< -o $@

# Manual pages and HTML files for the website.

man_MANS += virt-builder.1
noinst_DATA += $(top_builddir)/html/virt-builder.1.html

virt-builder.1 $(top_builddir)/html/virt-builder.1.html: stamp-virt-builder.pod

stamp-virt-builder.pod: virt-builder.pod
	$(PODWRAPPER) \
	  --man virt-builder.1 \
	  --html $(top_builddir)/html/virt-builder.1.html \
	  --license GPLv2+ \
	  $<
	touch $@

CLEANFILES += stamp-virt-builder.pod

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

disk_images := \
	$(shell for f in debian fedora ubuntu windows; do if [ -s "../tests/guests/$$f.img" ]; then echo $$f.xz; fi; done) \
	$(shell if [ -s "../tests/guests/fedora.img" ]; then echo fedora.qcow2 fedora.qcow2.xz; fi)

CLEANFILES += *.qcow2 *.xz

check_DATA = $(disk_images)

fedora.qcow2: ../tests/guests/fedora.img
	rm -f $@ $@-t
	qemu-img convert -f raw -O qcow2 $< $@-t
	mv $@-t $@

fedora.qcow2.xz: fedora.qcow2
	rm -f $@ $@-t
	xz --best --block-size=16777216 -c $< > $@-t
	mv $@-t $@

%.xz: ../tests/guests/%.img
	rm -f $@ $@-t
	xz --best --block-size=16777216 -c $< > $@-t
	mv $@-t $@

TESTS = test-virt-builder-list.sh

if ENABLE_APPLIANCE
TESTS += test-virt-builder.sh
endif ENABLE_APPLIANCE

check-valgrind:
	$(MAKE) VG="$(top_builddir)/run @VG@" check

check-slow:
	$(MAKE) TESTS="test-virt-builder-planner.sh" check

# Dependencies.
depend: .depend

.depend: $(wildcard $(abs_srcdir)/*.mli) $(wildcard $(abs_srcdir)/*.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep -I ../ocaml -I $(abs_srcdir) -I $(top_srcdir)/mllib $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

endif

DISTCLEANFILES = .depend

.PHONY: depend docs

# Build a small C index validator program.
bin_PROGRAMS = virt-index-validate

virt_index_validate_SOURCES = \
	index-parse.y \
	index-scan.l \
	index-struct.h \
	index-struct.c \
	index-validate.c

virt_index_validate_CPPFLAGS = \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\"

man_MANS += virt-index-validate.1
noinst_DATA += $(top_builddir)/html/virt-index-validate.1.html

virt-index-validate.1 $(top_builddir)/html/virt-index-validate.1.html: stamp-virt-index-validate.pod

stamp-virt-index-validate.pod: virt-index-validate.pod
	$(PODWRAPPER) \
	  --man virt-index-validate.1 \
	  --html $(top_builddir)/html/virt-index-validate.1.html \
	  --license GPLv2+ \
	  $<
	touch $@

CLEANFILES += \
	index-parse.c \
	index-parse.h \
	index-scan.c \
	stamp-virt-index-validate.pod

if HAVE_OCAML
# Automake-generated makefile has a rule ".l.c:" but lacks a rule ".l.h:".
# Also it doesn't generate dependencies for the C files that include
# index-parse.h.
index-parser-c.c index-scan.c index-validate.c: index-parse.h
index-parse.h: index-parse.y
	$(MAKE) index-parse.c
endif
