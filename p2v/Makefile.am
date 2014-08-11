# libguestfs virt-p2v
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

include $(top_srcdir)/subdir-rules.mk

EXTRA_DIST = \
	virt-p2v.pod

CLEANFILES = stamp-virt-p2v.pod

# Although virt-p2v is a regular binary, it is not usually installed
# in /usr/bin since it only functions when contained in an ISO or PXE
# image which is used to boot the physical machine (since otherwise
# virt-p2v would not be able to get a consistent snapshot of the
# physical disks).
libexec_PROGRAMS = virt-p2v

# Note that miniexpect comes from here:
# http://git.annexia.org/?p=miniexpect.git;a=summary
virt_p2v_SOURCES = \
	authors.c \
	config.c \
	conversion.c \
	copying.c \
	gui.c \
	kernel.c \
	main.c \
	miniexpect.c \
	miniexpect.h \
	p2v.h \
	ssh.c

virt_p2v_CPPFLAGS = \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

virt_p2v_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(PCRE_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(GTK2_CFLAGS)

virt_p2v_LDADD = \
	$(top_builddir)/src/libutils.la \
	$(PCRE_LIBS) \
	$(LIBXML2_LIBS) \
	$(GTK2_LIBS) \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-p2v.1

noinst_DATA = \
	$(top_builddir)/html/virt-p2v.1.html

virt-p2v.1 $(top_builddir)/html/virt-p2v.1.html: stamp-virt-p2v.pod

stamp-virt-p2v.pod: virt-p2v.pod
	$(PODWRAPPER) \
	  --man virt-p2v.1 \
	  --html $(top_builddir)/html/virt-p2v.1.html \
	  --license GPLv2+ \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

#if ENABLE_APPLIANCE
#TESTS = \
#	test-virt-p2v.sh
#endif ENABLE_APPLIANCE
#
#check-valgrind:
#	$(MAKE) VG="$(top_builddir)/run @VG@" check
