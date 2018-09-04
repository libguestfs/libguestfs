# libguestfs
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

# 'common-rules.mk' should be included in every Makefile.am.
# cf. 'subdir-rules.mk'

-include $(top_builddir)/localenv

# Files that should universally be removed by 'make clean'.  Note if
# there is any case in any subdirectory where a file should not be
# removed by 'make clean', it should not be listed here!

# Editor backup files
CLEANFILES = *~ *.bak

# Patch original and reject files.
CLEANFILES += *.orig *.rej

# OCaml intermediate and generated files.
CLEANFILES += *.cmi *.cmo *.cma *.cmx *.cmxa dll*.so *.a

# OCaml -annot files (used for displaying types in some IDEs).
CLEANFILES += *.annot

# OCaml oUnit generated files.
CLEANFILES += oUnit-*.cache oUnit-*.log

# Manual pages - these are all generated from *.pod, so the
# pages themselves should all be removed by 'make clean'.
CLEANFILES += *.1 *.3 *.5 *.8

# Stamp files used when generating man pages.
CLEANFILES += stamp-*.pod

# Bindtests temporary files used in many language bindings.
CLEANFILES += bindtests.tmp

# Files that should be universally removed by 'make distclean'.
DISTCLEANFILES = .depend stamp-*

# Special suffixes used by OCaml.
SUFFIXES = .cmo .cmi .cmx .ml .mli .mll .mly

# Special suffixes used by PO files.
SUFFIXES += .po .gmo
