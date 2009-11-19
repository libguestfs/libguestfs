# libguestfs
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# Define a force dependency which will always be rebuilt
.PHONY: force

# Rebuild rules for common dependencies
$(top_builddir)/src/libguestfs.la: force
	$(MAKE) -C $(top_builddir)/src libguestfs.la

# Automatically build targets defined in generator_built
# generator_built is defined in individual Makefiles
$(generator_built): $(top_builddir)/src/stamp-generator
$(top_builddir)/src/stamp-generator: force
	$(MAKE) -C $(top_builddir)/src stamp-generator
