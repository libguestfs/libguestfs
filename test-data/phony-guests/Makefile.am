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
	make-debian-img.sh \
	debian-packages \
	debian-syslog \
	make-fedora-img.pl \
	fedora-journal.tar.xz \
	fedora-name.db.txt \
	fedora-name.db \
	fedora-packages.db.txt \
	fedora-packages.db \
	make-ubuntu-img.sh \
	make-archlinux-img.sh \
	archlinux-package \
	make-coreos-img.sh \
	make-windows-img.sh \
	windows-software \
	windows-software.reg \
	windows-system \
	windows-system.reg \
	minimal-hive \
	make-guests-all-good.pl \
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
	coreos.img \
	windows.img

noinst_DATA = $(disk_images) guests-all-good.xml

CLEANFILES = \
	$(noinst_DATA) \
	guests-all-good.xml \
	stamp-fedora-md.img \
	*.tmp.*

# Make several different blank images.  These are not guests, but we
# include them in the libvirt fake XML to make sure that virt-df and
# virt-alignment-scan don't break when they encounter them.
blank-%.img:
	rm -f $@ $@-t
	$(top_builddir)/run guestfish \
	    -N $@-t="$$(echo $@ | $(SED) -e 's/blank-//' -e 's/.img//')" exit
	mv $@-t $@

# Make a (dummy) Fedora image.
fedora.img: make-fedora-img.pl \
		fedora-journal.tar.xz \
		fedora-name.db \
		fedora-packages.db
	SRCDIR=$(srcdir) LAYOUT=partitions $(top_builddir)/run --test ./$<

# Make a (dummy) Fedora image using md devices
fedora-md1.img fedora-md2.img: stamp-fedora-md.img

stamp-fedora-md.img: make-fedora-img.pl \
		fedora-journal.tar.xz \
		fedora-name.db \
		fedora-packages.db
	rm -f $@
	SRCDIR=$(srcdir) LAYOUT=partitions-md $(top_builddir)/run --test ./$<
	touch $@

fedora-btrfs.img: make-fedora-img.pl \
		fedora-journal.tar.xz \
		fedora-name.db \
		fedora-packages.db
	SRCDIR=$(srcdir) LAYOUT=btrfs $(top_builddir)/run --test ./$<

# Make a (dummy) Debian image.
debian.img: make-debian-img.sh
	SRCDIR=$(srcdir) $(top_builddir)/run --test ./$<

# Make a (dummy) Ubuntu image.
ubuntu.img: make-ubuntu-img.sh
	SRCDIR=$(srcdir) $(top_builddir)/run --test ./$<

# Make a (dummy) Arch Linux image.
archlinux.img: make-archlinux-img.sh
	SRCDIR=$(srcdir) $(top_builddir)/run --test ./$<

# Make a (dummy) CoreOS image.
coreos.img: make-coreos-img.sh
	SRCDIR=$(srcdir) $(top_builddir)/run --test ./$<

# Make a (dummy) Windows image.
windows.img: make-windows-img.sh \
		windows-software \
		windows-system
	SRCDIR=$(srcdir) $(top_builddir)/run --test ./$<

guests-all-good.xml: make-guests-all-good.pl $(disk_images)
	rm -f $@ $@-t
	./$^ > $@-t
	mv $@-t $@

# Since users might not have the tools needed to create this, we also
# distribute these files and they are only cleaned by 'make distclean'
# not regular 'make clean'.
fedora-name.db: fedora-name.db.txt
	rm -f $@ $@-t
	$(DB_LOAD) $@-t < $<
	mv $@-t $@

fedora-packages.db: fedora-packages.db.txt
	rm -f $@ $@-t
	$(DB_LOAD) $@-t < $<
	mv $@-t $@

windows-software: windows-software.reg
	rm -f $@ $@-t
	cp $(srcdir)/minimal-hive $@-t
	hivexregedit --merge $@-t --prefix 'HKEY_LOCAL_MACHINE\SOFTWARE' $<
	mv $@-t $@

windows-system: windows-system.reg
	rm -f $@ $@-t
	cp $(srcdir)/minimal-hive $@-t
	hivexregedit --merge $@-t --prefix 'HKEY_LOCAL_MACHINE\SYSTEM' $<
	mv $@-t $@

DISTCLEANFILES = \
	fedora-name.db \
	fedora-packages.db \
	windows-software \
	windows-system

# Don't construct the guests in parallel.  In automake 1.13, check_DATA
# was changed so it can now run in parallel, but this causes everything
# to fall over on machines with limited memory.
.NOTPARALLEL:
