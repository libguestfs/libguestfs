# Bindings for Perl-compatible Regular Expressions.
# Copyright (C) 2017 Red Hat Inc.
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
	pcre_tests.ml

SOURCES_MLI = \
	PCRE.mli

SOURCES_ML = \
	PCRE.ml

SOURCES_C = \
	pcre-c.c

# We pretend that we're building a C library.  automake handles the
# compilation of the C sources for us.  At the end we take the C
# objects and OCaml objects and link them into the OCaml library.
# This C library is never used.

noinst_LIBRARIES = libmlpcre.a

if !HAVE_OCAMLOPT
MLPCRE_CMA = mlpcre.cma
else
MLPCRE_CMA = mlpcre.cmxa
endif

noinst_DATA = $(MLPCRE_CMA)

libmlpcre_a_SOURCES = $(SOURCES_C)
libmlpcre_a_CPPFLAGS = \
	-DCAML_NAME_SPACE \
	-I. \
	-I$(top_builddir) \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(shell $(OCAMLC) -where)
libmlpcre_a_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	-fPIC

BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

# -I $(top_builddir)/lib/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-I $(top_builddir)/gnulib/lib/.libs \
	-I $(top_builddir)/common/utils/.libs \
	-I $(builddir)
OCAMLPACKAGES_TESTS = $(MLPCRE_CMA)

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR) -ccopt '$(CFLAGS)'

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif

libmlpcre_a_DEPENDENCIES = $(OBJECTS)

$(MLPCRE_CMA): $(OBJECTS) libmlpcre.a
	$(OCAMLFIND) mklib $(OCAMLPACKAGES) \
	    $(OBJECTS) $(libmlpcre_a_OBJECTS) -cclib -lpcre -o mlpcre

# Tests.

pcre_tests_SOURCES = dummy.c
pcre_tests_BOBJECTS = pcre_tests.cmo
pcre_tests_XOBJECTS = $(pcre_tests_BOBJECTS:.cmo=.cmx)

# Can't call the following as <test>_OBJECTS because automake gets confused.
if !HAVE_OCAMLOPT
pcre_tests_THEOBJECTS = $(pcre_tests_BOBJECTS)
pcre_tests.cmo: OCAMLPACKAGES += $(OCAMLPACKAGES_TESTS)
else
pcre_tests_THEOBJECTS = $(pcre_tests_XOBJECTS)
pcre_tests.cmx: OCAMLPACKAGES += $(OCAMLPACKAGES_TESTS)
endif

OCAMLLINKFLAGS = $(LINK_CUSTOM_OCAMLC_ONLY)

pcre_tests_DEPENDENCIES = \
	$(pcre_tests_THEOBJECTS) \
	$(MLPCRE_CMA) \
	$(top_srcdir)/ocaml-link.sh
pcre_tests_LINK = \
	$(top_srcdir)/ocaml-link.sh \
	  -cclib '-lutils -lpcre -lgnu' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLLINKFLAGS) \
	  $(OCAMLPACKAGES) $(OCAMLPACKAGES_TESTS) \
	  $(pcre_tests_THEOBJECTS) -o $@

TESTS_ENVIRONMENT = $(top_builddir)/run --test
LOG_COMPILER = $(VG)

check_PROGRAMS = pcre_tests
TESTS = pcre_tests

check-valgrind:
	$(MAKE) VG="@VG@" check

# Dependencies.
.depend: $(srcdir)/*.mli $(srcdir)/*.ml
	$(top_builddir)/ocaml-dep.sh $^
-include .depend

.PHONY: docs
