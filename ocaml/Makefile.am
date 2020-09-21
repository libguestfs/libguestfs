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
	guestfs-c-actions.c \
	guestfs-c-errnos.c \
	$(srcdir)/bindtests.ml

EXTRA_DIST = \
	$(generator_built) \
	guestfs-c.c guestfs-c.h \
	html/.gitignore \
	META.in \
	run-bindtests \
	t/*.ml

CLEANFILES += *.so
CLEANFILES += t/*.annot t/*.cmi t/*.cmo t/*.cmx t/*.o t/*.a t/*.so

if HAVE_OCAML

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR) -ccopt '$(CFLAGS)'

noinst_DATA = mlguestfs.cma META
if HAVE_OCAMLOPT
noinst_DATA +=  mlguestfs.cmxa
endif

# Build the C part into a library, so that automake handles the C
# compilation step for us.  Note that we don't directly use this
# library; we link with the object files that it generates.
noinst_LIBRARIES = libguestfsocaml.a

# Note that both calls to ocamlmklib below will create
# 'libmlguestfs.a' and if run at the same time, they will stomp on or
# corrupt each others copy.  Hence we have to serialize the calls.

CLEANFILES += stamp-mlguestfs

mlguestfs.cma mlguestfs.cmxa: stamp-mlguestfs

guestfs_cmm = guestfs.cmo
if HAVE_OCAMLOPT
guestfs_cmm += guestfs.cmx
endif

stamp-mlguestfs: libguestfsocaml.a $(guestfs_cmm)
	$(OCAMLMKLIB) -o mlguestfs \
	  -ldopt '$(LDFLAGS)' \
	  $(libguestfsocaml_a_OBJECTS) guestfs.cmo \
	  $(LTLIBINTL) \
	  -L../lib/.libs -lguestfs
if HAVE_OCAMLOPT
	$(OCAMLMKLIB) -o mlguestfs \
	  -ldopt '$(LDFLAGS)' \
	  $(libguestfsocaml_a_OBJECTS) guestfs.cmx \
	  $(LTLIBINTL) \
	  -L../lib/.libs -lguestfs
endif
	touch $@

libguestfsocaml_a_CPPFLAGS = \
	-DCAML_NAME_SPACE \
	-DGUESTFS_PRIVATE=1 \
	-I$(top_builddir) -I$(OCAMLLIB) -I$(top_srcdir)/ocaml \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/gnulib/lib -I../gnulib/lib

libguestfsocaml_a_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	-fPIC

libguestfsocaml_a_SOURCES = \
	guestfs-c.c \
	guestfs-c-actions.c \
	guestfs-c-errnos.c \
	../common/utils/cleanups.c \
	../common/utils/stringlists-utils.c

if HAVE_OCAMLDOC

noinst_DATA += html/index.html

html/index.html: $(srcdir)/guestfs.mli $(srcdir)/guestfs.ml
	-$(OCAMLFIND) ocamldoc -d html -html $^

clean-local:
	rm -rf html/*

endif

TESTS_ENVIRONMENT = $(top_builddir)/run --test
LOG_COMPILER = $(VG)

test_progs_bc = \
	t/guestfs_010_load.bc \
	t/guestfs_020_create.bc \
	t/guestfs_030_create_flags.bc \
	t/guestfs_040_create_multiple.bc \
	t/guestfs_050_handle_properties.bc \
	t/guestfs_060_explicit_close.bc \
	t/guestfs_065_implicit_close.bc \
	t/guestfs_070_optargs.bc \
	t/guestfs_080_version.bc \
	t/guestfs_410_close_event.bc \
	t/guestfs_420_log_messages.bc

test_progs_opt = \
	t/guestfs_010_load.opt \
	t/guestfs_020_create.opt \
	t/guestfs_030_create_flags.opt \
	t/guestfs_040_create_multiple.opt \
	t/guestfs_050_handle_properties.opt \
	t/guestfs_060_explicit_close.opt \
	t/guestfs_065_implicit_close.opt \
	t/guestfs_070_optargs.opt \
	t/guestfs_080_version.opt \
	t/guestfs_410_close_event.opt \
	t/guestfs_420_log_messages.opt

if ENABLE_APPLIANCE
test_progs_bc += \
	t/guestfs_100_launch.bc \
	t/guestfs_430_progress_messages.bc
test_progs_opt += \
	t/guestfs_100_launch.opt \
	t/guestfs_430_progress_messages.opt
endif

test_progs_all = $(test_progs_bc)
if HAVE_OCAMLOPT
test_progs_all += $(test_progs_opt)
endif

TESTS = run-bindtests $(test_progs_all)

check_DATA = bindtests.bc $(test_progs_all)
if HAVE_OCAMLOPT
check_DATA += bindtests.opt
endif

%.bc: %.cmo mlguestfs.cma
	$(guestfs_am_v_ocamlc)$(top_builddir)/libtool -dlopen $(top_builddir)/lib/.libs/libguestfs.la --mode=execute \
	$(OCAMLFIND) ocamlc $(OCAMLFLAGS) -I . -package unix -linkpkg mlguestfs.cma $< -o $@

if HAVE_OCAMLOPT
%.opt: %.cmx mlguestfs.cmxa
	$(guestfs_am_v_ocamlopt)$(OCAMLFIND) ocamlopt $(OCAMLFLAGS) -cclib -L$(top_builddir)/lib/.libs -I . -package unix -linkpkg mlguestfs.cmxa $< -o $@
endif

check-valgrind:
	$(MAKE) VG="@VG@" TESTS="$(test_progs_all)" check

# Dependencies.
.depend: $(srcdir)/*.mli $(srcdir)/*.ml
	$(top_builddir)/ocaml-dep.sh $^
-include .depend

# Run ocamlfind to perform the install.  ocamlfind refuses to install
# the package if it is already installed, so remove the old package
# first.
data_hook_files = META *.so *.a *.cma *.cmi $(srcdir)/*.mli
if HAVE_OCAMLOPT
data_hook_files += *.cmx *.cmxa
endif

install-data-hook:
	mkdir -p $(DESTDIR)$(OCAMLLIB)
	mkdir -p $(DESTDIR)$(OCAMLLIB)/stublibs
	rm -rf $(DESTDIR)$(OCAMLLIB)/guestfs
	rm -rf $(DESTDIR)$(OCAMLLIB)/stublibs/dllmlguestfs.so*
	$(OCAMLFIND) install \
	  -ldconf ignore -destdir $(DESTDIR)$(OCAMLLIB) \
	  guestfs \
	  $(data_hook_files)
	rm -f $(DESTDIR)$(OCAMLLIB)/guestfs/bindtests.*
	rm $(DESTDIR)$(OCAMLLIB)/guestfs/libguestfsocaml.a

CLEANFILES += $(noinst_DATA) $(check_DATA)

# This "tricks" ocamlfind into allowing us to compile other OCaml
# programs against a locally compiled copy of the libguestfs sources.
# ocamlfind needs to see a directory called ‘guestfs’ which contains
# ‘META’.  The current directory is called ‘ocaml’, but if we make
# this symlink then we can create the required directory structure.
#
# Note if you just want to use this, make sure you use
# ‘../libguestfs/run make’ in your other program and everything should
# just work.
CLEANFILES += guestfs

all-local: guestfs

guestfs:
	rm -f $@
	$(LN_S) . $@

endif HAVE_OCAML
