# libguestfs virt-cat, virt-filesystems and virt-ls.
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

include $(top_srcdir)/subdir-rules.mk

EXTRA_DIST = \
	run-cat-locally \
	test-virt-cat.sh \
	virt-cat.pod \
	run-filesystems-locally \
	test-virt-filesystems.sh \
	virt-filesystems.pod \
	run-ls-locally \
	test-virt-ls.sh \
	virt-ls.pod

bin_PROGRAMS = virt-cat virt-filesystems virt-ls

SHARED_SOURCE_FILES = \
	../fish/inspect.c \
	../fish/keys.c \
	../fish/options.h \
	../fish/options.c \
	../fish/virt.c

virt_cat_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-cat.c

virt_cat_CFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

virt_cat_LDADD = \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la

virt_filesystems_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-filesystems.c

virt_filesystems_CFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

virt_filesystems_LDADD = \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la

virt_ls_SOURCES = \
	$(SHARED_SOURCE_FILES) \
	virt-ls.c

virt_ls_CFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)

virt_ls_LDADD = \
	$(top_builddir)/src/libguestfs.la \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-cat.1 virt-filesystems.1 virt-ls.1

noinst_DATA = \
	$(top_builddir)/html/virt-cat.1.html \
	$(top_builddir)/html/virt-filesystems.1.html \
	$(top_builddir)/html/virt-ls.1.html

virt-cat.1: virt-cat.pod
	$(POD2MAN) \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t && mv $@-t $@

$(top_builddir)/html/virt-cat.1.html: virt-cat.pod
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --htmldir html \
	  --outfile html/$@ \
	  $(abs_srcdir)/$<

virt-filesystems.1: virt-filesystems.pod
	$(POD2MAN) \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t && mv $@-t $@

$(top_builddir)/html/virt-filesystems.1.html: virt-filesystems.pod
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --htmldir html \
	  --outfile html/$@ \
	  $(abs_srcdir)/$<

virt-ls.1: virt-ls.pod
	$(POD2MAN) \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t && mv $@-t $@

$(top_builddir)/html/virt-ls.1.html: virt-ls.pod
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --htmldir html \
	  --outfile html/$@ \
	  $(abs_srcdir)/$<

# Tests.

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	LD_LIBRARY_PATH=$(top_builddir)/src/.libs \
	LIBGUESTFS_PATH=$(top_builddir)/appliance

TESTS = test-virt-cat.sh test-virt-filesystems.sh test-virt-ls.sh

# Build a partly-static binary (for the binary distribution).

virt-cat.static$(EXEEXT): $(virt_cat_OBJECTS) $(virt_cat_DEPENDENCIES)
	$(top_srcdir)/relink-static.sh \
	$(virt_cat_LINK) $(virt_cat_OBJECTS) -static $(virt_cat_LDADD) $(virt_cat_LIBS) $(LIBVIRT_LIBS) $(LIBXML2_LIBS) -lpcre -lhivex -lmagic -lz -lm

virt-filesystems.static$(EXEEXT): $(virt_filesystems_OBJECTS) $(virt_filesystems_DEPENDENCIES)
	$(top_srcdir)/relink-static.sh \
	$(virt_filesystems_LINK) $(virt_filesystems_OBJECTS) -static $(virt_filesystems_LDADD) $(virt_filesystems_LIBS) $(LIBVIRT_LIBS) $(LIBXML2_LIBS) -lpcre -lhivex -lmagic -lz -lm

virt-ls.static$(EXEEXT): $(virt_ls_OBJECTS) $(virt_ls_DEPENDENCIES)
	$(top_srcdir)/relink-static.sh \
	$(virt_ls_LINK) $(virt_ls_OBJECTS) -static $(virt_ls_LDADD) $(virt_ls_LIBS) $(LIBVIRT_LIBS) $(LIBXML2_LIBS) -lpcre -lhivex -lmagic -lz -lm
