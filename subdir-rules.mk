# libguestfs
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
