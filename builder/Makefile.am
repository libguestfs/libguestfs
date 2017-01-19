# libguestfs virt-builder tool
# Copyright (C) 2013-2017 Red Hat Inc.
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

EXTRA_DIST = \
	$(SOURCES_MLI) $(SOURCES_ML) $(SOURCES_C) \
	libguestfs.gpg \
	opensuse.gpg \
	test-console.sh \
	test-index \
	test-simplestreams/streams/v1/index.json \
	test-simplestreams/streams/v1/net.cirros-cloud_released_download.json \
	test-virt-builder.sh \
	test-virt-builder-docs.sh \
	test-virt-builder-list.sh \
	test-virt-builder-list-simplestreams.sh \
	test-virt-builder-planner.sh \
	test-virt-index-validate.sh \
	test-virt-index-validate-bad-1 \
	test-virt-index-validate-good-1 \
	test-virt-index-validate-good-2 \
	test-virt-index-validate-good-3 \
	virt-builder.pod \
	virt-index-validate.pod \
	yajl_tests.ml

SOURCES_MLI = \
	cache.mli \
	cmdline.mli \
	downloader.mli \
	index.mli \
	index_parser.mli \
	ini_reader.mli \
	languages.mli \
	list_entries.mli \
	pxzcat.mli \
	setlocale.mli \
	sigchecker.mli \
	simplestreams_parser.mli \
	sources.mli \
	yajl.mli

SOURCES_ML = \
	utils.ml \
	pxzcat.ml \
	setlocale.ml \
	index.ml \
	ini_reader.ml \
	yajl.ml \
	paths.ml \
	languages.ml \
	cache.ml \
	sources.ml \
	downloader.ml \
	sigchecker.ml \
	index_parser.ml \
	simplestreams_parser.ml \
	list_entries.ml \
	cmdline.ml \
	builder.ml

SOURCES_C = \
	index-scan.c \
	index-struct.c \
	index-parse.c \
	index-parser-c.c \
	pxzcat-c.c \
	setlocale-c.c \
	yajl-c.c

man_MANS =
noinst_DATA =
bin_PROGRAMS =

if HAVE_OCAML

bin_PROGRAMS += virt-builder

virt_builder_SOURCES = $(SOURCES_C)
virt_builder_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_srcdir)/common/utils \
	-I$(top_srcdir)/lib \
	-I$(top_srcdir)/fish
virt_builder_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	-Wno-unused-macros \
	$(LIBLZMA_CFLAGS) \
	$(LIBTINFO_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(YAJL_CFLAGS)

BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

# -I $(top_builddir)/lib/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/common/utils/.libs \
	-I $(top_builddir)/lib/.libs \
	-I $(top_builddir)/gnulib/lib/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/mllib \
	-I $(top_builddir)/customize
OCAMLPACKAGES_TESTS =
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif
if HAVE_OCAML_PKG_OUNIT
OCAMLPACKAGES_TESTS += -package oUnit
endif

OCAMLCLIBS = \
	-pthread -lpthread \
	-lutils \
	$(LIBTINFO_LIBS) \
	$(LIBCRYPT_LIBS) \
	$(LIBLZMA_LIBS) \
	$(LIBXML2_LIBS) \
	$(YAJL_LIBS) \
	$(LIBINTL) \
	-lgnu

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR)

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif

OCAMLLINKFLAGS = mlguestfs.$(MLARCHIVE) mllib.$(MLARCHIVE) customize.$(MLARCHIVE) $(LINK_CUSTOM_OCAMLC_ONLY)

virt_builder_DEPENDENCIES = \
	$(OBJECTS) \
	../mllib/mllib.$(MLARCHIVE) \
	../customize/customize.$(MLARCHIVE) \
	$(top_srcdir)/ocaml-link.sh
virt_builder_LINK = \
	$(top_srcdir)/ocaml-link.sh -cclib '$(OCAMLCLIBS)' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) $(OCAMLLINKFLAGS) \
	  $(OBJECTS) -o $@

# Manual pages and HTML files for the website.

man_MANS += virt-builder.1
noinst_DATA += $(top_builddir)/website/virt-builder.1.html

virt-builder.1 $(top_builddir)/website/virt-builder.1.html: stamp-virt-builder.pod

stamp-virt-builder.pod: virt-builder.pod $(top_srcdir)/customize/customize-synopsis.pod $(top_srcdir)/customize/customize-options.pod
	$(PODWRAPPER) \
	  --man virt-builder.1 \
	  --html $(top_builddir)/website/virt-builder.1.html \
	  --insert $(top_srcdir)/customize/customize-synopsis.pod:__CUSTOMIZE_SYNOPSIS__ \
	  --insert $(top_srcdir)/customize/customize-options.pod:__CUSTOMIZE_OPTIONS__ \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

disk_images := \
	$(shell for f in debian fedora ubuntu windows; do if [ -s "../test-data/phony-guests/$$f.img" ]; then echo $$f.xz; fi; done) \
	$(shell if [ -s "../test-data/phony-guests/fedora.img" ]; then echo fedora.qcow2 fedora.qcow2.xz; fi)

CLEANFILES += *.qcow2 *.xz

check_DATA = $(disk_images)

fedora.qcow2: ../test-data/phony-guests/fedora.img
	rm -f $@ $@-t
	qemu-img convert -f raw -O qcow2 $< $@-t
	mv $@-t $@

fedora.qcow2.xz: fedora.qcow2
	rm -f $@ $@-t
	xz --best -c $< > $@-t
	mv $@-t $@

%.xz: ../test-data/phony-guests/%.img
	rm -f $@ $@-t
	xz --best -c $< > $@-t
	mv $@-t $@

yajl_tests_SOURCES = yajl-c.c
yajl_tests_CPPFLAGS = $(virt_builder_CPPFLAGS)
yajl_tests_BOBJECTS = \
	yajl.cmo \
	yajl_tests.cmo
yajl_tests_XOBJECTS = $(yajl_tests_BOBJECTS:.cmo=.cmx)

# Can't call the following as <test>_OBJECTS because automake gets confused.
if HAVE_OCAMLOPT
yajl_tests_THEOBJECTS = $(yajl_tests_XOBJECTS)
yajl_tests.cmx: OCAMLPACKAGES += $(OCAMLPACKAGES_TESTS)
else
yajl_tests_THEOBJECTS = $(yajl_tests_BOBJECTS)
yajl_tests.cmo: OCAMLPACKAGES += $(OCAMLPACKAGES_TESTS)
endif

yajl_tests_DEPENDENCIES = \
	$(yajl_tests_THEOBJECTS) \
	../mllib/mllib.$(MLARCHIVE) \
	../customize/customize.$(MLARCHIVE) \
	$(top_srcdir)/ocaml-link.sh
yajl_tests_LINK = \
	$(top_srcdir)/ocaml-link.sh -cclib '$(OCAMLCLIBS)' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) $(OCAMLPACKAGES_TESTS) $(OCAMLLINKFLAGS) \
	  $(yajl_tests_THEOBJECTS) -o $@

TESTS = \
	test-virt-builder-docs.sh \
	test-virt-builder-list.sh \
	test-virt-index-validate.sh \
	$(SLOW_TESTS)
check_PROGRAMS =

TESTS += test-virt-builder-list-simplestreams.sh

if ENABLE_APPLIANCE
TESTS += test-virt-builder.sh
endif ENABLE_APPLIANCE
if HAVE_OCAML_PKG_OUNIT
check_PROGRAMS += yajl_tests
TESTS += yajl_tests
endif

check-valgrind:
	$(MAKE) VG="@VG@" check

# Slow tests.

SLOW_TESTS = \
	$(console_test_scripts) \
	test-virt-builder-planner.sh

check-slow:
	$(MAKE) check TESTS="$(SLOW_TESTS)" SLOW=1

# Test that the supplied guests boot with a serial console.
#
# Note that in future we might decide to make the serial console a
# feature, eg. `virt-builder --add-serial-console' or `virt-builder
# --remove-serial-console', so don't assume that having these tests
# means that a serial console is a requirement.
console_test_scripts := \
	test-console-centos-7.2.sh \
	test-console-rhel-6.8.sh \
	test-console-rhel-7.2.sh \
	test-console-debian-7.sh \
	test-console-debian-8.sh \
	test-console-fedora-24.sh \
	test-console-ubuntu-12.04.sh \
	test-console-ubuntu-14.04.sh \
	test-console-ubuntu-16.04.sh

test-console-%.sh:
	rm -f $@ $@-t
	f=`echo "$@" | $(SED) 's/test-console-\(.*\).sh/\1/'`; \
	echo 'script=$@ exec $$srcdir/test-console.sh' "$$f" > $@-t
	chmod 0755 $@-t
	mv $@-t $@

CLEANFILES += \
	$(console_test_scripts) \
	console-*.img \
	console-*.out

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

.PHONY: depend docs

# virt-builder's default repository

repoconfdir = $(sysconfdir)/xdg/virt-builder/repos.d
repoconf_DATA = libguestfs.conf libguestfs.gpg \
		opensuse.conf opensuse.gpg

install-exec-hook:
	$(LN_S) -f xdg/virt-builder $(DESTDIR)$(sysconfdir)/virt-builder

# Build a small C index validator program.
bin_PROGRAMS += virt-index-validate

virt_index_validate_SOURCES = \
	index-parse.y \
	index-scan.l \
	index-struct.h \
	index-struct.c \
	index-validate.c

virt_index_validate_CPPFLAGS = \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I. \
	-I$(top_builddir) \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils \
	-I$(top_srcdir)/lib
virt_index_validate_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	-Wno-unused-macros
virt_index_validate_LDADD = \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la

man_MANS += virt-index-validate.1
noinst_DATA += $(top_builddir)/website/virt-index-validate.1.html

virt-index-validate.1 $(top_builddir)/website/virt-index-validate.1.html: stamp-virt-index-validate.pod

stamp-virt-index-validate.pod: virt-index-validate.pod
	$(PODWRAPPER) \
	  --man virt-index-validate.1 \
	  --html $(top_builddir)/website/virt-index-validate.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

CLEANFILES += \
	index-parse.c \
	index-parse.h \
	index-scan.c

if HAVE_OCAML
# Automake-generated makefile has a rule ".y.c" but lacks a rule ".y.h".
index-parse.h: index-parse.y
	touch $(srcdir)/index-parse.y
	$(MAKE) index-parse.c
# Also it doesn't generate dependencies for the C files that include
# index-parse.h.
index-parser-c.c index-scan.c index-validate.c: index-parse.h
endif

# Apparently there's no clean way with Automake to not have them
# in the distribution, so just remove them from the distdir.
dist-hook:
	rm -f $(distdir)/index-parse.c $(distdir)/index-parse.h $(distdir)/index-scan.c
