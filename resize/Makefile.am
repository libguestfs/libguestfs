# libguestfs virt-resize 2.0 tools
# Copyright (C) 2011 Red Hat Inc.
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

include $(top_srcdir)/subdir-rules.mk

EXTRA_DIST = \
	$(SOURCES) \
	virt-resize.pod \
	test-virt-resize.sh

CLEANFILES = *~ *.cmi *.cmo *.cmx *.cmxa *.o virt-resize test.img

if HAVE_OCAML
if HAVE_OCAML_PCRE

# Alphabetical order.
SOURCES = \
	progress.ml \
	resize.ml \
	utils.ml

# Note this list must be in dependency order.
OBJECTS = \
	utils.cmx \
	progress.cmx \
	resize.cmx

bin_SCRIPTS = virt-resize

# -I $(top_builddir)/src/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = -package pcre -I $(top_builddir)/src/.libs -I ../ocaml

OCAMLCFLAGS = -g -warn-error CDEFLMPSUVYZX $(OCAMLPACKAGES)
OCAMLOPTFLAGS = $(OCAMLCFLAGS)

virt-resize: $(OBJECTS)
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) mlguestfs.cmxa -linkpkg $^ -o $@

.mli.cmi:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
.ml.cmo:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
.ml.cmx:
	$(OCAMLFIND) ocamlopt $(OCAMLCFLAGS) -c $< -o $@

# Manual pages and HTML files for the website.

man_MANS = virt-resize.1

noinst_DATA = $(top_builddir)/html/virt-resize.1.html

virt-resize.1 $(top_builddir)/html/virt-resize.1.html: stamp-virt-resize.pod

stamp-virt-resize.pod: virt-resize.pod
	$(top_builddir)/podwrapper.sh \
	  --man virt-resize.1 \
	  --html $(top_builddir)/html/virt-resize.1.html \
	  $<
	touch $@

CLEANFILES += stamp-virt-resize.pod

# Tests.

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	TMPDIR=$(top_builddir)

TESTS = test-virt-resize.sh

# Dependencies.
depend: .depend

.depend: $(wildcard *.mli) $(wildcard *.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  sort > $@-t
	mv $@-t $@

include .depend

.PHONY: depend docs

endif
endif

# Parallel builds don't obey dependencies for some reason we
# don't understand.
.NOTPARALLEL:
