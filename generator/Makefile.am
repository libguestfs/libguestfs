# libguestfs
# Copyright (C) 2010-2014 Red Hat Inc.
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

# In alphabetical order.
sources = \
	actions.ml \
	actions.mli \
	api_versions.ml \
	api_versions.mli \
	bindtests.ml \
	c.ml \
	checks.ml \
	csharp.ml \
	customize.ml \
	daemon.ml \
	docstrings.ml \
	erlang.ml \
	errnostring.ml \
	events.ml \
	fish.ml \
	gobject.ml \
	golang.ml \
	haskell.ml \
	java.ml \
	lua.ml \
	main.ml \
	ocaml.ml \
	optgroups.ml \
	perl.ml \
	php.ml \
	pr.ml \
	pr.mli \
	prepopts.ml \
	prepopts.mli \
	python.ml \
	ruby.ml \
	structs.ml \
	structs.mli \
	tests_c_api.ml \
	types.ml \
	utils.ml \
	utils.mli \
	xdr.ml

# In build dependency order.
objects = \
	types.cmo \
	utils.cmo \
	actions.cmo \
	structs.cmo \
	api_versions.cmo \
	optgroups.cmo \
	prepopts.cmo \
	events.cmo \
	pr.cmo \
	docstrings.cmo \
	checks.cmo \
	c.cmo \
	xdr.cmo \
	daemon.cmo \
	tests_c_api.cmo \
	fish.cmo \
	ocaml.cmo \
	perl.cmo \
	python.cmo \
	ruby.cmo \
	java.cmo \
	haskell.cmo \
	csharp.cmo \
	php.cmo \
	erlang.cmo \
	lua.cmo \
	gobject.cmo \
	golang.cmo \
	bindtests.cmo \
	errnostring.cmo \
	customize.cmo \
	main.cmo

EXTRA_DIST = $(sources) files-generated.txt

OCAMLCFLAGS = $(OCAML_WARN_ERROR) -I $(srcdir) -I . -package unix,str

noinst_PROGRAM = generator

if HAVE_OCAML

generator: $(objects)
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -linkpkg $^ -o $@

# Dependencies.
%.cmi: %.mli
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
%.cmi: %.ml
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
%.cmo: %.ml
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@

depend: .depend

.depend: $(wildcard $(abs_srcdir)/*.mli) $(wildcard $(abs_srcdir)/*.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep -I ../ocaml -I $(abs_srcdir) $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

else

# No OCaml compiler.  Just replace the generator with a script that
# prints a warning.

generator:
	rm -f $@ $@-t
	echo 'echo Warning: Install OCaml compiler in order to rebuild the generated files.' > $@-t
	chmod +x $@-t
	mv $@-t $@

endif

noinst_DATA = stamp-generator

# Run the generator.
# Git removes empty directories, so in cases where the
# generator is creating the sole file in a directory, we
# have to create the directory first.
stamp-generator: generator
	mkdir -p $(top_srcdir)/perl/lib/Sys
	mkdir -p $(top_srcdir)/ruby/ext/guestfs
	mkdir -p $(top_srcdir)/java/com/redhat/et/libguestfs
	mkdir -p $(top_srcdir)/csharp
	mkdir -p $(top_srcdir)/gobject/src
	mkdir -p $(top_srcdir)/gobject/include
	mkdir -p $(top_srcdir)/gobject/include/guestfs-gobject
	cd $(top_srcdir) && $(abs_builddir)/generator
	touch $@

CLEANFILES = $(noinst_DATA) $(noinst_PROGRAM) *.cmi *.cmo *~

DISTCLEANFILES = .depend

SUFFIXES = .cmo .cmi .cmx .ml .mli .mll .mly
