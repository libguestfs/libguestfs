# libguestfs virt-builder tool
# Copyright (C) 2013 Red Hat Inc.
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
	$(SOURCES) \
	virt-builder.pod \
	test-virt-builder.sh \
	test-virt-builder-list.sh

CLEANFILES = *~ *.cmi *.cmo *.cmx *.cmxa *.o virt-builder

# Alphabetical order.
SOURCES = \
	builder.ml \
	cmdline.ml \
	downloader.mli \
	downloader.ml \
	get_kernel.mli \
	get_kernel.ml \
	index_parser.mli \
	index_parser.ml \
	list_entries.mli \
	list_entries.ml \
	sigchecker.mli \
	sigchecker.ml

if HAVE_OCAML

# Note this list must be in dependency order.
OBJECTS = \
	$(top_builddir)/mllib/libdir.cmx \
	$(top_builddir)/mllib/common_gettext.cmx \
	$(top_builddir)/mllib/common_utils.cmx \
	$(top_builddir)/mllib/urandom.cmx \
	$(top_builddir)/mllib/random_seed.cmx \
	$(top_builddir)/mllib/hostname.cmx \
	$(top_builddir)/mllib/firstboot.cmx \
	$(top_builddir)/mllib/perl_edit.cmx \
	$(top_builddir)/mllib/crypt-c.o \
	$(top_builddir)/mllib/crypt.cmx \
	$(top_builddir)/mllib/fsync-c.o \
	$(top_builddir)/mllib/fsync.cmx \
	$(top_builddir)/mllib/password.cmx \
	$(top_builddir)/mllib/config.cmx \
	get_kernel.cmx \
	downloader.cmx \
	sigchecker.cmx \
	index_parser.cmx \
	list_entries.cmx \
	cmdline.cmx \
	builder.cmx

bin_SCRIPTS = virt-builder

# -I $(top_builddir)/src/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/src/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/mllib
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

OCAMLCFLAGS = -g -warn-error CDEFLMPSUVYZX-3 $(OCAMLPACKAGES)
OCAMLOPTFLAGS = $(OCAMLCFLAGS)

virt-builder: $(OBJECTS)
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) \
	  mlguestfs.cmxa -linkpkg $^ \
	  -cclib '-lncurses -lcrypt' \
	  $(OCAML_GCOV_LDFLAGS) \
	  -o $@

.mli.cmi:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
.ml.cmo:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
.ml.cmx:
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -c $< -o $@

# automake will decide we don't need C support in this file.  Really
# we do, so we have to provide it ourselves.

DEFAULT_INCLUDES = \
	-I. \
	-I$(top_builddir) \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/src \
	-I$(top_srcdir)/fish

.c.o:
	$(CC) $(CFLAGS) $(PROF_CFLAGS) $(DEFAULT_INCLUDES) -c $< -o $@

# Manual pages and HTML files for the website.

man_MANS = virt-builder.1

noinst_DATA = $(top_builddir)/html/virt-builder.1.html

virt-builder.1 $(top_builddir)/html/virt-builder.1.html: stamp-virt-builder.pod

stamp-virt-builder.pod: virt-builder.pod
	$(PODWRAPPER) \
	  --man virt-builder.1 \
	  --html $(top_builddir)/html/virt-builder.1.html \
	  --license GPLv2+ \
	  $<
	touch $@

CLEANFILES += stamp-virt-builder.pod

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

all_disk_images := debian.xz fedora.xz ubuntu.xz windows.xz
disk_images := $(shell for f in $(all_disk_images); do b=`basename $$f .xz`; if [ -f "../tests/guests/$$b.img" ]; then echo $$f; fi; done)

CLEANFILES += $(all_disk_images)

check_DATA = $(disk_images)

%.xz: ../tests/guests/%.img
	xz --best --block-size=16777216 -c $< > $@

TESTS = test-virt-builder-list.sh

if ENABLE_APPLIANCE
TESTS += test-virt-builder.sh
endif ENABLE_APPLIANCE

check-valgrind:
	$(MAKE) VG="$(top_builddir)/run @VG@" check

# Dependencies.
depend: .depend

.depend: $(wildcard $(abs_srcdir)/*.mli) $(wildcard $(abs_srcdir)/*.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep -I ../ocaml -I $(abs_srcdir) -I $(top_srcdir)/mllib $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

endif

DISTCLEANFILES = .depend

.PHONY: depend docs
