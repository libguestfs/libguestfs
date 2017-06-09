# libguestfs get-kernel tool
# Copyright (C) 2015 Red Hat Inc.
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
	$(SOURCES_ML) $(SOURCES_C) \
	test-virt-get-kernel-docs.sh \
	virt-get-kernel.pod

SOURCES_ML = \
	get_kernel.ml

SOURCES_C = \
	dummy.c

man_MANS =
noinst_DATA =
bin_PROGRAMS =

if HAVE_OCAML

bin_PROGRAMS += virt-get-kernel

virt_get_kernel_SOURCES = $(SOURCES_C)
virt_get_kernel_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_srcdir)/common/utils \
	-I$(top_srcdir)/lib \
	-I$(top_srcdir)/fish
virt_get_kernel_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS)

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
	-I $(top_builddir)/common/mlstdutils \
	-I $(top_builddir)/common/mlutils \
	-I $(top_builddir)/mllib
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

OCAMLCLIBS = \
	-pthread -lpthread \
	-lutils \
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
	mlcutils.$(MLARCHIVE) \
	mllib.$(MLARCHIVE) \
	$(LINK_CUSTOM_OCAMLC_ONLY)

virt_get_kernel_DEPENDENCIES = \
	$(OBJECTS) \
	../common/mlstdutils/mlstdutils.$(MLARCHIVE) \
	../common/mlutils/mlcutils.$(MLARCHIVE) \
	../mllib/mllib.$(MLARCHIVE) \
	$(top_srcdir)/ocaml-link.sh
virt_get_kernel_LINK = \
	$(top_srcdir)/ocaml-link.sh -cclib '$(OCAMLCLIBS)' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) $(OCAMLLINKFLAGS) \
	  $(OBJECTS) -o $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = test-virt-get-kernel-docs.sh

# Manual pages and HTML files for the website.

man_MANS += virt-get-kernel.1
noinst_DATA += $(top_builddir)/website/virt-get-kernel.1.html

virt-get-kernel.1 $(top_builddir)/website/virt-get-kernel.1.html: stamp-virt-get-kernel.pod

stamp-virt-get-kernel.pod: virt-get-kernel.pod
	$(PODWRAPPER) \
	  --man virt-get-kernel.1 \
	  --html $(top_builddir)/website/virt-get-kernel.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

# Dependencies.
depend: .depend

.depend: $(wildcard $(abs_srcdir)/*.mli) $(wildcard $(abs_srcdir)/*.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep -I ../ocaml -I $(abs_srcdir) -I $(abs_top_builddir)/common/mlstdutils -I $(abs_top_builddir)/common/mlutils -I $(abs_top_builddir)/mllib $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

endif

.PHONY: depend
