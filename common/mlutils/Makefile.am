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
	c_utils_unit_tests.ml

SOURCES_MLI = \
	c_utils.mli \
	unix_utils.mli

SOURCES_ML = \
	c_utils.ml \
	unix_utils.ml

SOURCES_C = \
	c_utils-c.c \
	unix_utils-c.c

# We pretend that we're building a C library.  automake handles the
# compilation of the C sources for us.  At the end we take the C
# objects and OCaml objects and link them into the OCaml library.
# This C library is never used.

noinst_LIBRARIES = libmlcutils.a

if !HAVE_OCAMLOPT
MLCUTILS_CMA = mlcutils.cma
else
MLCUTILS_CMA = mlcutils.cmxa
endif

noinst_DATA = $(MLCUTILS_CMA)

# lib/guestfs-internal-all.h header is used here.  It probably
# shouldn't be located under lib.  XXX
libmlcutils_a_SOURCES = $(SOURCES_C)
libmlcutils_a_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(shell $(OCAMLC) -where)
libmlcutils_a_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	-fPIC

BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/gnulib/lib/.libs \
	-I $(top_builddir)/common/utils/.libs \
	-I $(top_builddir)/common/mlstdutils \
	-I $(builddir)

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR)

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif

libmlcutils_a_DEPENDENCIES = $(OBJECTS)

$(MLCUTILS_CMA): $(OBJECTS) libmlcutils.a
	$(OCAMLFIND) mklib $(OCAMLPACKAGES) \
	    $(OBJECTS) $(libmlcutils_a_OBJECTS) \
	    -cclib -lutils \
	    -o mlcutils

# Tests.

TESTS =
check_PROGRAMS =

if HAVE_OCAML_PKG_OUNIT
TESTS += c_utils_unit_tests
check_PROGRAMS += c_utils_unit_tests
endif

c_utils_unit_tests_BOBJECTS = \
	c_utils_unit_tests.cmo
c_utils_unit_tests_XOBJECTS = $(c_utils_unit_tests_BOBJECTS:.cmo=.cmx)

c_utils_unit_tests_SOURCES = dummy.c
c_utils_unit_tests_CPPFLAGS = $(libmlcutils_a_CPPFLAGS)
c_utils_unit_tests_CFLAGS = $(libmlcutils_a_CFLAGS)

if !HAVE_OCAMLOPT
# Can't call this c_utils_unit_tests_OBJECTS because automake gets confused.
c_utils_unit_tests_THEOBJECTS = $(c_utils_unit_tests_BOBJECTS)
c_utils_unit_tests.cmo: OCAMLPACKAGES += -package oUnit
else
c_utils_unit_tests_THEOBJECTS = $(c_utils_unit_tests_XOBJECTS)
c_utils_unit_tests.cmx: OCAMLPACKAGES += -package oUnit
endif

OCAMLLINKFLAGS = \
	mlstdutils.$(MLARCHIVE) \
	mlcutils.$(MLARCHIVE) \
	$(LINK_CUSTOM_OCAMLC_ONLY)

c_utils_unit_tests_DEPENDENCIES = \
	$(c_utils_unit_tests_THEOBJECTS) \
	../mlstdutils/mlstdutils.$(MLARCHIVE) \
	mlcutils.$(MLARCHIVE) \
	$(top_srcdir)/ocaml-link.sh
c_utils_unit_tests_LINK = \
	$(top_srcdir)/ocaml-link.sh -cclib '-lutils -lgnu' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) \
	  $(OCAMLPACKAGES) -package oUnit \
	  $(OCAMLLINKFLAGS) \
	  $(c_utils_unit_tests_THEOBJECTS) -o $@

# Dependencies.
.depend: *.mli *.ml
	$(top_builddir)/ocaml-dep.sh $^
-include .depend

.PHONY: docs
