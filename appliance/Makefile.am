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
	excludelist.in \
	guestfsd.suppressions \
	init \
	make.sh.in \
	packagelist.in

fsdir = $(libdir)/guestfs
superminfsdir = $(libdir)/guestfs/supermin.d

fs_DATA =
superminfs_DATA = \
	supermin.d/base.img \
	supermin.d/daemon.img \
	supermin.d/init.img \
	supermin.d/hostfiles

# This used to be a configure-generated file (as is update.sh still).
# However config.status always touches the destination file, which
# means the appliance got rebuilt too often.
make.sh: make.sh.in
	cd $(top_builddir) && \
	  ./config.status --file=appliance/$@-t:appliance/$<
	chmod +x $@-t
	mv $@-t $@

PACKAGELIST_CPP_FLAGS = -D$(DISTRO)=1
if VALGRIND_DAEMON
PACKAGELIST_CPP_FLAGS += -DVALGRIND_DAEMON=1
endif

packagelist: packagelist.in
	cpp -undef $(PACKAGELIST_CPP_FLAGS) < $< | \
	grep -v '^[[:space:]]*$$' | grep -v '^#' > $@-t
	mv $@-t $@

excludelist: excludelist.in
	cpp -undef $(PACKAGELIST_CPP_FLAGS) < $< | \
	grep -v '^[[:space:]]*$$' | grep -v '^#' > $@-t
	mv $@-t $@

supermin.d/base.img supermin.d/hostfiles: stamp-supermin
stamp-supermin: make.sh packagelist excludelist
	mkdir -p supermin.d
	rm -f $@ supermin.d/base.img supermin.d/hostfiles
	./make.sh
	touch $@

supermin.d/daemon.img: ../daemon/guestfsd guestfsd.suppressions
	mkdir -p supermin.d
	rm -f $@ $@-t
	rm -rf tmp
	mkdir -p tmp$(DAEMON_SUPERMIN_DIR) tmp/etc
	ln ../daemon/guestfsd tmp$(DAEMON_SUPERMIN_DIR)/guestfsd
	ln $(srcdir)/guestfsd.suppressions tmp/etc/guestfsd.suppressions
	( cd tmp && find | cpio --quiet -o -H newc ) > $@-t
	rm -rf tmp
	mv $@-t $@

supermin.d/init.img: init
	cmp -s $(srcdir)/init $(builddir)/init || cp $(srcdir)/init $(builddir)/init
	mkdir -p supermin.d
	rm -f $@ $@-t
	echo "init" | cpio --quiet -o -H newc > $@-t
	mv $@-t $@

# Make clean.

CLEANFILES = packagelist excludelist

clean-local:
	rm -rf supermin.d
