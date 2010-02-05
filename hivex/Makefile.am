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

SUBDIRS = t tools

EXTRA_DIST = \
	hivex.pod \
	hivexml.pod \
	hivexget.pod \
	hivexget \
	hivexsh.pod \
	LICENSE \
	example1 \
	example2 \
	example3 \
	example4 \
	example5 \
	example6

lib_LTLIBRARIES = libhivex.la

libhivex_la_SOURCES = \
  hivex.c \
  hivex.h \
  byte_conversions.h

libhivex_la_LDFLAGS = -version-info 0:0:0 $(LTLIBINTL) $(LTLIBTHREAD)
libhivex_la_CFLAGS = $(WARN_CFLAGS) $(WERROR_CFLAGS)
libhivex_la_CPPFLAGS = -I$(top_srcdir)/gnulib/lib

bin_PROGRAMS = hivexml hivexsh
bin_SCRIPTS = hivexget
noinst_SCRIPTS = example1 example2 example3 example4 example5 example6

hivexml_SOURCES = \
  hivexml.c

hivexml_LDADD = libhivex.la $(LIBXML2_LIBS) ../gnulib/lib/libgnu.la
hivexml_CFLAGS = \
  -I$(top_srcdir)/src \
  -DLOCALEBASEDIR=\""$(datadir)/locale"\" \
  $(LIBXML2_CFLAGS) \
  $(WARN_CFLAGS) $(WERROR_CFLAGS)

hivexsh_SOURCES = \
  hivexsh.c \
  hivex.h \
  byte_conversions.h

hivexsh_LDADD = libhivex.la ../gnulib/lib/libgnu.la  $(LIBREADLINE)
hivexsh_CFLAGS = \
  -I$(top_srcdir)/gnulib/lib \
  -I$(top_srcdir)/src \
  -DLOCALEBASEDIR=\""$(datadir)/locale"\" \
  $(WARN_CFLAGS) $(WERROR_CFLAGS)

man_MANS = hivex.3 hivexml.1 hivexget.1 hivexsh.1

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

hivexsh.1: hivexsh.pod
	$(POD2MAN) \
	  --section 1 \
	  -c "Windows Registry" \
	  --name "hivexsh" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t; mv $@-t $@

noinst_DATA = \
	$(top_builddir)/html/hivex.3.html \
	$(top_builddir)/html/hivexml.1.html \
	$(top_builddir)/html/hivexget.1.html \
	$(top_builddir)/html/hivexsh.1.html

$(top_builddir)/html/hivex.3.html: hivex.pod
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --htmldir html \
	  --outfile html/hivex.3.html \
	  hivex/hivex.pod

$(top_builddir)/html/hivexml.1.html: hivexml.pod
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --htmldir html \
	  --outfile html/hivexml.1.html \
	  hivex/hivexml.pod

$(top_builddir)/html/hivexget.1.html: hivexget.pod
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --htmldir html \
	  --outfile html/hivexget.1.html \
	  hivex/hivexget.pod

$(top_builddir)/html/hivexsh.1.html: hivexsh.pod
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --htmldir html \
	  --outfile html/hivexsh.1.html \
	  hivex/hivexsh.pod
