# libguestfs
# Copyright (C) 2009-2014 Red Hat Inc.
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

include $(top_srcdir)/subdir-rules.mk

EXTRA_DIST = \
	99-guestfs-serial.rules \
	excludefiles.in \
	guestfsd.suppressions \
	hostfiles.in \
	init \
	libguestfs-make-fixed-appliance.in \
	libguestfs-make-fixed-appliance.pod \
	make.sh.in \
	packagelist.in

fsdir = $(libdir)/guestfs
superminfsdir = $(libdir)/guestfs/supermin.d

fs_DATA =
superminfs_DATA = \
	supermin.d/init.tar.gz \
	supermin.d/udev-rules.tar.gz

if ENABLE_DAEMON
superminfs_DATA += \
	supermin.d/daemon.tar.gz
endif

if ENABLE_APPLIANCE
superminfs_DATA += \
	supermin.d/base.tar.gz \
	supermin.d/packages \
	supermin.d/excludefiles \
	supermin.d/hostfiles
endif

supermin.d/base.tar.gz \
supermin.d/daemon.tar.gz \
supermin.d/excludefiles \
supermin.d/hostfiles \
supermin.d/init.tar.gz \
supermin.d/packages \
supermin.d/udev-rules.tar.gz: stamp-supermin
stamp-supermin: make.sh \
	  packagelist \
	  hostfiles \
	  excludefiles \
	  daemon.tar.gz \
	  init.tar.gz \
	  udev-rules.tar.gz
	rm -f $@ supermin.d/base.tar.gz supermin.d/packages
	./make.sh
	cp -t supermin.d \
	    daemon.tar.gz excludefiles hostfiles init.tar.gz udev-rules.tar.gz
	touch $@

# This used to be a configure-generated file.  However config.status
# always touches the destination file, which means the appliance got
# rebuilt too often.
make.sh: make.sh.in $(top_builddir)/config.log $(top_builddir)/config.status
	cd $(top_builddir) && \
	  ./config.status --file=appliance/$@-t:appliance/$<
	chmod +x $@-t
	cmp -s $@ $@-t || mv $@-t $@
	rm -f $@-t

PACKAGELIST_CPP_FLAGS = -D$(DISTRO)=1 -DEXTRA_PACKAGES="$(EXTRA_PACKAGES)"
if VALGRIND_DAEMON
PACKAGELIST_CPP_FLAGS += -DVALGRIND_DAEMON=1
endif

excludefiles: excludefiles.in Makefile
	m4 $(PACKAGELIST_CPP_FLAGS) $< | \
	grep -v '^[[:space:]]*$$' | grep -v '^#' > $@-t
	cmp -s $@ $@-t || mv $@-t $@
	rm -f $@-t

hostfiles: hostfiles.in Makefile
	m4 $(PACKAGELIST_CPP_FLAGS) $< | \
	grep -v '^[[:space:]]*$$' | grep -v '^#' > $@-t
	cmp -s $@ $@-t || mv $@-t $@
	rm -f $@-t

packagelist: packagelist.in Makefile
	m4 $(PACKAGELIST_CPP_FLAGS) $< | \
	grep -v '^[[:space:]]*$$' | grep -v '^#' > $@-t
	cmp -s $@ $@-t || mv $@-t $@
	rm -f $@-t

daemon.tar.gz: ../daemon/guestfsd guestfsd.suppressions
	rm -f $@ $@-t
	rm -rf tmp-d
	mkdir -p tmp-d$(DAEMON_SUPERMIN_DIR) tmp-d/etc
	ln ../daemon/guestfsd tmp-d$(DAEMON_SUPERMIN_DIR)/guestfsd
	ln $(srcdir)/guestfsd.suppressions tmp-d/etc/guestfsd.suppressions
	( cd tmp-d && tar zcf - * ) > $@-t
	rm -r tmp-d
	mv $@-t $@

init.tar.gz: init
	rm -f $@ $@-t
	tar zcf $@-t init
	mv $@-t $@

# We should put this file in /lib/udev/rules.d, but put it in /etc so
# we don't have to deal with all the UsrMove crap in Fedora.
udev-rules.tar.gz: 99-guestfs-serial.rules
	rm -f $@ $@-t
	rm -rf tmp-u
	mkdir -p tmp-u/etc/udev/rules.d
	for f in $^; do ln $$f tmp-u/etc/udev/rules.d/$$(basename $$f); done
	( cd tmp-u && tar zcf - etc ) > $@-t
	rm -r tmp-u
	mv $@-t $@

# If installing the daemon, install the udev rules too.

if INSTALL_DAEMON
udevrulesdir = /lib/udev/rules.d
udevrules_DATA = 99-guestfs-serial.rules
endif

# libguestfs-make-fixed-appliance script and man page.

sbin_SCRIPTS = libguestfs-make-fixed-appliance

man_MANS = libguestfs-make-fixed-appliance.1

libguestfs-make-fixed-appliance.1 $(top_builddir)/html/libguestfs-make-fixed-appliance.1.html: stamp-libguestfs-make-fixed-appliance.pod

stamp-libguestfs-make-fixed-appliance.pod: libguestfs-make-fixed-appliance.pod
	$(PODWRAPPER) \
	  --man libguestfs-make-fixed-appliance.1 \
	  --html $(top_builddir)/html/libguestfs-make-fixed-appliance.1.html \
	  --license GPLv2+ \
	  $<
	touch $@

# Make clean.

CLEANFILES = \
	*~ \
	daemon.tar.gz \
	excludefiles \
	hostfiles \
	init.tar.gz \
	libguestfs-make-fixed-appliance.1 \
	packagelist \
	stamp-libguestfs-make-fixed-appliance.pod \
	supermin.d/* \
	udev-rules.tar.gz
