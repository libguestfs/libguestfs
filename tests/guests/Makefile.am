# libguestfs test images
# Copyright (C) 2009-2015 Red Hat Inc.
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
	guest-aux/make-debian-img.sh \
	guest-aux/debian-packages \
	guest-aux/debian-syslog \
	guest-aux/make-fedora-img.pl \
	guest-aux/fedora-journal.tar.xz \
	guest-aux/fedora-name.db.txt \
	guest-aux/fedora-name.db \
	guest-aux/fedora-packages.db.txt \
	guest-aux/fedora-packages.db \
	guest-aux/make-ubuntu-img.sh \
	guest-aux/make-archlinux-img.sh \
	guest-aux/archlinux-package \
	guest-aux/make-windows-img.sh \
	guest-aux/windows-software \
	guest-aux/windows-software.reg \
	guest-aux/windows-system \
	guest-aux/windows-system.reg \
	guest-aux/minimal-hive \
	guest-aux/make-guests-all-good.pl \
	guests.xml.in

disk_images = \
	blank-disk.img \
	blank-part.img \
	blank-fs.img \
	blank-bootroot.img \
	blank-bootrootlv.img \
	debian.img \
	fedora.img \
	fedora-md1.img \
	fedora-md2.img \
	fedora-btrfs.img \
	ubuntu.img \
	archlinux.img \
	windows.img

# This is 'check_DATA' because we don't need it until 'make check'
# time and we need the tools we have built in order to make it.
check_DATA = $(disk_images) guests-all-good.xml

CLEANFILES = $(check_DATA) \
	guests-all-good.xml \
	stamp-fedora-md.img \
	*.tmp.*

# Make several different blank images.  These are not guests, but we
# include them in the libvirt fake XML to make sure that virt-df and
# virt-alignment-scan don't break when they encounter them.
blank-%.img:
	rm -f $@ $@-t
	$(top_builddir)/run \
	  ../../fish/guestfish \
	    -N $@-t="$$(echo $@ | $(SED) -e 's/blank-//' -e 's/.img//')" exit
	mv $@-t $@

# Make a (dummy) Fedora image.
fedora.img: guest-aux/make-fedora-img.pl \
		guest-aux/fedora-journal.tar.xz \
		guest-aux/fedora-name.db \
		guest-aux/fedora-packages.db
	SRCDIR=$(srcdir) LAYOUT=partitions $(top_builddir)/run --test $<

# Make a (dummy) Fedora image using md devices
fedora-md1.img fedora-md2.img: stamp-fedora-md.img

stamp-fedora-md.img: guest-aux/make-fedora-img.pl \
		guest-aux/fedora-journal.tar.xz \
		guest-aux/fedora-name.db \
		guest-aux/fedora-packages.db
	rm -f $@
	SRCDIR=$(srcdir) LAYOUT=partitions-md $(top_builddir)/run --test $<
	touch $@

fedora-btrfs.img: guest-aux/make-fedora-img.pl \
		guest-aux/fedora-journal.tar.xz \
		guest-aux/fedora-name.db \
		guest-aux/fedora-packages.db
	SRCDIR=$(srcdir) LAYOUT=btrfs $(top_builddir)/run --test $<

# Make a (dummy) Debian image.
debian.img: guest-aux/make-debian-img.sh
	SRCDIR=$(srcdir) $(top_builddir)/run --test $<

# Make a (dummy) Ubuntu image.
ubuntu.img: guest-aux/make-ubuntu-img.sh
	SRCDIR=$(srcdir) $(top_builddir)/run --test $<

# Make a (dummy) Arch Linux image.
archlinux.img: guest-aux/make-archlinux-img.sh
	SRCDIR=$(srcdir) $(top_builddir)/run --test $<

# Make a (dummy) Windows image.
windows.img: guest-aux/make-windows-img.sh \
	     guest-aux/windows-software guest-aux/windows-system
	SRCDIR=$(srcdir) $(top_builddir)/run --test $<

guests-all-good.xml: guest-aux/make-guests-all-good.pl $(disk_images)
	rm -f $@ $@-t
	$^ > $@-t
	mv $@-t $@

# Since users might not have the tools needed to create this, we also
# distribute these files and they are only cleaned by 'make distclean'
# not regular 'make clean'.
guest-aux/fedora-name.db: guest-aux/fedora-name.db.txt
	rm -f $@ $@-t
	$(DB_LOAD) $@-t < $<
	mv $@-t $@

guest-aux/fedora-packages.db: guest-aux/fedora-packages.db.txt
	rm -f $@ $@-t
	$(DB_LOAD) $@-t < $<
	mv $@-t $@

guest-aux/windows-software: guest-aux/windows-software.reg
	rm -f $@ $@-t
	cp $(srcdir)/guest-aux/minimal-hive $@-t
	hivexregedit --merge $@-t --prefix 'HKEY_LOCAL_MACHINE\SOFTWARE' $<
	mv $@-t $@

guest-aux/windows-system: guest-aux/windows-system.reg
	rm -f $@ $@-t
	cp $(srcdir)/guest-aux/minimal-hive $@-t
	hivexregedit --merge $@-t --prefix 'HKEY_LOCAL_MACHINE\SYSTEM' $<
	mv $@-t $@

DISTCLEANFILES = \
	guest-aux/fedora-name.db \
	guest-aux/fedora-packages.db \
	guest-aux/windows-software \
	guest-aux/windows-system

# Don't construct the guests in parallel.  In automake 1.13, check_DATA
# was changed so it can now run in parallel, but this causes everything
# to fall over on machines with limited memory.
#
# ALSO: the guestfish rules above for making the blank-*.img files are
# NOT safe to run in parallel.
.NOTPARALLEL:
