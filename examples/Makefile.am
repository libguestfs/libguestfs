# libguestfs C examples
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
	guestfs-examples.pod

CLEANFILES = stamp-guestfs-examples.pod

noinst_PROGRAMS = create_disk inspect_vm

create_disk_SOURCES = create_disk.c
create_disk_CFLAGS = -I$(top_srcdir)/src -I$(top_builddir)/src -Wall
create_disk_LDADD = $(top_builddir)/src/libguestfs.la

inspect_vm_SOURCES = inspect_vm.c
inspect_vm_CFLAGS = -I$(top_srcdir)/src -I$(top_builddir)/src -Wall
inspect_vm_LDADD = $(top_builddir)/src/libguestfs.la

man_MANS = guestfs-examples.3
noinst_DATA = $(top_builddir)/html/guestfs-examples.3.html

guestfs-examples.3 $(top_builddir)/html/guestfs-examples.3.html: stamp-guestfs-examples.pod

stamp-guestfs-examples.pod: guestfs-examples.pod create_disk.c inspect_vm.c
	$(top_srcdir)/podwrapper.sh \
	  --section 3 \
	  --man guestfs-examples.3 \
	  --html $(top_builddir)/html/guestfs-examples.3.html \
	  --verbatim create_disk.c:@EXAMPLE1@ \
	  --verbatim inspect_vm.c:@EXAMPLE2@ \
	  $<
	touch $@
