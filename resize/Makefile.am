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
	run-resize-locally \
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

OCAMLPACKAGES = -package guestfs,pcre
OCAMLCFLAGS = -g -warn-error CDEFLMPSUVYZX $(OCAMLPACKAGES)
OCAMLOPTFLAGS = $(OCAMLCFLAGS)

virt-resize: $(OBJECTS)
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -linkpkg $^ -o $@

.mli.cmi:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
.ml.cmo:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
.ml.cmx:
	$(OCAMLFIND) ocamlopt $(OCAMLCFLAGS) -c $< -o $@

# Manual pages and HTML files for the website.

man_MANS = virt-resize.1

noinst_DATA = $(top_builddir)/html/virt-resize.1.html

virt-%.1: virt-%.pod
	$(top_srcdir)/podwrapper.sh \
	  --man $@ \
	  $<

$(top_builddir)/html/virt-%.1.html: virt-%
	$(top_srcdir)/podwrapper.sh \
	  --html $@ \
	  $<

# Tests.

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance

TESTS = test-virt-resize.sh

# Dependencies.
depend: .depend

.depend: $(wildcard *.mli) $(wildcard *.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep $(OCAMLPACKAGES) $^ | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  sort > $@-t
	mv $@-t $@

include .depend

.PHONY: depend docs

endif
endif
