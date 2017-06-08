# libguestfs OCaml tools common code
# Copyright (C) 2011-2017 Red Hat Inc.
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
	$(SOURCES_MLI) \
	$(SOURCES_ML) \
	$(SOURCES_C) \
	visit_tests.ml

SOURCES_MLI = \
	visit.mli

SOURCES_ML = \
	visit.ml

SOURCES_C = \
	visit-c.c

if HAVE_OCAML

# We pretend that we're building a C library.  automake handles the
# compilation of the C sources for us.  At the end we take the C
# objects and OCaml objects and link them into the OCaml library.
# This C library is never used.

noinst_LIBRARIES = libmlvisit.a

if !HAVE_OCAMLOPT
MLVISIT_CMA = mlvisit.cma
else
MLVISIT_CMA = mlvisit.cmxa
endif

noinst_DATA = $(MLVISIT_CMA)

libmlvisit_a_SOURCES = $(SOURCES_C)
libmlvisit_a_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/lib \
	-I$(top_srcdir)/common/visit
libmlvisit_a_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBVIRT_CFLAGS) $(LIBXML2_CFLAGS) \
	-fPIC

BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

# -I $(top_builddir)/lib/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/lib/.libs \
	-I $(top_builddir)/gnulib/lib/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/common/utils/.libs \
	-I $(top_builddir)/common/visit/.libs \
	-I $(builddir)
OCAMLPACKAGES_TESTS = $(MLVISIT_CMA)

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR)

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif

libmlvisit_a_DEPENDENCIES = $(OBJECTS)

$(MLVISIT_CMA): $(OBJECTS) libmlvisit.a
	$(OCAMLFIND) mklib $(OCAMLPACKAGES) \
	    $(OBJECTS) $(libmlvisit_a_OBJECTS) -cclib -lvisit -o mlvisit

# Tests.

visit_tests_SOURCES = dummy.c
visit_tests_BOBJECTS = visit_tests.cmo
visit_tests_XOBJECTS = $(visit_tests_BOBJECTS:.cmo=.cmx)

# Can't call the following as <test>_OBJECTS because automake gets confused.
if !HAVE_OCAMLOPT
visit_tests_THEOBJECTS = $(visit_tests_BOBJECTS)
visit_tests.cmo: OCAMLPACKAGES += $(OCAMLPACKAGES_TESTS)
else
visit_tests_THEOBJECTS = $(visit_tests_XOBJECTS)
visit_tests.cmx: OCAMLPACKAGES += $(OCAMLPACKAGES_TESTS)
endif

OCAMLLINKFLAGS = mlguestfs.$(MLARCHIVE) $(LINK_CUSTOM_OCAMLC_ONLY)

visit_tests_DEPENDENCIES = \
	$(visit_tests_THEOBJECTS) \
	$(MLVISIT_CMA) \
	$(top_srcdir)/ocaml-link.sh
visit_tests_LINK = \
	$(top_srcdir)/ocaml-link.sh \
	  -cclib '-lvisit -lutils $(LIBXML2_LIBS) -lgnu' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLLINKFLAGS) \
	  $(OCAMLPACKAGES) $(OCAMLPACKAGES_TESTS) \
	  $(visit_tests_THEOBJECTS) -o $@

TESTS_ENVIRONMENT = $(top_builddir)/run --test

check_PROGRAMS =
TESTS =

if ENABLE_APPLIANCE
check_PROGRAMS += visit_tests
TESTS += visit_tests
endif

check-valgrind:
	$(MAKE) VG="@VG@" check

# Dependencies.
depend: .depend

.depend: $(wildcard $(abs_srcdir)/*.mli) $(wildcard $(abs_srcdir)/*.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep -I ../../ocaml -I $(abs_srcdir) $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

endif

.PHONY: depend docs
