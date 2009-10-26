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

EXTRA_DIST = hivex.pod hivexml.pod hivexget.pod

lib_LTLIBRARIES = libhivex.la

libhivex_la_SOURCES = \
  hivex.c \
  hivex.h

libhivex_la_LDFLAGS = -version-info 0:0:0
libhivex_la_CFLAGS = \
  $(WARN_CFLAGS) $(WERROR_CFLAGS)

bin_PROGRAMS = hivexml hivexget

hivexml_SOURCES = \
  hivexml.c

hivexml_LDADD = libhivex.la $(LIBXML2_LIBS)
hivexml_CFLAGS = \
  $(LIBXML2_CFLAGS) \
  $(WARN_CFLAGS) $(WERROR_CFLAGS)

hivexget_SOURCES = \
  hivexget.c

hivexget_LDADD = libhivex.la
hivexget_CFLAGS = \
  $(WARN_CFLAGS) $(WERROR_CFLAGS)

man_MANS = hivex.3 hivexml.1 hivexget.1

hivex.3: hivex.pod
	$(POD2MAN) \
	  --section 3 \
	  -c "Windows Registry" \
	  --name "hivex" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t; mv $@-t $@

hivexml.1: hivexml.pod
	$(POD2MAN) \
	  --section 1 \
	  -c "Windows Registry" \
	  --name "hivexml" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t; mv $@-t $@

hivexget.1: hivexget.pod
	$(POD2MAN) \
	  --section 1 \
	  -c "Windows Registry" \
	  --name "hivexget" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t; mv $@-t $@
