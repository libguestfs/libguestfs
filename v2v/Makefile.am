# libguestfs virt-v2v tool
# Copyright (C) 2009-2014 Red Hat Inc.
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
	$(SOURCES_MLI) $(SOURCES_ML) $(SOURCES_C) \
	$(TESTS) $(SLOW_TESTS) \
	virt-v2v.pod

CLEANFILES = *~ *.cmi *.cmo *.cmx *.cmxa *.o virt-v2v

SOURCES_MLI = \
	convert_linux.mli \
	convert_windows.mli \
	DOM.mli \
	lib_linux.mli \
	source_libvirt.mli \
	target_libvirt.mli \
	target_local.mli \
	target_RHEV.mli \
	types.mli \
	xml.mli

SOURCES_ML = \
	stringMap.ml \
	types.ml \
	utils.ml \
	xml.ml \
	DOM.ml \
	lib_linux.ml \
	cmdline.ml \
	source_libvirt.ml \
	convert_linux.ml \
	convert_windows.ml \
	target_libvirt.ml \
	target_local.ml \
	target_RHEV.ml \
	v2v.ml

SOURCES_C = \
	$(top_builddir)/fish/progress.c \
	$(top_builddir)/mllib/tty-c.c \
	$(top_builddir)/mllib/progress-c.c \
	$(top_builddir)/mllib/mkdtemp-c.c \
	$(top_builddir)/customize/crypt-c.c \
	utils-c.c \
	xml-c.c

if HAVE_OCAML

bin_PROGRAMS = virt-v2v

virt_v2v_SOURCES = $(SOURCES_C)
virt_v2v_CFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/src \
	-I$(top_srcdir)/fish \
	$(LIBXML2_CFLAGS)

BOBJECTS = \
	$(top_builddir)/mllib/common_gettext.cmo \
	$(top_builddir)/mllib/common_utils.cmo \
	$(top_builddir)/mllib/regedit.cmo \
	$(top_builddir)/mllib/tTY.cmo \
	$(top_builddir)/mllib/progress.cmo \
	$(top_builddir)/mllib/config.cmo \
	$(top_builddir)/mllib/mkdtemp.cmo \
	$(top_builddir)/customize/urandom.cmo \
	$(top_builddir)/customize/random_seed.cmo \
	$(top_builddir)/customize/hostname.cmo \
	$(top_builddir)/customize/timezone.cmo \
	$(top_builddir)/customize/firstboot.cmo \
	$(top_builddir)/customize/perl_edit.cmo \
	$(top_builddir)/customize/crypt.cmo \
	$(top_builddir)/customize/password.cmo \
	$(top_builddir)/customize/customize_run.cmo \
	$(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

# -I $(top_builddir)/src/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/src/.libs \
	-I ../gnulib/lib/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/mllib \
	-I $(top_builddir)/customize
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

OCAMLFLAGS = -g -warn-error CDEFLMPSUVYZX-3

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
BEST    = c
OCAMLLINKFLAGS = mlguestfs.cma -custom
else
OBJECTS = $(XOBJECTS)
BEST    = opt
OCAMLLINKFLAGS = mlguestfs.cmxa
endif

virt_v2v_DEPENDENCIES = $(OBJECTS)
virt_v2v_LINK = \
	./link.sh \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) $(OCAMLLINKFLAGS) \
	  $(OBJECTS) -o $@

.mli.cmi:
	$(OCAMLFIND) ocamlc $(OCAMLFLAGS) $(OCAMLPACKAGES) -c $< -o $@
.ml.cmo:
	$(OCAMLFIND) ocamlc $(OCAMLFLAGS) $(OCAMLPACKAGES) -c $< -o $@
.ml.cmx:
	$(OCAMLFIND) ocamlopt $(OCAMLFLAGS) $(OCAMLPACKAGES) -c $< -o $@

# Data directory.

virttoolsdatadir = $(datadir)/virt-tools

# Manual pages and HTML files for the website.

man_MANS = virt-v2v.1

noinst_DATA = $(top_builddir)/html/virt-v2v.1.html

virt-v2v.1 $(top_builddir)/html/virt-v2v.1.html: stamp-virt-v2v.pod

stamp-virt-v2v.pod: virt-v2v.pod
	$(PODWRAPPER) \
	  --man virt-v2v.1 \
	  --html $(top_builddir)/html/virt-v2v.1.html \
	  --license GPLv2+ \
	  $<
	touch $@

CLEANFILES += stamp-virt-v2v.pod

# Tests.

# The virt-v2v tests here are not meant to be thorough tests of guest
# conversion.  There is a test suite used to test conversion which is
# kept outside libguestfs because it contains lots of proprietary
# unredistributable guests like Windows.
#
# The tests here instead are testing:
#
# - virt-v2v command line arguments
# - virt-v2v reads and writes files to the correct places
# - valgrind & memory leaks
# - any conversion properties that can be tested using just the
#   phony guests (but we don't go out of our way here)
# - that up to date guests don't crash virt-v2v

TESTS_ENVIRONMENT = $(top_builddir)/run --test

if ENABLE_APPLIANCE
TESTS = \
	test-v2v-machine-readable.sh \
	test-v2v-no-copy.sh \
	test-v2v-o-libvirt.sh \
	test-v2v-o-rhev.sh \
	test-v2v-o-rhev-options.sh \
	test-v2v-of-option.sh \
	test-v2v-on-option.sh \
	test-v2v-windows-conversion.sh
endif ENABLE_APPLIANCE

check-valgrind:
	$(MAKE) VG="$(top_builddir)/run @VG@" check

SLOW_TESTS = \
	test-v2v-real-conversions.sh

check-slow: $(real_guests:%=%.img)
	$(MAKE) check TESTS="$(SLOW_TESTS)"

# A selection of real guests that test-v2v-real-conversions.sh will
# try to convert.  This is only used by 'make check-slow'.

real_guests = \
	centos-6 \
	centos-7.0 \
	fedora-20 \
	rhel-5.10 \
	rhel-6.5 \
	rhel-7.0

$(real_guests:%=%.img):
	rm -f $@
	n=`basename $@ .img`;                                            \
	vb="$(top_builddir)/run $(top_builddir)/builder/virt-builder";   \
	if $$vb --help >/dev/null && $$vb --notes $$n >/dev/null; then   \
	  $$vb $$n;                                                      \
	else                                                             \
	  touch $$n.img;                                                 \
	fi

CLEANFILES += $(real_guests:%=%.img)

# Dependencies.
depend: .depend

.depend: $(wildcard $(abs_srcdir)/*.mli) $(wildcard $(abs_srcdir)/*.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep -I ../ocaml -I $(abs_srcdir) -I $(abs_top_builddir)/mllib -I $(abs_top_builddir)/customize $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

endif

DISTCLEANFILES = .depend

.PHONY: depend docs
