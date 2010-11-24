# libguestfs translations of man pages and POD files
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

# Note that each Makefile.am in po-docs/$lang/Makefile.am should be
# identical.  If you create a new $lang.po, create the $lang/
# subdirectory and copy the Makefile.am from an existing language.

LINGUA = $(shell basename -- `pwd`)

CLEANFILES = *.1 *.3

MANPAGES = \
	guestfs.3 \
	guestfish.1 \
	libguestfs-test-tool.1 \
	guestmount.1 \
	$(patsubst %.pl,%.1,$(wildcard virt-*.pl))

# Ship the POD files and the translated manpages in the tarball.  This
# just simplifies building from the tarball, at a small cost in extra
# size.
EXTRA_DIST = \
	$(MANPAGES) \
	guestfs.pod guestfs-actions.pod guestfs-availability.pod guestfs-structs.pod \
	guestfish.pod guestfish-actions.pod guestfish-commands.pod \
	guestmount.pod \
	libguestfs-test-tool.pod \
	$(wildcard virt-*.pl)

if HAVE_PO4A

all-local: $(MANPAGES)

guestfs.3: guestfs.pod guestfs-actions.pod guestfs-availability.pod guestfs-structs.pod
	$(top_srcdir)/podwrapper.sh \
	  --section 3 \
	  --man $@ \
	  --insert guestfs-actions.pod:@ACTIONS@ \
	  --insert guestfs-availability.pod:@AVAILABILITY@ \
	  --insert guestfs-structs.pod:@STRUCTS@ \
	  $<

guestfish.1: guestfish.pod guestfish-actions.pod guestfish-commands.pod
	$(top_srcdir)/podwrapper.sh \
	  --man $@ \
	  --insert guestfish-actions.pod:@ACTIONS@ \
	  --insert guestfish-commands.pod:@FISH_COMMANDS@ \
	  $<

guestmount.1: guestmount.pod
	$(top_srcdir)/podwrapper.sh \
	  --man $@ \
	  $<

libguestfs-test-tool.1: libguestfs-test-tool.pod
	$(top_srcdir)/podwrapper.sh \
	  --man $@ \
	  $<

virt-%.1: virt-%.pl
	$(top_srcdir)/podwrapper.sh \
	  --man $@ \
	  $<

else

all-local:

endif

# XXX Can automake do this properly?
install-data-hook:
	$(MKDIR_P) $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(INSTALL) -m 0644 guestfish.1 $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(INSTALL) -m 0644 guestmount.1 $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(INSTALL) -m 0644 virt-*.1 $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(MKDIR_P) $(DESTDIR)$(mandir)/$(LINGUA)/man3
	$(INSTALL) -m 0644 guestfs.3 $(DESTDIR)$(mandir)/$(LINGUA)/man3
