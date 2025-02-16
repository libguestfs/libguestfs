# libguestfs
# Copyright (C) 2009-2025 Red Hat Inc.
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

# subdir-rules.mk should be included in every *subdirectory* Makefile.am.

include $(top_srcdir)/common-rules.mk

# Individual Makefile.am's should define generator_built if that
# subdirectory contains any files which are built by the generator.
# Set generator_built to the list of those files.

$(generator_built): $(top_builddir)/generator/stamp-generator

$(top_builddir)/generator/stamp-generator: $(top_builddir)/generator/generator
	@if test -f $(top_builddir)/generator/Makefile; then \
	  $(MAKE) -C $(top_builddir)/generator stamp-generator; \
	else \
	  echo "warning: Run 'make' at the top level to build $(generator_built)"; \
	fi

# If this file doesn't exist, just print a warning and continue.
# During 'make distclean' we can end up deleting this file.
$(top_builddir)/generator/generator:
	@if test -f $(top_builddir)/generator/Makefile; then \
	  $(MAKE) -C $(top_builddir)/generator generator; \
	else \
	  echo "warning: Run 'make' at the top level to build $@"; \
	fi

LOG_DRIVER = env $(SHELL) $(top_srcdir)/build-aux/guestfs-test-driver

# Rules for building OCaml objects.
# See also:
# guestfs-hacking(1) section "HOW OCAML PROGRAMS ARE COMPILED AND LINKED"

if !HAVE_OCAMLOPT
MLARCHIVE = cma
LINK_CUSTOM_OCAMLC_ONLY = -custom
BEST = c
else
MLARCHIVE = cmxa
BEST = opt
endif

# custom silent rules
guestfs_am_v_ocamlc = $(guestfs_am_v_ocamlc_@AM_V@)
guestfs_am_v_ocamlc_ = $(guestfs_am_v_ocamlc_@AM_DEFAULT_V@)
guestfs_am_v_ocamlc_0 = @echo "  OCAMLC  " $@;
guestfs_am_v_ocamlcmi= $(guestfs_am_v_ocamlcmi_@AM_V@)
guestfs_am_v_ocamlcmi_ = $(guestfs_am_v_ocamlcmi_@AM_DEFAULT_V@)
guestfs_am_v_ocamlcmi_0 = @echo "  OCAMLCMI" $@;
guestfs_am_v_ocamlopt = $(guestfs_am_v_ocamlopt_@AM_V@)
guestfs_am_v_ocamlopt_ = $(guestfs_am_v_ocamlopt_@AM_DEFAULT_V@)
guestfs_am_v_ocamlopt_0 = @echo "  OCAMLOPT" $@;
guestfs_am_v_javac = $(guestfs_am_v_javac_@AM_V@)
guestfs_am_v_javac_ = $(guestfs_am_v_javac_@AM_DEFAULT_V@)
guestfs_am_v_javac_0 = @echo "  JAVAC   " $@;
guestfs_am_v_erlc = $(guestfs_am_v_erlc_@AM_V@)
guestfs_am_v_erlc_ = $(guestfs_am_v_erlc_@AM_DEFAULT_V@)
guestfs_am_v_erlc_0 = @echo "  ERLC    " $@;
guestfs_am_v_podwrapper = $(guestfs_am_v_podwrapper_@AM_V@)
guestfs_am_v_podwrapper_ = $(guestfs_am_v_podwrapper_@AM_DEFAULT_V@)
guestfs_am_v_podwrapper_0 = @echo "  POD     " $@;
guestfs_am_v_jar = $(guestfs_am_v_jar_@AM_V@)
guestfs_am_v_jar_ = $(guestfs_am_v_jar_@AM_DEFAULT_V@)
guestfs_am_v_jar_0 = @echo "  JAR     " $@;
guestfs_am_v_po4a_translate = $(guestfs_am_v_po4a_translate_@AM_V@)
guestfs_am_v_po4a_translate_ = $(guestfs_am_v_po4a_translate_@AM_DEFAULT_V@)
guestfs_am_v_po4a_translate_0 = @echo "  PO4A-T  " $@;

%.cmi: %.mli
	$(guestfs_am_v_ocamlcmi)$(OCAMLFIND) ocamlc $(OCAMLFLAGS) $(OCAMLPACKAGES) -c $< -o $@
%.cmo: %.ml
	$(guestfs_am_v_ocamlc)$(OCAMLFIND) ocamlc $(OCAMLFLAGS) $(OCAMLPACKAGES) -c $< -o $@
if HAVE_OCAMLOPT
%.cmx: %.ml
	$(guestfs_am_v_ocamlopt)$(OCAMLFIND) ocamlopt $(OCAMLFLAGS) $(OCAMLPACKAGES) -c $< -o $@
endif
