# libguestfs virt-edit
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
	run-edit-locally \
	virt-edit.pl

if HAVE_EDIT

man_MANS = virt-edit.1

noinst_DATA = $(top_builddir)/html/virt-edit.1.html

virt-edit.1: virt-edit.pl
	$(POD2MAN) \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

$(top_builddir)/html/virt-edit.1.html: virt-edit.pl
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --title 'virt-edit, edit a file in a virtual machine' \
	  --htmldir html \
	  --outfile html/virt-edit.1.html \
	  edit/$<

install-data-hook:
	mkdir -p $(DESTDIR)$(bindir)
	install -m 0755 virt-edit.pl $(DESTDIR)$(bindir)/virt-edit

endif
