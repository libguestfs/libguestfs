# libguestfs OCaml tools common code
# Copyright (C) 2018 Red Hat Inc.
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
	$(SOURCES_MLI) \
	$(SOURCES_ML) \
	generator.pl \
	libvirt_c_epilogue.c \
	libvirt_c_oneoffs.c \
	libvirt_c_prologue.c \
	libvirt.README

SOURCES_MLI = \
	libvirt.mli

SOURCES_ML = \
	libvirt.ml

SOURCES_C = \
	libvirt_c.c

# Automatically generate the C code from a Perl script 'generator.pl'.
libvirt_c.c: $(srcdir)/generator.pl
	$(PERL) -w $<

CLEANFILES += \
	libvirt_c.c

# We pretend that we're building a C library.  automake handles the
# compilation of the C sources for us.  At the end we take the C
# objects and OCaml objects and link them into the OCaml library.
# This C library is never used.

noinst_LIBRARIES = libmllibvirt.a

if !HAVE_OCAMLOPT
MLLIBVIRT_CMA = mllibvirt.cma
else
MLLIBVIRT_CMA = mllibvirt.cmxa
endif

noinst_DATA = $(MLLIBVIRT_CMA)

libmllibvirt_a_SOURCES = $(SOURCES_C)
libmllibvirt_a_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(shell $(OCAMLC) -where)
libmllibvirt_a_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBVIRT_CFLAGS) \
	-fPIC

BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

OCAMLPACKAGES =
OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR)

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif

libmllibvirt_a_DEPENDENCIES = $(OBJECTS)

$(MLLIBVIRT_CMA): $(OBJECTS) libmllibvirt.a
	$(OCAMLFIND) mklib $(OCAMLPACKAGES) \
	    $(OBJECTS) $(libmllibvirt_a_OBJECTS) -cclib -lvirt -o mllibvirt

# Dependencies.
depend: .depend

.depend: $(wildcard $(abs_srcdir)/*.mli) $(wildcard $(abs_srcdir)/*.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep -I ../../ocaml -I $(abs_srcdir) $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

.PHONY: depend docs
