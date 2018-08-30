# libguestfs virt-v2v test harness
# Copyright (C) 2009-2019 Red Hat Inc.
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

# Build the V2V_test_harness library, used by external repositories
# that test virt-v2v end-to-end.

include $(top_srcdir)/subdir-rules.mk

EXTRA_DIST = \
	$(SOURCES_MLI) $(SOURCES_ML) \
	virt-v2v-test-harness.pod

SOURCES_MLI = \
	v2v_test_harness.mli

SOURCES_ML = \
	v2v_test_harness.ml

if HAVE_OCAML

# -I $(top_builddir)/lib/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/common/utils/.libs \
	-I $(top_builddir)/lib/.libs \
	-I $(top_builddir)/gnulib/lib/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/common/mlstdutils \
	-I $(top_builddir)/common/mlxml \
	-I $(top_builddir)/common/mltools \
	-I $(top_builddir)/common/mllibvirt \
	-I $(top_builddir)/v2v

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR) -ccopt '$(CFLAGS)'

BOBJECTS = \
	$(SOURCES_ML:.ml=.cmo) \
	$(libv2vth_a_OBJECTS)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

if !HAVE_OCAMLOPT
noinst_DATA = v2v_test_harness.cma META
else
noinst_DATA = v2v_test_harness.cmxa META
endif

v2v_test_harness.cma: $(BOBJECTS)
	$(OCAMLMKLIB) $^ -o v2v_test_harness $(LIBXML2_LIBS)

v2v_test_harness.cmxa: $(XOBJECTS)
	$(OCAMLMKLIB) $^ -o v2v_test_harness $(LIBXML2_LIBS)

# We have to recompile *.c files with -fPIC.  Do that by building an
# uninstalled library.
noinst_LIBRARIES = libv2vth.a

libv2vth_a_CPPFLAGS = \
	-DGUESTFS_PRIVATE=1 \
	-I$(top_builddir) -I$(OCAMLLIB) -I$(top_srcdir)/ocaml \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib

libv2vth_a_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	-fPIC

libv2vth_a_SOURCES = \
	dummy.c

v2v_test_harness.cmi: $(top_builddir)/ocaml/guestfs.cmi

# Run ocamlfind to perform the install.  ocamlfind refuses to install
# the package if it is already installed, so remove the old package
# first.
data_hook_files = META *.so *.a *.cmi $(srcdir)/*.mli
if !HAVE_OCAMLOPT
data_hook_files += *.cmo *.cma
else
data_hook_files += *.cmx *.cmxa
endif

install-data-hook:
	mkdir -p $(DESTDIR)$(OCAMLLIB)
	mkdir -p $(DESTDIR)$(OCAMLLIB)/stublibs
	rm -rf $(DESTDIR)$(OCAMLLIB)/v2v_test_harness
	rm -rf $(DESTDIR)$(OCAMLLIB)/stublibs/dllv2v_test_harness.so*
	$(OCAMLFIND) install \
	  -ldconf ignore -destdir $(DESTDIR)$(OCAMLLIB) \
	  v2v_test_harness \
	  $(data_hook_files)
	rm $(DESTDIR)$(OCAMLLIB)/v2v_test_harness/libv2vth.a

# Manual pages and HTML files for the website.

man_MANS = virt-v2v-test-harness.1

noinst_DATA += $(top_builddir)/website/virt-v2v-test-harness.1.html

virt-v2v-test-harness.1 $(top_builddir)/website/virt-v2v-test-harness.1.html: stamp-virt-v2v-test-harness.pod

stamp-virt-v2v-test-harness.pod: virt-v2v-test-harness.pod
	$(PODWRAPPER) \
	  --man virt-v2v-test-harness.1 \
	  --html $(top_builddir)/website/virt-v2v-test-harness.1.html \
	  --license LGPLv2+ \
	  --warning safe \
	  $<
	touch $@

# Dependencies.
.depend: $(srcdir)/*.mli $(srcdir)/*.ml
	$(top_builddir)/ocaml-dep.sh -I .. $^
-include .depend

endif

.PHONY: docs
