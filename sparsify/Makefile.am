# libguestfs virt-sparsify tool
# Copyright (C) 2011-2016 Red Hat Inc.
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
	virt-sparsify.pod \
	test-virt-sparsify.sh \
	test-virt-sparsify-in-place.sh

CLEANFILES = *~ *.annot *.cmi *.cmo *.cmx *.cmxa *.o virt-sparsify

SOURCES_MLI = \
	cmdline.mli

SOURCES_ML = \
	utils.ml \
	cmdline.ml \
	copying.ml \
	in_place.ml \
	sparsify.ml

SOURCES_C = \
	../fish/progress.c \
	../mllib/dev_t-c.c \
	../mllib/progress-c.c \
	../mllib/statvfs-c.c

if HAVE_OCAML

bin_PROGRAMS = virt-sparsify

virt_sparsify_SOURCES = $(SOURCES_C)
virt_sparsify_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/src \
	-I$(top_srcdir)/fish
virt_sparsify_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

BOBJECTS = \
	$(top_builddir)/mllib/guestfs_config.cmo \
	$(top_builddir)/mllib/common_gettext.cmo \
	$(top_builddir)/mllib/dev_t.cmo \
	$(top_builddir)/mllib/common_utils.cmo \
	$(top_builddir)/mllib/progress.cmo \
	$(top_builddir)/mllib/StatVFS.cmo \
	$(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

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

OCAMLCLIBS = \
	$(LIBTINFO_LIBS)

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR)

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
BEST    = c
OCAMLLINKFLAGS = mlguestfs.cma -custom
else
OBJECTS = $(XOBJECTS)
BEST    = opt
OCAMLLINKFLAGS = mlguestfs.cmxa
endif

virt_sparsify_DEPENDENCIES = $(OBJECTS) $(top_srcdir)/ocaml-link.sh

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

CLEANFILES += \
	stamp-virt-sparsify.pod \
	virt-sparsify.1

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

if ENABLE_APPLIANCE
TESTS = \
	test-virt-sparsify.sh \
	test-virt-sparsify-in-place.sh
endif ENABLE_APPLIANCE

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
