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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

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

AM_CPPFLAGS = -I$(top_builddir) -I$(OCAMLLIB) -I$(top_srcdir)/ocaml \
  -I$(top_srcdir)/src -I$(top_builddir)/src \
  $(WARN_CFLAGS) $(WERROR_CFLAGS)

if HAVE_OCAML

noinst_DATA = mlguestfs.cma mlguestfs.cmxa META

OBJS = guestfs_c.o guestfs_c_actions.o guestfs.cmo
XOBJS = $(OBJS:.cmo=.cmx)

mlguestfs.cma: $(OBJS)
	$(OCAMLMKLIB) -o mlguestfs $^ -L$(top_builddir)/src/.libs -lguestfs

mlguestfs.cmxa: $(XOBJS)
	$(OCAMLMKLIB) -o mlguestfs $^ -L$(top_builddir)/src/.libs -lguestfs

guestfs_c.o: guestfs_c.c
	$(CC) $(AM_CPPFLAGS) $(CFLAGS) -fPIC -Wall -c $<

guestfs_c_actions.o: guestfs_c_actions.c
	$(CC) $(AM_CPPFLAGS) $(CFLAGS) -fPIC -Wall -c $(srcdir)/$<

if HAVE_OCAMLDOC

noinst_DATA += html/index.html

html/index.html: $(srcdir)/guestfs*.mli $(srcdir)/guestfs*.ml
	mkdir -p html
	-$(OCAMLDOC) -d html -html $^
endif

TESTS_ENVIRONMENT = \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	TMPDIR=$(top_builddir) \
	$(VG)

TESTS = run-bindtests \
	t/guestfs_005_load \
	t/guestfs_010_basic \
	t/guestfs_070_threads \
	t/guestfs_080_optargs \
	t/guestfs_400_events \
	t/guestfs_400_progress
noinst_DATA += bindtests \
	t/guestfs_005_load \
	t/guestfs_010_basic \
	t/guestfs_070_threads \
	t/guestfs_080_optargs \
	t/guestfs_400_events \
	t/guestfs_400_progress

bindtests: bindtests.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_005_load: t/guestfs_005_load.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_010_basic: t/guestfs_010_basic.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_070_threads: t/guestfs_070_threads.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package unix,threads -thread -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_080_optargs: t/guestfs_080_optargs.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_400_events: t/guestfs_400_events.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_400_progress: t/guestfs_400_progress.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

# Need to rebuild the tests from source if the main library has
# changed at all, otherwise we get inconsistent assumptions.
t/guestfs_070_threads.cmx: t/guestfs_070_threads.ml mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt -package unix,threads -thread -linkpkg -c $< -o $@

t/%.cmx: t/%.ml mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt -package unix -linkpkg -c $< -o $(builddir)/$@

%.cmi: %.mli
	$(OCAMLFIND) ocamlc -package unix -c $< -o $(builddir)/$@
%.cmo: %.ml
	$(OCAMLFIND) ocamlc -package unix -c $< -o $(builddir)/$@
%.cmx: %.ml
	$(OCAMLFIND) ocamlopt -package unix -c $< -o $(builddir)/$@

depend: .depend

.depend: $(wildcard *.mli) $(wildcard *.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  sort > $@-t
	mv $@-t $@

include .depend

SUFFIXES = .cmo .cmi .cmx .ml .mli .mll .mly

# Do the installation by hand, because we want to run ocamlfind.
install-data-hook:
	mkdir -p $(DESTDIR)$(OCAMLLIB)
	mkdir -p $(DESTDIR)$(OCAMLLIB)/stublibs
	$(OCAMLFIND) install \
	  -ldconf ignore -destdir $(DESTDIR)$(OCAMLLIB) \
	  guestfs \
	  META *.so *.a *.cma *.cmx *.cmxa *.cmi $(srcdir)/*.mli

CLEANFILES += $(noinst_DATA)

endif

# Tell version 3.79 and up of GNU make to not build goals in this
# directory in parallel.  (Possible solution for RHBZ#502309).
.NOTPARALLEL:
