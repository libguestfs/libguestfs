# libguestfs Erlang examples
# Copyright (C) 2011 Red Hat Inc.
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
	create_disk.erl \
	inspect_vm.erl \
	guestfs-erlang.pod

CLEANFILES = stamp-guestfs-erlang.pod

man_MANS = guestfs-erlang.3
noinst_DATA = $(top_builddir)/html/guestfs-erlang.3.html

guestfs-erlang.3 $(top_builddir)/html/guestfs-erlang.3.html: stamp-guestfs-erlang.pod

stamp-guestfs-erlang.pod: guestfs-erlang.pod create_disk.erl inspect_vm.erl
	$(PODWRAPPER) \
	  --section 3 \
	  --man guestfs-erlang.3 \
	  --html $(top_builddir)/html/guestfs-erlang.3.html \
	  --verbatim $(srcdir)/create_disk.erl:@EXAMPLE1@ \
	  --verbatim $(srcdir)/inspect_vm.erl:@EXAMPLE2@ \
	  $<
	touch $@
