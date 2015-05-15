# virt-customize
# Copyright (C) 2014 Red Hat Inc.
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

EXTRA_DIST = \
	$(SOURCES) \
	test-virt-customize.sh \
	virt-customize.pod

CLEANFILES = \
	*~ *.cmi *.cmo *.cmx *.cmxa *.o \
	stamp-virt-customize.pod \
	virt-customize virt-customize.1

generator_built = \
	customize_cmdline.mli \
	customize_cmdline.ml \
	customize-options.pod \
	customize-synopsis.pod

# Alphabetical order.
SOURCES = \
	crypt.ml \
	crypt.mli \
	crypt-c.c \
	customize_cmdline.ml \
	customize_cmdline.mli \
	customize_run.ml \
	customize_run.mli \
	firstboot.ml \
	firstboot.mli \
	hostname.ml \
	hostname.mli \
	customize_main.ml \
	password.ml \
	password.mli \
	perl_edit-c.c \
	perl_edit.ml \
	perl_edit.mli \
	random_seed.ml \
	random_seed.mli \
	timezone.ml \
	timezone.mli \
	urandom.ml \
	urandom.mli

if HAVE_OCAML

deps = \
	$(top_builddir)/fish/guestfish-uri.o \
	$(top_builddir)/fish/guestfish-file-edit.o \
	$(top_builddir)/mllib/config.cmx \
	$(top_builddir)/mllib/common_gettext.cmx \
	$(top_builddir)/mllib/tty-c.o \
	$(top_builddir)/mllib/tTY.cmx \
	$(top_builddir)/mllib/common_utils.cmx \
	$(top_builddir)/mllib/config.cmx \
	$(top_builddir)/mllib/regedit.cmx \
	$(top_builddir)/mllib/uri-c.o \
	$(top_builddir)/mllib/uRI.cmx \
	crypt-c.o \
	perl_edit-c.o

if HAVE_OCAMLOPT
OBJECTS = $(deps)
else
OBJECTS = $(patsubst %.cmx,%.cmo,$(deps))
endif

# This list must be in dependency order.
ocaml_modules = \
	crypt \
	firstboot \
	hostname \
	urandom \
	password \
	perl_edit \
	random_seed \
	timezone \
	customize_cmdline \
	customize_run \
	customize_main

if HAVE_OCAMLOPT
OBJECTS += $(patsubst %,%.cmx,$(ocaml_modules))
else
OBJECTS += $(patsubst %,%.cmo,$(ocaml_modules))
endif

bin_SCRIPTS = virt-customize

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

OCAMLCFLAGS = -g -warn-error CDEFLMPSUVYZX-3 $(OCAMLPACKAGES)
OCAMLOPTFLAGS = $(OCAMLCFLAGS)

OCAMLCLIBS  = \
	$(LIBXML2_LIBS) -lncurses -lcrypt \
	-L../src/.libs -lutils \
	-L../gnulib/lib/.libs -lgnu

virt-customize: $(OBJECTS)
if HAVE_OCAMLOPT
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) \
	  mlguestfs.cmxa -linkpkg $^ \
	  -cclib '$(OCAMLCLIBS)' \
	  -o $@
else
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

# automake will decide we don't need C support in this file.  Really
# we do, so we have to provide it ourselves.

DEFAULT_INCLUDES = \
	-I. \
	-I$(top_builddir) \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/src \
	-I$(top_srcdir)/fish

.c.o:
	$(CC) $(CFLAGS) $(PROF_CFLAGS) $(DEFAULT_INCLUDES) -c $< -o $@

# Manual pages and HTML files for the website.
man_MANS = virt-customize.1
noinst_DATA = $(top_builddir)/html/virt-customize.1.html

virt-customize.1 $(top_builddir)/html/virt-customize.1.html: stamp-virt-customize.pod

stamp-virt-customize.pod: virt-customize.pod $(top_srcdir)/customize/customize-synopsis.pod $(top_srcdir)/customize/customize-options.pod
	$(PODWRAPPER) \
	  --man virt-customize.1 \
	  --html $(top_builddir)/html/virt-customize.1.html \
	  --insert $(top_srcdir)/customize/customize-synopsis.pod:__CUSTOMIZE_SYNOPSIS__ \
	  --insert $(top_srcdir)/customize/customize-options.pod:__CUSTOMIZE_OPTIONS__ \
	  --license GPLv2+ \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

if ENABLE_APPLIANCE
TESTS = test-virt-customize.sh
endif

check-valgrind:
	$(MAKE) VG="$(top_builddir)/run @VG@" check

# Dependencies.
depend: .depend

.depend: $(wildcard $(abs_srcdir)/*.mli) $(wildcard $(abs_srcdir)/*.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep -I ../ocaml -I $(abs_srcdir) -I $(abs_top_builddir)/mllib $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

endif

DISTCLEANFILES = .depend

.PHONY: depend docs
