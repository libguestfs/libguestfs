# libguestfs virt-resize 2.0 tools
# Copyright (C) 2011-2014 Red Hat Inc.
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
	virt-resize.pod \
	test-virt-resize.pl

CLEANFILES = *~ *.cmi *.cmo *.cmx *.cmxa *.o virt-resize

# Alphabetical order.
SOURCES = \
	resize.ml

if HAVE_OCAML

# Note this list must be in dependency order.
deps = \
	$(top_builddir)/mllib/config.cmx \
	$(top_builddir)/mllib/tty-c.o \
	$(top_builddir)/mllib/tTY.cmx \
	$(top_builddir)/mllib/fsync-c.o \
	$(top_builddir)/mllib/fsync.cmx \
	$(top_builddir)/fish/guestfish-progress.o \
	$(top_builddir)/mllib/progress-c.o \
	$(top_builddir)/mllib/progress.cmx \
	$(top_builddir)/fish/guestfish-uri.o \
	$(top_builddir)/mllib/uri-c.o \
	$(top_builddir)/mllib/uRI.cmx \
	$(top_builddir)/mllib/common_gettext.cmx \
	$(top_builddir)/mllib/common_utils.cmx \
	$(top_builddir)/mllib/config.cmx \
	resize.cmx

if HAVE_OCAMLOPT
OBJECTS = $(deps)
else
OBJECTS = $(patsubst %.cmx,%.cmo,$(deps))
endif

bin_SCRIPTS = virt-resize

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
	$(LIBXML2_LIBS) -lncurses \
	-L../src/.libs -lutils \
	-L../gnulib/lib/.libs -lgnu

if HAVE_OCAMLOPT
virt-resize: $(OBJECTS)
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) \
	  mlguestfs.cmxa -linkpkg $^ \
	  -cclib '$(OCAMLCLIBS)' \
	  -o $@
else
virt-resize: $(OBJECTS)
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

man_MANS = virt-resize.1

noinst_DATA = $(top_builddir)/html/virt-resize.1.html

virt-resize.1 $(top_builddir)/html/virt-resize.1.html: stamp-virt-resize.pod

stamp-virt-resize.pod: virt-resize.pod
	$(PODWRAPPER) \
	  --man virt-resize.1 \
	  --html $(top_builddir)/html/virt-resize.1.html \
	  --license GPLv2+ \
	  $<
	touch $@

CLEANFILES += stamp-virt-resize.pod

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS =
if ENABLE_APPLIANCE
TESTS += test-virt-resize.pl
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
