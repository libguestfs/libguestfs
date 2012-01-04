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
	generator_types.ml \
	generator_utils.mli \
	generator_utils.ml \
	generator_actions.mli \
	generator_actions.ml \
	generator_structs.mli \
	generator_structs.ml \
	generator_api_versions.mli \
	generator_api_versions.ml \
	generator_optgroups.ml \
	generator_prepopts.mli \
	generator_prepopts.ml \
	generator_events.ml \
	generator_pr.mli \
	generator_pr.ml \
	generator_docstrings.ml \
	generator_checks.ml \
	generator_c.ml \
	generator_xdr.ml \
	generator_daemon.ml \
	generator_tests_c_api.ml \
	generator_fish.ml \
	generator_ocaml.ml \
	generator_perl.ml \
	generator_python.ml \
	generator_ruby.ml \
	generator_java.ml \
	generator_haskell.ml \
	generator_csharp.ml \
	generator_php.ml \
	generator_erlang.ml \
	generator_gobject.ml \
	generator_bindtests.ml \
	generator_errnostring.ml \
	generator_main.ml

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
	cd $(top_srcdir) && generator/generator

CLEANFILES = $(noinst_DATA) $(noinst_PROGRAM) *.cmi *.cmo *~

SUFFIXES = .cmo .cmi .cmx .ml .mli .mll .mly
