# libguestfs virt-v2v
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
	run-v2v-locally \
	virt-v2v.pl

if HAVE_V2V

man_MANS = virt-v2v.1

noinst_DATA = @top_builddir@/html/virt-v2v.1.html

virt-v2v.1: virt-v2v.pl
	$(POD2MAN) \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

@top_builddir@/html/virt-v2v.1.html: virt-v2v.pl
	mkdir -p @top_builddir@/html
	cd @top_builddir@ && pod2html \
	  --css 'pod.css' \
	  --title 'virt-v2v, convert virtual machine from Xen to KVM' \
	  --htmldir html \
	  --outfile html/virt-v2v.1.html \
	  v2v/$<

install-data-hook:
	mkdir -p $(DESTDIR)$(bindir)
	install -m 0755 virt-v2v.pl $(DESTDIR)$(bindir)/virt-v2v

endif
