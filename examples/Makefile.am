# libguestfs C examples
# Copyright (C) 2010-2023 Red Hat Inc.
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
	LICENSE \
	guestfs-examples.pod \
	copy-over.c \
	create-disk.c \
	debug-logging.c \
	display-icon.c \
	inspect-vm.c \
	libvirt-auth.c \
	mount-local.c \
	virt-dhcp-address.c

noinst_PROGRAMS = create-disk debug-logging display-icon inspect-vm
if HAVE_LIBVIRT
noinst_PROGRAMS += copy-over libvirt-auth
endif
if HAVE_HIVEX
noinst_PROGRAMS += virt-dhcp-address
endif
if HAVE_FUSE
noinst_PROGRAMS += mount-local
endif

if HAVE_LIBVIRT
copy_over_SOURCES = copy-over.c
copy_over_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-I$(top_srcdir)/include
copy_over_CFLAGS = \
	$(LIBVIRT_CFLAGS) \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
copy_over_LDADD = \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBVIRT_LIBS)

libvirt_auth_SOURCES = libvirt-auth.c
libvirt_auth_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-I$(top_srcdir)/include
libvirt_auth_CFLAGS = \
	$(LIBVIRT_CFLAGS) \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
libvirt_auth_LDADD = \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBVIRT_LIBS)
endif

create_disk_SOURCES = create-disk.c
create_disk_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-I$(top_srcdir)/include
create_disk_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
create_disk_LDADD = \
	$(top_builddir)/lib/libguestfs.la

debug_logging_SOURCES = debug-logging.c
debug_logging_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-I$(top_srcdir)/include
debug_logging_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
debug_logging_LDADD = \
	$(top_builddir)/lib/libguestfs.la

display_icon_SOURCES = display-icon.c
display_icon_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-I$(top_srcdir)/include
display_icon_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
display_icon_LDADD = \
	$(top_builddir)/lib/libguestfs.la

inspect_vm_SOURCES = inspect-vm.c
inspect_vm_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-I$(top_srcdir)/include
inspect_vm_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
inspect_vm_LDADD = \
	$(top_builddir)/lib/libguestfs.la

if HAVE_FUSE
mount_local_SOURCES = mount-local.c
mount_local_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-I$(top_srcdir)/include
mount_local_CFLAGS = \
	-I$(top_srcdir)/include \
	$(FUSE_CFLAGS) \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
mount_local_LDADD = \
	$(FUSE_LIBS) \
	$(top_builddir)/lib/libguestfs.la
endif

if HAVE_HIVEX
virt_dhcp_address_SOURCES = virt-dhcp-address.c
virt_dhcp_address_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-I$(top_srcdir)/include
virt_dhcp_address_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
virt_dhcp_address_LDADD = \
	$(top_builddir)/lib/libguestfs.la
endif

man_MANS = guestfs-examples.3
noinst_DATA = $(top_builddir)/website/guestfs-examples.3.html

guestfs-examples.3 $(top_builddir)/website/guestfs-examples.3.html: stamp-guestfs-examples.pod

stamp-guestfs-examples.pod: guestfs-examples.pod copy-over.c create-disk.c debug-logging.c display-icon.c inspect-vm.c libvirt-auth.c mount-local.c virt-dhcp-address.c
	$(PODWRAPPER) \
	  --section 3 \
	  --man guestfs-examples.3 \
	  --html $(top_builddir)/website/guestfs-examples.3.html \
	  --verbatim $(srcdir)/copy-over.c:@COPY_OVER@ \
	  --verbatim $(srcdir)/create-disk.c:@CREATE_DISK@ \
	  --verbatim $(srcdir)/debug-logging.c:@DEBUG_LOGGING@ \
	  --verbatim $(srcdir)/display-icon.c:@DISPLAY_ICON@ \
	  --verbatim $(srcdir)/inspect-vm.c:@INSPECT_VM@ \
	  --verbatim $(srcdir)/libvirt-auth.c:@LIBVIRT_AUTH@ \
	  --verbatim $(srcdir)/mount-local.c:@MOUNT_LOCAL@ \
	  --verbatim $(srcdir)/virt-dhcp-address.c:@VIRT_DHCP_ADDRESS@ \
	  --license examples \
	  $<
	touch $@
