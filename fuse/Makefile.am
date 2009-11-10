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

EXTRA_DIST = guestmount.pod

if HAVE_FUSE

bin_PROGRAMS = guestmount

guestmount_SOURCES = \
	dircache.c \
	dircache.h \
	guestmount.c \
	guestmount.h

guestmount_CFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DGUESTFS_DEFAULT_PATH='"$(libdir)/guestfs"' \
	$(FUSE_CFLAGS) \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

guestmount_LDADD = \
	$(FUSE_LIBS) -lulockmgr \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la

man_MANS = guestmount.1

guestmount.1: guestmount.pod
	$(POD2MAN) \
	  --section 1 \
	  -c "Virtualization Support" \
	  --name "guestmount" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t; mv $@-t $@

noinst_DATA = \
	$(top_builddir)/html/guestmount.1.html

$(top_builddir)/html/guestmount.1.html: guestmount.pod
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --htmldir html \
	  --outfile html/guestmount.1.html \
	  fuse/guestmount.pod

endif
