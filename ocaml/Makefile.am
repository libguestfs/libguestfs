# libguestfs OCaml bindings
# Copyright (C) 2009 Red Hat Inc.
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

generator_built = \
	guestfs.mli \
	guestfs.ml \
	guestfs_c_actions.c \
	bindtests.ml

EXTRA_DIST = \
	$(generator_built) \
	.depend \
	guestfs_c.c guestfs_c.h \
	html/.gitignore \
	META.in \
	run-bindtests \
	t/*.ml

CLEANFILES = *.cmi *.cmo *.cmx *.cma *.cmxa *.o *.a *.so
CLEANFILES += t/*.cmi t/*.cmo t/*.cmx t/*.o t/*.a t/*.so

if HAVE_OCAML

OCAMLCFLAGS = -g -warn-error CDEFLMPSUVYZX
OCAMLOPTFLAGS = $(OCAMLCFLAGS)

noinst_DATA = mlguestfs.cma mlguestfs.cmxa META

# Build the C part into a library, so that automake handles the C
# compilation step for us.  Note that we don't directly use this
# library; we link with the object files that it generates.
noinst_LIBRARIES = libguestfsocaml.a

mlguestfs.cma: libguestfsocaml.a guestfs.cmo
	$(OCAMLMKLIB) -o mlguestfs \
	  $(libguestfsocaml_a_OBJECTS) guestfs.cmo \
	  -L$(top_builddir)/src/.libs -lguestfs

mlguestfs.cmxa: libguestfsocaml.a guestfs.cmx
	$(OCAMLMKLIB) -o mlguestfs \
	  $(libguestfsocaml_a_OBJECTS) guestfs.cmx \
	  -L$(top_builddir)/src/.libs -lguestfs

libguestfsocaml_a_CFLAGS = \
	-I$(top_builddir) -I$(OCAMLLIB) -I$(top_srcdir)/ocaml \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	-fPIC
libguestfsocaml_a_SOURCES = guestfs_c.c guestfs_c_actions.c

if HAVE_OCAMLDOC

noinst_DATA += html/index.html

html/index.html: $(srcdir)/guestfs*.mli $(srcdir)/guestfs*.ml
	mkdir -p html
	-$(OCAMLDOC) -d html -html $^
endif

TESTS_ENVIRONMENT = \
	CAML_LD_LIBRARY_PATH=. \
	$(top_builddir)/run \
	$(VG)

test_progs = \
	t/guestfs_005_load \
	t/guestfs_080_optargs \
	t/guestfs_400_events

if ENABLE_APPLIANCE
test_progs += \
	t/guestfs_010_basic \
	t/guestfs_070_threads \
	t/guestfs_400_progress
endif

TESTS = run-bindtests \
	$(sort \
		$(patsubst %,%.bc,$(test_progs)) \
		$(patsubst %,%.opt,$(test_progs)))

noinst_DATA += \
	bindtests.bc bindtests.opt \
	$(test_progs:%=%.bc) \
	$(test_progs:%=%.opt)

bindtests.bc: bindtests.cmo mlguestfs.cma
	mkdir -p t
	LD_LIBRARY_PATH=../src/.libs \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

bindtests.opt: bindtests.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_005_load.bc: t/guestfs_005_load.cmo mlguestfs.cma
	mkdir -p t
	LD_LIBRARY_PATH=../src/.libs \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

t/guestfs_005_load.opt: t/guestfs_005_load.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_010_basic.bc: t/guestfs_010_basic.cmo mlguestfs.cma
	mkdir -p t
	LD_LIBRARY_PATH=../src/.libs \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

t/guestfs_010_basic.opt: t/guestfs_010_basic.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_070_threads.bc: t/guestfs_070_threads.cmo mlguestfs.cma
	mkdir -p t
	LD_LIBRARY_PATH=../src/.libs \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix,threads -thread -linkpkg mlguestfs.cma $< -o $@

t/guestfs_070_threads.opt: t/guestfs_070_threads.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix,threads -thread -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_080_optargs.bc: t/guestfs_080_optargs.cmo mlguestfs.cma
	mkdir -p t
	LD_LIBRARY_PATH=../src/.libs \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

t/guestfs_080_optargs.opt: t/guestfs_080_optargs.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_400_events.bc: t/guestfs_400_events.cmo mlguestfs.cma
	mkdir -p t
	LD_LIBRARY_PATH=../src/.libs \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

t/guestfs_400_events.opt: t/guestfs_400_events.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_400_progress.bc: t/guestfs_400_progress.cmo mlguestfs.cma
	mkdir -p t
	LD_LIBRARY_PATH=../src/.libs \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

t/guestfs_400_progress.opt: t/guestfs_400_progress.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

# Explicit rules for this test which requires 'threads' package.
t/guestfs_070_threads.cmo: t/guestfs_070_threads.ml mlguestfs.cma
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -package unix,threads -thread -linkpkg -c $< -o $@

t/guestfs_070_threads.cmx: t/guestfs_070_threads.ml mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -package unix,threads -thread -linkpkg -c $< -o $@

%.cmi: %.mli
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -package unix -c $< -o $(builddir)/$@
%.cmo: %.ml mlguestfs.cma
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -package unix -c $< -o $(builddir)/$@
%.cmx: %.ml mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -package unix -c $< -o $(builddir)/$@

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

SUFFIXES = .cmo .cmi .cmx .ml .mli .mll .mly

# Do the installation by hand, because we want to run ocamlfind.
install-data-hook:
	mkdir -p $(DESTDIR)$(OCAMLLIB)
	mkdir -p $(DESTDIR)$(OCAMLLIB)/stublibs
	$(OCAMLFIND) install \
	  -ldconf ignore -destdir $(DESTDIR)$(OCAMLLIB) \
	  guestfs \
	  META *.so *.a *.cma *.cmx *.cmxa *.cmi $(srcdir)/*.mli
	rm $(DESTDIR)$(OCAMLLIB)/guestfs/bindtests.*
	rm $(DESTDIR)$(OCAMLLIB)/guestfs/libguestfsocaml.a

CLEANFILES += $(noinst_DATA)

endif

# Tell version 3.79 and up of GNU make to not build goals in this
# directory in parallel.  (Possible solution for RHBZ#502309).
.NOTPARALLEL:
