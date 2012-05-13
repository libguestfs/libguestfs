# libguestfs C examples
# Copyright (C) 2010-2012 Red Hat Inc.
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

EXTRA_DIST = \
	LICENSE \
	guestfs-examples.pod \
	guestfs-recipes.pod \
	guestfs-testing.pod

CLEANFILES = \
	stamp-guestfs-examples.pod \
	stamp-guestfs-recipes.pod \
	stamp-guestfs-testing.pod

noinst_PROGRAMS = create_disk inspect_vm
if HAVE_HIVEX
noinst_PROGRAMS += virt-dhcp-address
endif

create_disk_SOURCES = create_disk.c
create_disk_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
create_disk_LDADD = \
	$(top_builddir)/src/libguestfs.la

inspect_vm_SOURCES = inspect_vm.c
inspect_vm_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
inspect_vm_LDADD = \
	$(top_builddir)/src/libguestfs.la

if HAVE_HIVEX
virt_dhcp_address_SOURCES = virt-dhcp-address.c
virt_dhcp_address_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(HIVEX_CFLAGS)
virt_dhcp_address_LDADD = \
	$(HIVEX_LIBS) \
	$(top_builddir)/src/libguestfs.la
endif

man_MANS = \
	guestfs-examples.3 \
	guestfs-recipes.1 \
	guestfs-testing.1
noinst_DATA = \
	$(top_builddir)/html/guestfs-examples.3.html \
	$(top_builddir)/html/guestfs-recipes.1.html \
	$(top_builddir)/html/guestfs-testing.1.html

guestfs-examples.3 $(top_builddir)/html/guestfs-examples.3.html: stamp-guestfs-examples.pod

stamp-guestfs-examples.pod: guestfs-examples.pod create_disk.c inspect_vm.c
	$(top_builddir)/podwrapper.sh \
	  --section 3 \
	  --man guestfs-examples.3 \
	  --html $(top_builddir)/html/guestfs-examples.3.html \
	  --verbatim $(srcdir)/create_disk.c:@EXAMPLE1@ \
	  --verbatim $(srcdir)/inspect_vm.c:@EXAMPLE2@ \
	  $<
	touch $@

guestfs-recipes.1 $(top_builddir)/html/guestfs-recipes.1.html: stamp-guestfs-recipes.pod

stamp-guestfs-recipes.pod: guestfs-recipes.pod
	$(top_builddir)/podwrapper.sh \
	  --section 1 \
	  --man guestfs-recipes.1 \
	  --html $(top_builddir)/html/guestfs-recipes.1.html \
	  $<
	touch $@

guestfs-testing.1 $(top_builddir)/html/guestfs-testing.1.html: stamp-guestfs-testing.pod

stamp-guestfs-testing.pod: guestfs-testing.pod
	$(top_builddir)/podwrapper.sh \
	  --section 1 \
	  --man guestfs-testing.1 \
	  --html $(top_builddir)/html/guestfs-testing.1.html \
	  $<
	touch $@
