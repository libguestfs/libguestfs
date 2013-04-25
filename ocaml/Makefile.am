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

# Old RHEL 5 autoconf doesn't have builddir.
builddir ?= .

# Old RHEL 5 autoconf doesn't have abs_srcdir.
abs_srcdir ?= $(shell cd $(top_srcdir)/ocaml && pwd)

include $(top_srcdir)/subdir-rules.mk

generator_built = \
	guestfs.mli \
	guestfs.ml \
	guestfs-c-actions.c \
	$(srcdir)/bindtests.ml

EXTRA_DIST = \
	$(generator_built) \
	.depend \
	guestfs-c.c guestfs-c.h \
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

# Note that both calls to ocamlmklib below will create
# 'libmlguestfs.a' and if run at the same time, they will stomp on or
# corrupt each others copy.  Hence we have to serialize the calls.

CLEANFILES += stamp-mlguestfs

mlguestfs.cma mlguestfs.cmxa: stamp-mlguestfs

stamp-mlguestfs: libguestfsocaml.a guestfs.cmo guestfs.cmx
	$(OCAMLMKLIB) -o mlguestfs \
	  $(libguestfsocaml_a_OBJECTS) guestfs.cmo \
	  -L$(top_builddir)/src/.libs -lguestfs
	$(OCAMLMKLIB) -o mlguestfs \
	  $(libguestfsocaml_a_OBJECTS) guestfs.cmx \
	  -L$(top_builddir)/src/.libs -lguestfs
	touch $@

libguestfsocaml_a_CPPFLAGS = \
	-DGUESTFS_PRIVATE=1 \
	-I$(top_builddir) -I$(OCAMLLIB) -I$(top_srcdir)/ocaml \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/gnulib/lib -I../gnulib/lib

libguestfsocaml_a_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	-fPIC

libguestfsocaml_a_SOURCES = \
	guestfs-c.c \
	guestfs-c-actions.c \
	../src/utils.c

if HAVE_OCAMLDOC

noinst_DATA += html/index.html

html/index.html: $(srcdir)/guestfs*.mli $(srcdir)/guestfs*.ml
	-$(OCAMLDOC) -d html -html $^
endif

TESTS_ENVIRONMENT = $(top_builddir)/run --test $(VG)

test_progs = \
	t/guestfs_005_load \
	t/guestfs_080_optargs \
	t/guestfs_400_events

if ENABLE_APPLIANCE
test_progs += \
	t/guestfs_010_basic \
	t/guestfs_070_threads \
	t/guestfs_400_progress \
	t/guestfs_500_mount_local
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
	$(top_builddir)/libtool -dlopen $(top_builddir)/src/.libs/libguestfs.la --mode=execute \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

bindtests.opt: bindtests.cmx mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_005_load.bc: t/guestfs_005_load.cmo mlguestfs.cma
	$(top_builddir)/libtool -dlopen $(top_builddir)/src/.libs/libguestfs.la --mode=execute \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

t/guestfs_005_load.opt: t/guestfs_005_load.cmx mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_010_basic.bc: t/guestfs_010_basic.cmo mlguestfs.cma
	$(top_builddir)/libtool -dlopen $(top_builddir)/src/.libs/libguestfs.la --mode=execute \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

t/guestfs_010_basic.opt: t/guestfs_010_basic.cmx mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_070_threads.bc: t/guestfs_070_threads.cmo mlguestfs.cma
	$(top_builddir)/libtool -dlopen $(top_builddir)/src/.libs/libguestfs.la --mode=execute \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix,threads -thread -linkpkg mlguestfs.cma $< -o $@

t/guestfs_070_threads.opt: t/guestfs_070_threads.cmx mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix,threads -thread -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_080_optargs.bc: t/guestfs_080_optargs.cmo mlguestfs.cma
	$(top_builddir)/libtool -dlopen $(top_builddir)/src/.libs/libguestfs.la --mode=execute \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

t/guestfs_080_optargs.opt: t/guestfs_080_optargs.cmx mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_400_events.bc: t/guestfs_400_events.cmo mlguestfs.cma
	$(top_builddir)/libtool -dlopen $(top_builddir)/src/.libs/libguestfs.la --mode=execute \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

t/guestfs_400_events.opt: t/guestfs_400_events.cmx mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_400_progress.bc: t/guestfs_400_progress.cmo mlguestfs.cma
	$(top_builddir)/libtool -dlopen $(top_builddir)/src/.libs/libguestfs.la --mode=execute \
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

t/guestfs_400_progress.opt: t/guestfs_400_progress.cmx mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

t/guestfs_500_mount_local.bc: t/guestfs_500_mount_local.cmo mlguestfs.cma
	$(top_builddir)/libtool -dlopen $(top_builddir)/src/.libs/libguestfs.la --mode=execute \
	$(OCAMLFIND) ocamlc -custom $(OCAMLCFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

t/guestfs_500_mount_local.opt: t/guestfs_500_mount_local.cmx mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -cclib -L$(top_builddir)/src/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@

# Explicit rules for these tests which require 'threads' package.
t/guestfs_070_threads.cmo: t/guestfs_070_threads.ml mlguestfs.cma
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -package unix,threads -thread -linkpkg -c $< -o $@

t/guestfs_070_threads.cmx: t/guestfs_070_threads.ml mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -package unix,threads -thread -linkpkg -c $< -o $@

check-valgrind:
	$(MAKE) VG="$(top_builddir)/run @VG@" check

# Dependencies.
%.cmi: %.mli
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -package unix -c $< -o $@
guestfs.cmo: guestfs.ml
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -package unix -c $< -o $@
%.cmo: %.ml mlguestfs.cma
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -package unix -c $< -o $@
guestfs.cmx: guestfs.ml
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -package unix -c $< -o $@
%.cmx: %.ml mlguestfs.cmxa
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -package unix -c $< -o $@

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
