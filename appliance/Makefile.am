# libguestfs
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

include $(top_srcdir)/subdir-rules.mk

EXTRA_DIST = \
	99-guestfs-serial.rules \
	excludelist.in \
	guestfsd.suppressions \
	guestfs_lvm_conf.aug \
	init \
	libguestfs-make-fixed-appliance.in \
	libguestfs-make-fixed-appliance.pod \
	make.sh.in \
	packagelist.in

fsdir = $(libdir)/guestfs
superminfsdir = $(libdir)/guestfs/supermin.d

fs_DATA =
superminfs_DATA = \
	supermin.d/init.img \
	supermin.d/udev-rules.img

if ENABLE_DAEMON
superminfs_DATA += \
	supermin.d/daemon.img
endif

if ENABLE_APPLIANCE
superminfs_DATA += \
	supermin.d/base.img \
	supermin.d/hostfiles
endif

# This used to be a configure-generated file (as is update.sh still).
# However config.status always touches the destination file, which
# means the appliance got rebuilt too often.
make.sh: make.sh.in $(top_builddir)/config.log $(top_builddir)/config.status
	cd $(top_builddir) && \
	  ./config.status --file=appliance/$@-t:appliance/$<
	chmod +x $@-t
	cmp -s $@ $@-t || mv $@-t $@
	rm -f $@-t

PACKAGELIST_CPP_FLAGS = -D$(DISTRO)=1
if VALGRIND_DAEMON
PACKAGELIST_CPP_FLAGS += -DVALGRIND_DAEMON=1
endif

packagelist: packagelist.in Makefile
	cpp -undef $(PACKAGELIST_CPP_FLAGS) < $< | \
	grep -v '^[[:space:]]*$$' | grep -v '^#' > $@-t
	cmp -s $@ $@-t || mv $@-t $@
	rm -f $@-t

excludelist: excludelist.in Makefile
	cpp -undef $(PACKAGELIST_CPP_FLAGS) < $< | \
	grep -v '^[[:space:]]*$$' | grep -v '^#' > $@-t
	cmp -s $@ $@-t || mv $@-t $@
	rm -f $@-t

supermin.d/base.img supermin.d/hostfiles: stamp-supermin
stamp-supermin: make.sh packagelist excludelist
	rm -f $@ supermin.d/base.img supermin.d/hostfiles
	./make.sh
	touch $@

supermin.d/daemon.img: ../daemon/guestfsd guestfsd.suppressions guestfs_lvm_conf.aug
	rm -f $@ $@-t
	rm -rf tmp-d
	mkdir -p tmp-d$(DAEMON_SUPERMIN_DIR) tmp-d/etc tmp-d/usr/share/guestfs
	ln ../daemon/guestfsd tmp-d$(DAEMON_SUPERMIN_DIR)/guestfsd
	ln $(srcdir)/guestfsd.suppressions tmp-d/etc/guestfsd.suppressions
	ln $(srcdir)/guestfs_lvm_conf.aug tmp-d/usr/share/guestfs/guestfs_lvm_conf.aug
	( cd tmp-d && find | cpio --quiet -o -H newc ) > $@-t
	rm -rf tmp-d
	mv $@-t $@

supermin.d/init.img: init
	rm -rf init.tmp $@ $@-t
	mkdir init.tmp
	cp $< init.tmp
	(cd init.tmp; echo "init" | cpio --quiet -o -H newc) > $@-t
	rm -r init.tmp
	mv $@-t $@

# We should put this file in /lib/udev/rules.d, but put it in /etc so
# we don't have to deal with all the UsrMove crap in Fedora.
supermin.d/udev-rules.img: 99-guestfs-serial.rules
	rm -f $@ $@-t
	rm -rf tmp-u
	mkdir -p tmp-u/etc/udev/rules.d
	for f in $^; do ln $$f tmp-u/etc/udev/rules.d/$$(basename $$f); done
	( cd tmp-u && find | cpio --quiet -o -H newc ) > $@-t
	rm -rf tmp-u
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

CLEANFILES = packagelist excludelist \
	libguestfs-make-fixed-appliance.1 \
	stamp-libguestfs-make-fixed-appliance.pod \
	supermin.d/*
