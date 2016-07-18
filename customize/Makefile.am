# virt-customize
# Copyright (C) 2014-2016 Red Hat Inc.
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
	$(generator_built) \
	$(SOURCES_MLI) $(SOURCES_ML) $(SOURCES_C) \
	customize_main.ml \
	test-virt-customize.sh \
	virt-customize.pod

CLEANFILES = \
	*~ *.annot *.cmi *.cmo *.cmx *.cmxa *.o dll*.so \
	stamp-virt-customize.pod \
	virt-customize virt-customize.1

generator_built = \
	customize_cmdline.mli \
	customize_cmdline.ml \
	customize-options.pod \
	customize-synopsis.pod

SOURCES_MLI = \
	crypt.mli \
	customize_cmdline.mli \
	customize_run.mli \
	firstboot.mli \
	hostname.mli \
	password.mli \
	perl_edit.mli \
	random_seed.mli \
	SELinux_relabel.mli \
	ssh_key.mli \
	subscription_manager.mli \
	timezone.mli \
	urandom.mli

# This list must be in dependency order.
SOURCES_ML = \
	customize_utils.ml \
	crypt.ml \
	firstboot.ml \
	hostname.ml \
	urandom.ml \
	password.ml \
	perl_edit.ml \
	random_seed.ml \
	SELinux_relabel.ml \
	ssh_key.ml \
	subscription_manager.ml \
	timezone.ml \
	customize_cmdline.ml \
	customize_run.ml

SOURCES_C = \
	../fish/file-edit.c \
	../fish/file-edit.h \
	crypt-c.c \
	perl_edit-c.c

if HAVE_OCAML

# Build the virt-customize objects into a library, since these are
# reused by virt-builder and virt-sysprep.  We pretend we are building
# a C library.  automake handles the compilation of C sources for us.
# At the end we take the C objects and OCaml objects and link them
# into the OCaml library.  This C library is never used.
noinst_LIBRARIES = libcustomize.a

if !HAVE_OCAMLOPT
CUSTOMIZE_CMA = customize.cma
else
CUSTOMIZE_CMA = customize.cmxa
endif

noinst_DATA = $(CUSTOMIZE_CMA)

libcustomize_a_SOURCES = $(SOURCES_C)
libcustomize_a_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/src \
	-I$(top_srcdir)/fish
libcustomize_a_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBVIRT_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	-fPIC

BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif

# -I $(top_builddir)/src/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/src/.libs \
	-I $(top_builddir)/gnulib/lib/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/mllib \
	-I $(builddir)
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

libcustomize_a_DEPENDENCIES = $(OBJECTS)

$(CUSTOMIZE_CMA): $(OBJECTS) libcustomize.a
	$(OCAMLFIND) mklib -g $(OCAMLPACKAGES) \
	    $(OBJECTS) $(libcustomize_a_OBJECTS) -o customize

# Build the virt-customize program.
bin_PROGRAMS = virt-customize

virt_customize_SOURCES = dummy.c

CUSTOMIZE_BOBJECTS = customize_main.cmo
CUSTOMIZE_XOBJECTS = $(CUSTOMIZE_BOBJECTS:.cmo=.cmx)

if !HAVE_OCAMLOPT
CUSTOMIZE_THEOBJECTS = $(CUSTOMIZE_BOBJECTS)
BEST    = c
OCAMLLINKFLAGS = mlguestfs.cma mllib.cma customize.cma -custom
else
CUSTOMIZE_THEOBJECTS = $(CUSTOMIZE_XOBJECTS)
BEST    = opt
OCAMLLINKFLAGS = mlguestfs.cmxa mllib.cmxa customize.cmxa
endif

OCAMLCLIBS = \
	-lutils \
	$(LIBTINFO_LIBS) \
	$(LIBCRYPT_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LIBXML2_LIBS) \
	$(LIBINTL) \
	-lgnu

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR)

virt_customize_DEPENDENCIES = \
	$(top_srcdir)/ocaml-link.sh \
	$(CUSTOMIZE_THEOBJECTS) \
	$(CUSTOMIZE_CMA)
virt_customize_LINK = \
	$(top_srcdir)/ocaml-link.sh -cclib '$(OCAMLCLIBS)' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) $(OCAMLLINKFLAGS) \
	  $(CUSTOMIZE_THEOBJECTS) -o $@

# Manual pages and HTML files for the website.
man_MANS = virt-customize.1
noinst_DATA += $(top_builddir)/website/virt-customize.1.html

virt-customize.1 $(top_builddir)/website/virt-customize.1.html: stamp-virt-customize.pod

stamp-virt-customize.pod: virt-customize.pod $(top_srcdir)/customize/customize-synopsis.pod $(top_srcdir)/customize/customize-options.pod
	$(PODWRAPPER) \
	  --man virt-customize.1 \
	  --html $(top_builddir)/website/virt-customize.1.html \
	  --insert $(top_srcdir)/customize/customize-synopsis.pod:__CUSTOMIZE_SYNOPSIS__ \
	  --insert $(top_srcdir)/customize/customize-options.pod:__CUSTOMIZE_OPTIONS__ \
	  --license GPLv2+ \
	  --warning general \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

if ENABLE_APPLIANCE
TESTS = test-virt-customize.sh
endif

check-valgrind:
	$(MAKE) VG="$(top_builddir)/run @VG@" check

# Dependencies.
depend: .depend

.depend: $(wildcard $(abs_srcdir)/*.mli) $(wildcard $(abs_srcdir)/*.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep -I ../ocaml -I $(abs_srcdir) -I $(abs_top_builddir)/mllib $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

endif

DISTCLEANFILES = .depend

.PHONY: depend docs
