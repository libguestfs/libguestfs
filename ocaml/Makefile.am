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
	guestfs_c.c guestfs_c.h \
	guestfs_inspector.mli guestfs_inspector.ml \
	.depend META.in \
	run-bindtests \
	t/*.ml

CLEANFILES = *.cmi *.cmo *.cmx *.cma *.cmxa *.o *.a *.so
CLEANFILES += t/*.cmi t/*.cmo t/*.cmx t/*.o t/*.a t/*.so

AM_CPPFLAGS = -I$(top_builddir) -I$(OCAMLLIB) -I$(top_srcdir)/ocaml \
  -I$(top_srcdir)/src -I$(top_builddir)/src \
  $(WARN_CFLAGS) $(WERROR_CFLAGS)

if HAVE_OCAML
if HAVE_XML_LIGHT

noinst_DATA = mlguestfs.cma mlguestfs.cmxa META

OBJS = guestfs_c.o guestfs_c_actions.o guestfs.cmo guestfs_inspector.cmo
XOBJS = $(OBJS:.cmo=.cmx)

mlguestfs.cma: $(OBJS)
	$(OCAMLMKLIB) -o mlguestfs $^ -L$(top_builddir)/src/.libs -lguestfs

mlguestfs.cmxa: $(XOBJS)
	$(OCAMLMKLIB) -o mlguestfs $^ -L$(top_builddir)/src/.libs -lguestfs

guestfs_c.o: guestfs_c.c
	$(CC) $(AM_CPPFLAGS) $(CFLAGS) -fPIC -Wall -c $<

guestfs_c_actions.o: guestfs_c_actions.c
	$(CC) $(AM_CPPFLAGS) $(CFLAGS) -fPIC -Wall -c $<

TESTS_ENVIRONMENT = \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	$(VG)

TESTS = run-bindtests \
	t/guestfs_005_load t/guestfs_010_launch t/guestfs_050_lvcreate \
	t/guestfs_060_readdir t/guestfs_500_inspect
noinst_DATA += bindtests \
	t/guestfs_005_load t/guestfs_010_launch t/guestfs_050_lvcreate \
	t/guestfs_060_readdir t/guestfs_500_inspect

bindtests: bindtests.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package xml-light,unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_005_load: t/guestfs_005_load.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package xml-light,unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_010_launch: t/guestfs_010_launch.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package xml-light,unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_050_lvcreate: t/guestfs_050_lvcreate.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package xml-light,unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_060_readdir: t/guestfs_060_readdir.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package xml-light,unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_500_inspect: t/guestfs_500_inspect.cmx mlguestfs.cmxa
	mkdir -p t
	$(OCAMLFIND) ocamlopt -cclib -L$(top_builddir)/src/.libs -I . -package xml-light,unix -linkpkg mlguestfs.cmxa $< -o $@

# Need to rebuild the tests from source if the main library has
# changed at all, otherwise we get inconsistent assumptions.
t/%.cmx: t/%.ml mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt -package xml-light,unix -linkpkg -c $< -o $@

.mli.cmi:
	$(OCAMLFIND) ocamlc -package xml-light,unix -c $< -o $@
.ml.cmo:
	$(OCAMLFIND) ocamlc -package xml-light,unix -c $< -o $@
.ml.cmx:
	$(OCAMLFIND) ocamlopt -package xml-light,unix -c $< -o $@

depend: .depend

.depend: $(wildcard *.mli) $(wildcard *.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep $^ | sed 's/  *$$//' | sort > $@-t
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
	  META *.so *.a *.cma *.cmx *.cmxa *.cmi *.mli

CLEANFILES += $(noinst_DATA)

endif
endif

# Tell version 3.79 and up of GNU make to not build goals in this
# directory in parallel.  (Possible solution for RHBZ#502309).
.NOTPARALLEL:
