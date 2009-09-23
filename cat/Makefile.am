# libguestfs virt-cat
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

EXTRA_DIST = \
	run-cat-locally \
	virt-cat.pl

if HAVE_CAT

man_MANS = virt-cat.1

noinst_DATA = $(top_builddir)/html/virt-cat.1.html

virt-cat.1: virt-cat.pl
	$(POD2MAN) \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t && mv $@-t $@

$(top_builddir)/html/virt-cat.1.html: virt-cat.pl
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --title 'virt-cat, display a file in a virtual machine' \
	  --htmldir html \
	  --outfile html/virt-cat.1.html \
	  cat/$<

install-data-hook:
	mkdir -p $(DESTDIR)$(bindir)
	install -m 0755 virt-cat.pl $(DESTDIR)$(bindir)/virt-cat

endif
