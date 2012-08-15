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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Define a force dependency which will always be rebuilt
.PHONY: force

# Automatically build targets defined in generator_built
# generator_built is defined in individual Makefiles
$(generator_built): $(top_builddir)/generator/stamp-generator
$(top_builddir)/generator/stamp-generator: force
	$(MAKE) -C $(top_builddir)/generator stamp-generator

# A symbolic rule to regenerate the appliance
.PHONY: appliance
appliance: force
	$(MAKE) -C $(top_builddir)/appliance
