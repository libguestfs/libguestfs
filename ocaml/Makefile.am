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

if HAVE_OCAML

EXTRA_DIST = \
	guestfs.mli guestfs.ml \
	guestfs_internal.ml \
	guestfs_c.c guestfs_c.h guestfs_c_actions.c \
	.depend META.in

noinst_DATA = mlguestfs.cma mlguestfs.cmxa META

mlguestfs.cma: guestfs_c.o guestfs_c_actions.o guestfs_internal.cmo guestfs.cmo
	$(OCAMLMKLIB) -o mlguestfs $^ -lguestfs

mlguestfs.cmxa: guestfs_c.o guestfs_c_actions.o guestfs_internal.cmx guestfs.cmx
	$(OCAMLMKLIB) -o mlguestfs $^ -lguestfs

guestfs_c.o: guestfs_c.c
	$(CC) $(CFLAGS) -I$(OCAMLLIB) -c $<

guestfs_c_actions.o: guestfs_c_actions.c
	$(CC) $(CFLAGS) -I$(OCAMLLIB) -c $<

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
	$(OCAMLFIND) install -destdir $(DESTDIR) guestfs \
	  META *.so *.a *.cma *.cmx *.cmxa *.cmi *.mli

endif