# libguestfs
# Copyright (C) 2012 Red Hat Inc.
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

if HAVE_LIBVIRT

# This LD_PRELOAD library can be used to precisely control the XML
# returned by libvirt.
check_LTLIBRARIES = libfakevirtxml.la

libfakevirtxml_la_SOURCES = fake_libvirt_xml.c
libfakevirtxml_la_CFLAGS = $(LIBVIRT_CFLAGS)
# -version-info and -rpath force libtool to build a shared library.
libfakevirtxml_la_LDFLAGS = -version-info 0:0:0 -rpath /nowhere

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS = \
	rhbz701814.pl

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	abs_srcdir=$(abs_srcdir) \
	LD_PRELOAD=.libs/libfakevirtxml.so \
	$(top_builddir)/run

endif

EXTRA_DIST = \
	rhbz701814.pl \
	rhbz701814-faked.xml \
	rhbz701814-node.xml

CLEANFILES = *~
