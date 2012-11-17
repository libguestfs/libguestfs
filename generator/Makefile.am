# libguestfs
# Copyright (C) 2010-2012 Red Hat Inc.
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

SOURCES = \
	types.ml \
	utils.mli \
	utils.ml \
	actions.mli \
	actions.ml \
	structs.mli \
	structs.ml \
	api_versions.mli \
	api_versions.ml \
	optgroups.ml \
	prepopts.mli \
	prepopts.ml \
	events.ml \
	pr.mli \
	pr.ml \
	docstrings.ml \
	checks.ml \
	c.ml \
	xdr.ml \
	daemon.ml \
	tests_c_api.ml \
	fish.ml \
	ocaml.ml \
	perl.ml \
	python.ml \
	ruby.ml \
	java.ml \
	haskell.ml \
	csharp.ml \
	php.ml \
	erlang.ml \
	lua.ml \
	gobject.ml \
	bindtests.ml \
	errnostring.ml \
	main.ml

SOURCES_ML = $(filter %.ml,$(SOURCES))
OBJECTS = $(SOURCES_ML:.ml=.cmo)

EXTRA_DIST = $(SOURCES) files-generated.txt

OCAMLCFLAGS = -warn-error CDEFLMPSUVYZX
OCAMLCLIBS = unix.cma str.cma

noinst_PROGRAM = generator

if HAVE_OCAML

$(srcdir)/generator: $(OBJECTS)
	$(OCAMLC) -I $(srcdir) -o $@ $(OCAMLCFLAGS) $(OCAMLCLIBS) $(OBJECTS)

.ml.cmo:
	$(OCAMLC) -I $(srcdir) $(OCAMLCFLAGS) -c $< -o $@

.mli.cmi:
	$(OCAMLC) -I $(srcdir) $(OCAMLCFLAGS) -c $< -o $@

depend: .depend

.depend: $(SOURCES)
	rm -f $@ $@-t
	$(OCAMLDEP) $^ | sed 's/  *$$//' > $@-t
	mv $@-t $@

-include .depend

else

# No OCaml compiler.  Just replace the generator with a script that
# touches stamp-generator and prints a warning.

$(srcdir)/generator: $(SOURCES)
	rm -f $@ $@-t
	echo 'echo Warning: Install OCaml compiler in order to rebuild the generated files.' >> $@-t
	echo 'touch generator/stamp-generator' >> $@-t
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
	cd $(top_srcdir) && generator/generator

CLEANFILES = $(noinst_DATA) $(noinst_PROGRAM) *.cmi *.cmo *~

SUFFIXES = .cmo .cmi .cmx .ml .mli .mll .mly
