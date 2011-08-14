# libguestfs Python examples
# Copyright (C) 2010 Red Hat Inc.
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

EXTRA_DIST = \
	LICENSE \
	create_disk.py \
	inspect_vm.py \
	guestfs-python.pod

CLEANFILES = *.pyc *.pyo stamp-guestfs-python.pod

man_MANS = guestfs-python.3
noinst_DATA = $(top_builddir)/html/guestfs-python.3.html

guestfs-python.3 $(top_builddir)/html/guestfs-python.3.html: stamp-guestfs-python.pod

stamp-guestfs-python.pod: guestfs-python.pod create_disk.py inspect_vm.py
	$(top_builddir)/podwrapper.sh \
	  --section 3 \
	  --man guestfs-python.3 \
	  --html $(top_builddir)/html/guestfs-python.3.html \
	  --verbatim $(srcdir)/create_disk.py:@EXAMPLE1@ \
	  --verbatim $(srcdir)/inspect_vm.py:@EXAMPLE2@ \
	  $<
	touch $@
