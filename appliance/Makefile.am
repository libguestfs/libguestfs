# libguestfs
# Copyright (C) 2009-2016 Red Hat Inc.
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
	guestfs_lvm_conf.aug \
	guestfs_shadow.aug \
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
	supermin.d/base.tar.gz \
	supermin.d/daemon.tar.gz \
	supermin.d/excludefiles \
	supermin.d/hostfiles \
	supermin.d/init.tar.gz \
	supermin.d/packages \
	supermin.d/udev-rules.tar.gz

supermin.d/base.tar.gz supermin.d/packages: stamp-supermin
stamp-supermin: make.sh packagelist supermin.d/excludefiles
	rm -f $@ supermin.d/base.tar.gz supermin.d/packages
	./make.sh
	$(MAKE) \
	  supermin.d/daemon.tar.gz \
	  supermin.d/excludefiles \
	  supermin.d/hostfiles \
	  supermin.d/init.tar.gz \
	  supermin.d/udev-rules.tar.gz
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

packagelist: packagelist.in Makefile
	m4 $(PACKAGELIST_CPP_FLAGS) $< | \
	grep -v '^[[:space:]]*$$' | grep -v '^#' > $@-t
	cmp -s $@ $@-t || mv $@-t $@
	rm -f $@-t

supermin.d/daemon.tar.gz: ../daemon/guestfsd guestfs_lvm_conf.aug guestfs_shadow.aug
	rm -f $@ $@-t
	rm -rf tmp-d
	mkdir -p tmp-d$(DAEMON_SUPERMIN_DIR) tmp-d/etc tmp-d/usr/share/guestfs
	ln ../daemon/guestfsd tmp-d$(DAEMON_SUPERMIN_DIR)/guestfsd
	( cd tmp-d && tar zcf - * ) > $@-t
	rm -r tmp-d
	mv $@-t $@

# Note we must avoid touching supermin.d if possible, so don't create
# the temporary files inside the supermin.d directory.

supermin.d/excludefiles: excludefiles.in Makefile
	m4 $(PACKAGELIST_CPP_FLAGS) $< | \
	grep -v '^[[:space:]]*$$' | grep -v '^#' > excludefiles-t
	cmp -s $@ excludefiles-t || mv excludefiles-t $@
	rm -f excludefiles-t

supermin.d/hostfiles: hostfiles.in Makefile
	m4 $(PACKAGELIST_CPP_FLAGS) $< | \
	grep -v '^[[:space:]]*$$' | grep -v '^#' > hostfiles-t
	cmp -s $@ hostfiles-t || mv hostfiles-t $@
	rm -f hostfiles-t

supermin.d/init.tar.gz: init
	rm -f $@ $@-t
	( cd $(srcdir) && tar zcf - init ) > $@-t
	mv $@-t $@

# We should put this file in /lib/udev/rules.d, but put it in /etc so
# we don't have to deal with all the UsrMove crap in Fedora.
supermin.d/udev-rules.tar.gz: 99-guestfs-serial.rules
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

libguestfs-make-fixed-appliance.1 $(top_builddir)/website/libguestfs-make-fixed-appliance.1.html: stamp-libguestfs-make-fixed-appliance.pod

stamp-libguestfs-make-fixed-appliance.pod: libguestfs-make-fixed-appliance.pod
	$(PODWRAPPER) \
	  --man libguestfs-make-fixed-appliance.1 \
	  --html $(top_builddir)/website/libguestfs-make-fixed-appliance.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

# Make clean.

CLEANFILES = \
	*~ \
	libguestfs-make-fixed-appliance.1 \
	stamp-libguestfs-make-fixed-appliance.pod

DISTCLEANFILES = \
	make.sh \
	packagelist \
	stamp-supermin \
	supermin.d/*
