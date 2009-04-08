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

EXTRA_DIST = \
	guestfs.mli guestfs.ml \
	guestfs_c.c guestfs_c.h guestfs_c_actions.c \
	.depend META.in

SUBDIRS = examples

if HAVE_OCAML

noinst_DATA = mlguestfs.cma mlguestfs.cmxa META

mlguestfs.cma: guestfs_c.o guestfs_c_actions.o guestfs.cmo
	$(OCAMLMKLIB) -o mlguestfs $^ -lguestfs

mlguestfs.cmxa: guestfs_c.o guestfs_c_actions.o guestfs.cmx
	$(OCAMLMKLIB) -o mlguestfs $^ -lguestfs

guestfs_c.o: guestfs_c.c
	$(CC) $(CFLAGS) -I$(OCAMLLIB) -I$(top_builddir)/src -fPIC -Wall -c $<

guestfs_c_actions.o: guestfs_c_actions.c
	$(CC) $(CFLAGS) -I$(OCAMLLIB) -I$(top_builddir)/src -fPIC -Wall -c $<

.mli.cmi:
	$(OCAMLFIND) ocamlc -c $<
.ml.cmo:
	$(OCAMLFIND) ocamlc -c $<
.ml.cmx:
	$(OCAMLFIND) ocamlopt -c $<

depend: .depend

.depend: $(wildcard *.mli) $(wildcard *.ml)
	rm -f .depend
	$(OCAMLFIND) ocamldep $^ > $@

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

endif