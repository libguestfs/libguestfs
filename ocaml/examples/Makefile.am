# libguestfs OCaml examples
# Copyright (C) 2010-2023 Red Hat Inc.
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

EXTRA_DIST = \
	LICENSE \
	create_disk.ml \
	debug_logging.ml \
	inspect_vm.ml \
	guestfs-ocaml.pod

CLEANFILES += \
	$(noinst_SCRIPTS)

man_MANS = guestfs-ocaml.3
noinst_DATA = $(top_builddir)/website/guestfs-ocaml.3.html

guestfs-ocaml.3 $(top_builddir)/website/guestfs-ocaml.3.html: stamp-guestfs-ocaml.pod

stamp-guestfs-ocaml.pod: guestfs-ocaml.pod create_disk.ml inspect_vm.ml
	$(PODWRAPPER) \
	  --section 3 \
	  --man guestfs-ocaml.3 \
	  --html $(top_builddir)/website/guestfs-ocaml.3.html \
	  --verbatim $(srcdir)/create_disk.ml:@CREATE_DISK@ \
	  --verbatim $(srcdir)/inspect_vm.ml:@INSPECT_VM@ \
	  --verbatim $(srcdir)/debug_logging.ml:@DEBUG_LOGGING@ \
	  --license examples \
	  $<
	touch $@

if HAVE_OCAML

noinst_SCRIPTS = create_disk debug_logging inspect_vm

OCAMLFINDFLAGS = -cclib -L$(top_builddir)/lib/.libs

if HAVE_OCAMLOPT
create_disk: create_disk.ml
	$(OCAMLFIND) ocamlopt $(OCAMLFINDFLAGS) -package unix -linkpkg \
          -warn-error A -I .. mlguestfs.cmxa $< -o $@

debug_logging: debug_logging.ml
	$(OCAMLFIND) ocamlopt $(OCAMLFINDFLAGS) -package unix -linkpkg \
          -warn-error A -I .. mlguestfs.cmxa $< -o $@

inspect_vm: inspect_vm.ml
	$(OCAMLFIND) ocamlopt $(OCAMLFINDFLAGS) -package unix -linkpkg \
          -warn-error A -I .. mlguestfs.cmxa $< -o $@
else
create_disk: create_disk.ml
	$(OCAMLFIND) ocamlc $(OCAMLFINDFLAGS) -package unix -linkpkg \
          -warn-error A -I .. mlguestfs.cma -custom $< -o $@

debug_logging: debug_logging.ml
	$(OCAMLFIND) ocamlc $(OCAMLFINDFLAGS) -package unix -linkpkg \
          -warn-error A -I .. mlguestfs.cma -custom $< -o $@

inspect_vm: inspect_vm.ml
	$(OCAMLFIND) ocamlc $(OCAMLFINDFLAGS) -package unix -linkpkg \
          -warn-error A -I .. mlguestfs.cma -custom $< -o $@
endif

endif
