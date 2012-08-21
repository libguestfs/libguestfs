# libguestfs Ruby examples
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

EXTRA_DIST = \
	LICENSE \
	create_disk.rb \
	inspect_vm.rb \
	guestfs-ruby.pod

CLEANFILES = stamp-guestfs-ruby.pod

man_MANS = guestfs-ruby.3
noinst_DATA = $(top_builddir)/html/guestfs-ruby.3.html

guestfs-ruby.3 $(top_builddir)/html/guestfs-ruby.3.html: stamp-guestfs-ruby.pod

stamp-guestfs-ruby.pod: guestfs-ruby.pod create_disk.rb inspect_vm.rb
	$(PODWRAPPER) \
	  --section 3 \
	  --man guestfs-ruby.3 \
	  --html $(top_builddir)/html/guestfs-ruby.3.html \
	  --verbatim $(srcdir)/create_disk.rb:@EXAMPLE1@ \
	  --verbatim $(srcdir)/inspect_vm.rb:@EXAMPLE2@ \
	  --license examples \
	  $<
	touch $@
