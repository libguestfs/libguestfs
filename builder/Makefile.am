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
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_srcdir)/src \
	-I$(top_srcdir)/fish \
	-pthread \
	$(LIBLZMA_CFLAGS)

EXTRA_DIST = \
	$(SOURCES) \
	libguestfs.gpg \
	test-index \
	test-virt-builder.sh \
	test-virt-builder-list.sh \
	test-virt-builder-planner.sh \
	test-virt-index-validate.sh \
	test-virt-index-validate-bad-1 \
	test-virt-index-validate-good-1 \
	test-virt-index-validate-good-2 \
	virt-builder.pod \
	virt-index-validate.pod

CLEANFILES = *~ *.cmi *.cmo *.cmx *.cmxa *.o virt-builder

# Alphabetical order.
SOURCES = \
	builder.ml \
	cache.mli \
	cache.ml \
	cmdline.ml \
	downloader.mli \
	downloader.ml \
	get_kernel.mli \
	get_kernel.ml \
	index_parser.mli \
	index_parser.ml \
	index-parser-c.c \
	ini_reader.mli \
	ini_reader.ml \
	languages.mli \
	languages.ml \
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
	sigchecker.ml \
	sources.mli \
	sources.ml

man_MANS =
noinst_DATA =

if HAVE_OCAML

# Note this list must be in dependency order.
deps = \
	$(top_builddir)/mllib/libdir.cmx \
	$(top_builddir)/mllib/config.cmx \
	$(top_builddir)/mllib/common_gettext.cmx \
	$(top_builddir)/mllib/tty-c.o \
	$(top_builddir)/mllib/tTY.cmx \
	$(top_builddir)/mllib/common_utils.cmx \
	$(top_builddir)/mllib/fsync-c.o \
	$(top_builddir)/mllib/fsync.cmx \
	$(top_builddir)/mllib/planner.cmx \
	$(top_builddir)/mllib/regedit.cmx \
	$(top_builddir)/mllib/JSON.cmx \
	$(top_builddir)/mllib/uri-c.o \
	$(top_builddir)/mllib/uRI.cmx \
	$(top_builddir)/mllib/mkdtemp-c.o \
	$(top_builddir)/mllib/mkdtemp.cmx \
	$(top_builddir)/customize/urandom.cmx \
	$(top_builddir)/customize/random_seed.cmx \
	$(top_builddir)/customize/hostname.cmx \
	$(top_builddir)/customize/timezone.cmx \
	$(top_builddir)/customize/firstboot.cmx \
	$(top_builddir)/customize/perl_edit-c.o \
	$(top_builddir)/customize/perl_edit.cmx \
	$(top_builddir)/customize/crypt-c.o \
	$(top_builddir)/customize/crypt.cmx \
	$(top_builddir)/customize/password.cmx \
	$(top_builddir)/customize/customize_cmdline.cmx \
	$(top_builddir)/customize/customize_run.cmx \
	$(top_builddir)/fish/guestfish-uri.o \
	$(top_builddir)/fish/guestfish-file-edit.o \
	index-scan.o \
	index-struct.o \
	index-parse.o \
	index-parser-c.o \
	pxzcat-c.o \
	pxzcat.cmx \
	setlocale-c.o \
	setlocale.cmx \
	ini_reader.cmx \
	paths.cmx \
	languages.cmx \
	get_kernel.cmx \
	cache.cmx \
	downloader.cmx \
	sigchecker.cmx \
	index_parser.cmx \
	list_entries.cmx \
	sources.cmx \
	cmdline.cmx \
	builder.cmx

if HAVE_OCAMLOPT
OBJECTS = $(deps)
else
OBJECTS = $(patsubst %.cmx,%.cmo,$(deps))
endif

bin_SCRIPTS = virt-builder

# -I $(top_builddir)/src/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/src/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/mllib \
	-I $(top_builddir)/customize
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

OCAMLCFLAGS = -g -warn-error CDEFLMPSUVYZX-3 $(OCAMLPACKAGES)
OCAMLOPTFLAGS = $(OCAMLCFLAGS)

OCAMLCLIBS  = \
	$(LIBLZMA_LIBS) \
	$(LIBXML2_LIBS) \
	-L../src/.libs -lutils \
	-L../gnulib/lib/.libs -lgnu \
	-pthread -lpthread \
	-lncurses -lcrypt

if HAVE_OCAMLOPT
virt-builder: $(OBJECTS)
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) \
	  mlguestfs.cmxa -linkpkg $^ \
	  -cclib '$(OCAMLCLIBS)' \
	  -o $@
else
virt-builder: $(OBJECTS)
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) \
	  mlguestfs.cma -linkpkg $^ \
	  -cclib '$(OCAMLCLIBS)' \
	  -custom \
	  -o $@
endif

.mli.cmi:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
.ml.cmo:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
if HAVE_OCAMLOPT
.ml.cmx:
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -c $< -o $@
endif

# Manual pages and HTML files for the website.

man_MANS += virt-builder.1
noinst_DATA += $(top_builddir)/html/virt-builder.1.html

virt-builder.1 $(top_builddir)/html/virt-builder.1.html: stamp-virt-builder.pod

stamp-virt-builder.pod: virt-builder.pod $(top_srcdir)/customize/customize-synopsis.pod $(top_srcdir)/customize/customize-options.pod
	$(PODWRAPPER) \
	  --man virt-builder.1 \
	  --html $(top_builddir)/html/virt-builder.1.html \
	  --insert $(top_srcdir)/customize/customize-synopsis.pod:__CUSTOMIZE_SYNOPSIS__ \
	  --insert $(top_srcdir)/customize/customize-options.pod:__CUSTOMIZE_OPTIONS__ \
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
	xz --best -c $< > $@-t
	mv $@-t $@

%.xz: ../tests/guests/%.img
	rm -f $@ $@-t
	xz --best -c $< > $@-t
	mv $@-t $@

TESTS = \
	test-virt-builder-list.sh \
	test-virt-index-validate.sh

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
	$(OCAMLFIND) ocamldep -I ../ocaml -I $(abs_srcdir) -I $(abs_top_builddir)/mllib -I $(abs_top_builddir)/customize $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

endif

DISTCLEANFILES = .depend

.PHONY: depend docs

# virt-builder's default repository

repoconfdir = $(sysconfdir)/xdg/virt-builder/repos.d
repoconf_DATA = libguestfs.conf libguestfs.gpg

install-exec-hook:
	$(LN_S) xdg/virt-builder $(DESTDIR)$(sysconfdir)/virt-builder

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

virt_index_validate_LDADD = \
	../gnulib/lib/libgnu.la

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
	$(MAKE) index-parse.h
endif

# Apparently there's no clean way with Automake to not have them
# in the distribution, so just remove them from the distdir.
dist-hook:
	rm -f $(distdir)/index-parse.c $(distdir)/index-parse.h $(distdir)/index-scan.c
