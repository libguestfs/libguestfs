# libguestfs virt-sparsify tool
# Copyright (C) 2011-2018 Red Hat Inc.
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
	$(SOURCES_MLI) $(SOURCES_ML) $(SOURCES_C) \
	test-virt-sparsify.sh \
	test-virt-sparsify-docs.sh \
	test-virt-sparsify-in-place.sh \
	test-virt-sparsify-in-place-fstrim-unsupported.sh \
	virt-sparsify.pod

SOURCES_MLI = \
	cmdline.mli \
	copying.mli \
	in_place.mli \
	sparsify.mli \
	utils.mli

SOURCES_ML = \
	utils.ml \
	cmdline.ml \
	copying.ml \
	in_place.ml \
	sparsify.ml

SOURCES_C = \
	dummy.c

if HAVE_OCAML

bin_PROGRAMS = virt-sparsify

virt_sparsify_SOURCES = $(SOURCES_C)
virt_sparsify_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/common/utils \
	-I$(top_srcdir)/lib \
	-I$(top_srcdir)/fish
virt_sparsify_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

# -I $(top_builddir)/lib/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/common/utils/.libs \
	-I $(top_builddir)/common/progress/.libs \
	-I $(top_builddir)/lib/.libs \
	-I $(top_builddir)/gnulib/lib/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/common/mlstdutils \
	-I $(top_builddir)/common/mlprogress \
	-I $(top_builddir)/common/mlutils \
	-I $(top_builddir)/common/mlgettext \
	-I $(top_builddir)/common/mlpcre \
	-I $(top_builddir)/common/mltools
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

OCAMLCLIBS = \
	-lprogress \
	-lutils \
	$(LIBTINFO_LIBS) \
	$(LIBXML2_LIBS) \
	$(LIBINTL) \
	-lgnu

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR)

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif

OCAMLLINKFLAGS = \
	mlstdutils.$(MLARCHIVE) \
	mlguestfs.$(MLARCHIVE) \
	mlprogress.$(MLARCHIVE) \
	mlgettext.$(MLARCHIVE) \
	mlpcre.$(MLARCHIVE) \
	mlcutils.$(MLARCHIVE) \
	mltools.$(MLARCHIVE) \
	$(LINK_CUSTOM_OCAMLC_ONLY)

virt_sparsify_DEPENDENCIES = \
	$(OBJECTS) \
	../common/mlstdutils/mlstdutils.$(MLARCHIVE) \
	../common/mlutils/mlcutils.$(MLARCHIVE) \
	../common/mlgettext/mlgettext.$(MLARCHIVE) \
	../common/mlpcre/mlpcre.$(MLARCHIVE) \
	../common/mltools/mltools.$(MLARCHIVE) \
	$(top_srcdir)/ocaml-link.sh
virt_sparsify_LINK = \
	$(top_srcdir)/ocaml-link.sh -cclib '$(OCAMLCLIBS)' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) $(OCAMLLINKFLAGS) \
	  $(OBJECTS) -o $@

# Manual pages and HTML files for the website.

man_MANS = virt-sparsify.1

noinst_DATA = $(top_builddir)/website/virt-sparsify.1.html

virt-sparsify.1 $(top_builddir)/website/virt-sparsify.1.html: stamp-virt-sparsify.pod

stamp-virt-sparsify.pod: virt-sparsify.pod
	$(PODWRAPPER) \
	  --man virt-sparsify.1 \
	  --html $(top_builddir)/website/virt-sparsify.1.html \
	  --license GPLv2+ \
	  --warning general \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-virt-sparsify-docs.sh

if ENABLE_APPLIANCE
TESTS += \
	test-virt-sparsify.sh \
	test-virt-sparsify-in-place.sh \
	test-virt-sparsify-in-place-fstrim-unsupported.sh
endif ENABLE_APPLIANCE

check-valgrind:
	$(MAKE) VG="@VG@" check

# OCaml dependencies.
.depend: *.mli *.ml
	$(top_builddir)/ocaml-dep.sh $^
-include .depend

endif

.PHONY: docs
