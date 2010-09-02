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

# Ship the final translated manpages in the tarball.
MANPAGES = \
	guestfs.3 \
	guestfish.1 \
	libguestfs-test-tool.1 \
	guestmount.1 \
	$(patsubst %.pl,%.1,$(wildcard virt-*.pl))

EXTRA_DIST = $(MANPAGES)

all-local: $(MANPAGES)

guestfs.3: guestfs.pod guestfs-actions.pod guestfs-availability.pod guestfs-structs.pod
	sed \
	  -e '/@ACTIONS@/rguestfs-actions.pod' \
	  -e 's/@ACTIONS@//' \
	  -e '/@AVAILABILITY@/rguestfs-availability.pod' \
	  -e 's/@AVAILABILITY@//' \
	  -e '/@STRUCTS@/rguestfs-structs.pod' \
	  -e 's/@STRUCTS@//' \
	< $< | \
	$(POD2MAN) -u \
	  --section 3 \
	  -c "Virtualization Support" \
	  --name "guestfs" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  > $@-t; mv $@-t $@

guestfish.1: guestfish.pod guestfish-actions.pod
	sed \
	  -e '/@ACTIONS@/rguestfish-actions.pod' -e 's/@ACTIONS@//' \
	  < $< | \
	$(POD2MAN) -u \
	  --section 1 \
	  -c "Virtualization Support" \
	  --name "guestfish" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  > $@-t; mv $@-t $@

guestmount.1: guestmount.pod
	$(POD2MAN) -u \
	  --section 1 \
	  -c "Virtualization Support" \
	  --name "guestmount" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t; mv $@-t $@

libguestfs-test-tool.1: libguestfs-test-tool.pod
	$(POD2MAN) -u \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t; mv $@-t $@

virt-%.1: virt-%.pl
	$(POD2MAN) -u \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@-t && mv $@-t $@

# XXX Can automake do this properly?
install-data-hook:
	$(MKDIR_P) $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(INSTALL) -m 0644 guestfish.1 $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(INSTALL) -m 0644 guestmount.1 $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(INSTALL) -m 0644 virt-*.1 $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(MKDIR_P) $(DESTDIR)$(mandir)/$(LINGUA)/man3
	$(INSTALL) -m 0644 guestfs.3 $(DESTDIR)$(mandir)/$(LINGUA)/man3
