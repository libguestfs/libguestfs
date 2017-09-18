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
	common_utils_tests.ml \
	getopt_tests.ml \
	JSON_tests.ml \
	test-getopt.sh

SOURCES_MLI = \
	checksums.mli \
	common_gettext.mli \
	common_utils.mli \
	curl.mli \
	getopt.mli \
	JSON.mli \
	planner.mli \
	regedit.mli \
	registry.mli \
	URI.mli \
	xpath_helpers.mli

SOURCES_ML = \
	common_gettext.ml \
	getopt.ml \
	common_utils.ml \
	URI.ml \
	planner.ml \
	registry.ml \
	regedit.ml \
	JSON.ml \
	curl.ml \
	checksums.ml \
	xpath_helpers.ml

SOURCES_C = \
	../common/options/decrypt.c \
	../common/options/keys.c \
	../common/options/uri.c \
	common_utils-c.c \
	getopt-c.c \
	uri-c.c

if HAVE_OCAML

# We pretend that we're building a C library.  automake handles the
# compilation of the C sources for us.  At the end we take the C
# objects and OCaml objects and link them into the OCaml library.
# This C library is never used.

noinst_LIBRARIES = libmllib.a

if !HAVE_OCAMLOPT
MLLIB_CMA = mllib.cma
else
MLLIB_CMA = mllib.cmxa
endif

noinst_DATA = $(MLLIB_CMA)

libmllib_a_SOURCES = $(SOURCES_C)
libmllib_a_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/common/utils \
	-I$(top_srcdir)/lib \
	-I$(top_srcdir)/common/options \
	-I$(top_srcdir)/common/mlxml \
	-I$(top_srcdir)/common/mlstdutils \
	-I$(top_srcdir)/common/mlutils
libmllib_a_CFLAGS = \
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
	-I $(top_builddir)/common/utils/.libs \
	-I $(top_builddir)/lib/.libs \
	-I $(top_builddir)/gnulib/lib/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/common/mlxml \
	-I $(top_builddir)/common/mlstdutils \
	-I $(top_builddir)/common/mlutils \
	-I $(builddir)
OCAMLPACKAGES_TESTS = $(MLLIB_CMA)
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif
if HAVE_OCAML_PKG_OUNIT
OCAMLPACKAGES_TESTS += -package oUnit
endif

OCAMLCLIBS = \
	-lutils \
	$(LIBTINFO_LIBS) \
	$(LIBCRYPT_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LIBXML2_LIBS) \
	$(LIBINTL) \
	-lgnu

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR)

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif

libmllib_a_DEPENDENCIES = $(OBJECTS)

$(MLLIB_CMA): $(OBJECTS) libmllib.a
	$(OCAMLFIND) mklib $(OCAMLPACKAGES) \
	    $(OBJECTS) $(libmllib_a_OBJECTS) -o mllib

# Tests.

common_utils_tests_SOURCES = dummy.c
common_utils_tests_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/lib
common_utils_tests_BOBJECTS = common_utils_tests.cmo
common_utils_tests_XOBJECTS = $(common_utils_tests_BOBJECTS:.cmo=.cmx)

getopt_tests_SOURCES = dummy.c
getopt_tests_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/lib
getopt_tests_BOBJECTS = getopt_tests.cmo
getopt_tests_XOBJECTS = $(getopt_tests_BOBJECTS:.cmo=.cmx)

JSON_tests_SOURCES = dummy.c
JSON_tests_BOBJECTS = JSON_tests.cmo
JSON_tests_XOBJECTS = $(JSON_tests_BOBJECTS:.cmo=.cmx)

# Can't call the following as <test>_OBJECTS because automake gets confused.
if !HAVE_OCAMLOPT
common_utils_tests_THEOBJECTS = $(common_utils_tests_BOBJECTS)
common_utils_tests.cmo: OCAMLPACKAGES += $(OCAMLPACKAGES_TESTS)

getopt_tests_THEOBJECTS = $(getopt_tests_BOBJECTS)
getopt_tests.cmo: OCAMLPACKAGES += $(OCAMLPACKAGES_TESTS)

JSON_tests_THEOBJECTS = $(JSON_tests_BOBJECTS)
JSON_tests.cmo: OCAMLPACKAGES += $(OCAMLPACKAGES_TESTS)
else
common_utils_tests_THEOBJECTS = $(common_utils_tests_XOBJECTS)
common_utils_tests.cmx: OCAMLPACKAGES += $(OCAMLPACKAGES_TESTS)

getopt_tests_THEOBJECTS = $(getopt_tests_XOBJECTS)
getopt_tests.cmx: OCAMLPACKAGES += $(OCAMLPACKAGES_TESTS)

JSON_tests_THEOBJECTS = $(JSON_tests_XOBJECTS)
JSON_tests.cmx: OCAMLPACKAGES += $(OCAMLPACKAGES_TESTS)
endif

OCAMLLINKFLAGS = \
	mlstdutils.$(MLARCHIVE) \
	mlcutils.$(MLARCHIVE) \
	mlguestfs.$(MLARCHIVE) \
	$(LINK_CUSTOM_OCAMLC_ONLY)

common_utils_tests_DEPENDENCIES = \
	$(common_utils_tests_THEOBJECTS) \
	../common/mlstdutils/mlstdutils.$(MLARCHIVE) \
	$(MLLIB_CMA) \
	$(top_srcdir)/ocaml-link.sh
common_utils_tests_LINK = \
	$(top_srcdir)/ocaml-link.sh -cclib '-lutils $(LIBXML2_LIBS) -lgnu' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLLINKFLAGS) \
	  $(OCAMLPACKAGES) $(OCAMLPACKAGES_TESTS) \
	  $(common_utils_tests_THEOBJECTS) -o $@

getopt_tests_DEPENDENCIES = \
	$(getopt_tests_THEOBJECTS) \
	../common/mlstdutils/mlstdutils.$(MLARCHIVE) \
	$(MLLIB_CMA) \
	$(top_srcdir)/ocaml-link.sh
getopt_tests_LINK = \
	$(top_srcdir)/ocaml-link.sh -cclib '-lutils $(LIBXML2_LIBS) -lgnu' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLLINKFLAGS) \
	  $(OCAMLPACKAGES) $(OCAMLPACKAGES_TESTS) \
	  $(getopt_tests_THEOBJECTS) -o $@

JSON_tests_DEPENDENCIES = \
	$(JSON_tests_THEOBJECTS) \
	../common/mlstdutils/mlstdutils.$(MLARCHIVE) \
	$(MLLIB_CMA) \
	$(top_srcdir)/ocaml-link.sh
JSON_tests_LINK = \
	$(top_srcdir)/ocaml-link.sh -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLLINKFLAGS) \
	  $(OCAMLPACKAGES) $(OCAMLPACKAGES_TESTS) \
	  $(JSON_tests_THEOBJECTS) -o $@

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-getopt.sh
check_PROGRAMS = \
	getopt_tests

if HAVE_OCAML_PKG_OUNIT
check_PROGRAMS += common_utils_tests JSON_tests
TESTS += common_utils_tests JSON_tests
endif

check-valgrind:
	$(MAKE) VG="@VG@" check

# Dependencies.
.depend: *.mli *.ml
	$(top_builddir)/ocaml-dep.sh $^
-include .depend

endif

.PHONY: docs
