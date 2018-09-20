# Wrapper around ocaml-gettext.
# Copyright (C) 2009-2018 Red Hat Inc.
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
	$(SOURCES_ML)

SOURCES_MLI = \
	common_gettext.mli

SOURCES_ML = \
	common_gettext.ml

if HAVE_OCAML

# We pretend that we're building a C library.  automake handles the
# compilation of the C sources for us.  At the end we take the C
# objects and OCaml objects and link them into the OCaml library.
# This C library is never used.

noinst_LIBRARIES = libmlgettext.a

if !HAVE_OCAMLOPT
MLGETTEXT_CMA = mlgettext.cma
else
MLGETTEXT_CMA = mlgettext.cmxa
endif

noinst_DATA = $(MLGETTEXT_CMA)

libmlgettext_a_SOURCES = dummy.c
libmlgettext_a_CPPFLAGS = \
	-I. \
	-I$(top_builddir)
libmlgettext_a_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	-fPIC

BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

OCAMLPACKAGES = -I $(builddir)
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR) -ccopt '$(CFLAGS)'

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif

libmlgettext_a_DEPENDENCIES = $(OBJECTS)

mlgettext.cma: $(BOBJECTS)
	$(OCAMLFIND) ocamlc $(OCAMLPACKAGES) -a $^ -o $@

if HAVE_OCAMLOPT
mlgettext.cmxa: $(XOBJECTS)
	$(OCAMLFIND) ocamlopt $(OCAMLPACKAGES) -a $^ -o $@
endif

# Dependencies.
.depend: $(srcdir)/*.mli $(srcdir)/*.ml
	$(top_builddir)/ocaml-dep.sh $^
-include .depend

endif
