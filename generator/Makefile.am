# libguestfs
# Copyright (C) 2010-2016 Red Hat Inc.
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
	bindtests.ml \
	bindtests.mli \
	c.ml \
	c.mli \
	checks.ml \
	checks.mli \
	csharp.ml \
	csharp.mli \
	customize.ml \
	customize.mli \
	daemon.ml \
	daemon.mli \
	docstrings.ml \
	docstrings.mli \
	erlang.ml \
	erlang.mli \
	errnostring.ml \
	errnostring.mli \
	events.ml \
	events.mli \
	fish.ml \
	fish.mli \
	gobject.ml \
	gobject.mli \
	golang.ml \
	golang.mli \
	haskell.ml \
	haskell.mli \
	java.ml \
	java.mli \
	lua.ml \
	lua.mli \
	main.ml \
	ocaml.ml \
	ocaml.mli \
	optgroups.ml \
	optgroups.mli \
	perl.ml \
	perl.mli \
	php.ml \
	php.mli \
	pr.ml \
	pr.mli \
	prepopts.ml \
	prepopts.mli \
	python.ml \
	python.mli \
	ruby.ml \
	ruby.mli \
	structs.ml \
	structs.mli \
	tests_c_api.ml \
	tests_c_api.mli \
	types.ml \
	utils.ml \
	utils.mli \
	xdr.ml \
	xdr.mli

# In build dependency order.
objects = \
	types.cmo \
	utils.cmo \
	actions.cmo \
	structs.cmo \
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

DISTCLEANFILES = .depend .pod2text.data.version.2

SUFFIXES = .cmo .cmi .cmx .ml .mli .mll .mly
